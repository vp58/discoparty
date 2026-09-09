from __future__ import annotations

import os
import json
import hashlib
import pwd
import stat
import subprocess
import argparse
from dataclasses import dataclass
from tempfile import TemporaryDirectory
from pathlib import Path


# The child receives an allowlist, not a copy of the launchd environment. In
# particular, API keys and the Discord token never enter the App Server child.
SAFE_ENV_VARS = {"LANG", "LC_ALL", "LC_CTYPE", "TERM", "TZ"}
SUPPORTED_CODEX_VERSION = "codex-cli 0.153.4"
SUPPORTED_LAUNCHER_REALPATH = Path(
    "/opt/homebrew/lib/node_modules/@openai/codex/bin/codex.js"
)
SUPPORTED_LAUNCHER_SHA256 = "61b0194f3bb6534439c8d26a3ed57d0805f84b884588b761795323eeb92fcf70"
SUPPORTED_NATIVE_REALPATH = Path(
    "/opt/homebrew/lib/node_modules/@openai/codex/node_modules/@openai/"
    "codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex"
)
SUPPORTED_NATIVE_SHA256 = "b973d440acac501fd2594a43e7ca9ce41e0a65b9dfb28d0d7a7837c99e1261e3"
SUPPORTED_EXPERIMENTAL_SCHEMA_SHA256 = (
    "2c84857334e81aef586066634d753df4d570ada5e54aa5125c51bf6229f1c9ec"
)
EXPECTED_SERVER_REQUEST_METHODS = {
    "item/commandExecution/requestApproval",
    "item/fileChange/requestApproval",
    "item/tool/requestUserInput",
    "mcpServer/elicitation/request",
    "item/permissions/requestApproval",
    "item/tool/call",
    "account/chatgptAuthTokens/refresh",
    "attestation/generate",
    "currentTime/read",
    "applyPatchApproval",
    "execCommandApproval",
}
ACCOUNT_BINDING_VERSION = 2
CHATGPT_PLAN_TYPES = frozenset(
    {
        "free",
        "go",
        "plus",
        "pro",
        "prolite",
        "team",
        "self_serve_business_prolite",
        "self_serve_business_usage_based",
        "business",
        "ent26",
        "enterprise_cbp_automation",
        "enterprise_cbp_usage_based",
        "enterprise",
        "edu",
        "edu_plus",
        "edu_pro",
        "unknown",
    }
)


@dataclass(frozen=True)
class ChatGPTAccountBinding:
    """Nonsecret identity facts returned by the official App Server."""

    digest: str
    plan_type: str


def _validate_codex_home(codex_home: Path) -> Path:
    if not codex_home.is_absolute() or ".." in codex_home.parts:
        raise RuntimeError("isolated CODEX_HOME path is unsafe")
    try:
        home_metadata = codex_home.lstat()
    except OSError as exc:
        raise RuntimeError("isolated CODEX_HOME is unavailable") from exc
    if (
        stat.S_ISLNK(home_metadata.st_mode)
        or not stat.S_ISDIR(home_metadata.st_mode)
        or home_metadata.st_uid != os.getuid()
        or stat.S_IMODE(home_metadata.st_mode) != 0o700
    ):
        raise RuntimeError("isolated CODEX_HOME must be a private, owned real directory")
    try:
        canonical = codex_home.resolve(strict=True)
    except OSError as exc:
        raise RuntimeError("isolated CODEX_HOME is unavailable") from exc
    if canonical != Path(os.path.normpath(os.fspath(codex_home))):
        raise RuntimeError("isolated CODEX_HOME must use its canonical path")
    return canonical


def reject_filesystem_credentials(codex_home: Path) -> None:
    """Reject official Codex filesystem auth artifacts without reading them.

    Keyring mode stores credentials in macOS Keychain. An ``auth.json`` or a
    sibling backup/temp variant means the process is no longer keyring only.
    """

    canonical = _validate_codex_home(codex_home)
    directory_flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    directory_flags |= getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0)
    descriptor = os.open(canonical, directory_flags)
    try:
        with os.scandir(descriptor) as entries:
            for entry in entries:
                name = entry.name.casefold()
                if (
                    name in {"auth.json", ".auth.json"}
                    or name.startswith("auth.json.")
                    or name.startswith(".auth.json.")
                    or name in {".credentials.json", "credentials.json", "secrets"}
                    or name.startswith(".credentials.json.")
                    or name.startswith("credentials.json.")
                ):
                    raise RuntimeError(
                        "filesystem Codex credential artifacts are forbidden in isolated CODEX_HOME"
                    )
    finally:
        os.close(descriptor)


def chatgpt_account_binding(result: object) -> ChatGPTAccountBinding:
    """Bind nonsecret ``account/read`` facts without exposing the email value."""

    if not isinstance(result, dict) or result.get("requiresOpenaiAuth") is not True:
        raise RuntimeError("Codex App Server returned an invalid authentication state")
    account = result.get("account")
    if not isinstance(account, dict) or set(account) != {
        "type",
        "email",
        "planType",
    }:
        raise RuntimeError("Codex App Server returned a malformed ChatGPT account")
    if account.get("type") != "chatgpt":
        raise RuntimeError("Codex App Server is not using ChatGPT subscription authentication")
    plan_type = account.get("planType")
    if plan_type not in CHATGPT_PLAN_TYPES:
        raise RuntimeError("Codex App Server returned an unsupported ChatGPT plan")
    email = account.get("email")
    if (
        not isinstance(email, str)
        or not email
        or email.strip() != email
        or len(email.encode("utf-8")) > 512
        or any(ord(character) < 0x20 or ord(character) == 0x7F for character in email)
    ):
        raise RuntimeError("Codex App Server returned a malformed ChatGPT identity")
    identity = email.encode("utf-8")
    digest = hashlib.sha256(b"discoparty-chatgpt-account-read-v2\0")
    for component in (identity, plan_type.encode("ascii")):
        digest.update(len(component).to_bytes(4, "big"))
        digest.update(component)
    return ChatGPTAccountBinding(digest=digest.hexdigest(), plan_type=plan_type)


def canonical_user_home() -> Path:
    account = pwd.getpwuid(os.getuid())
    configured_home = Path(account.pw_dir)
    if not configured_home.is_absolute() or ".." in configured_home.parts:
        raise RuntimeError("canonical user HOME is unsafe")
    try:
        real_home = configured_home.resolve(strict=True)
        home_metadata = real_home.stat()
    except OSError as exc:
        raise RuntimeError("canonical user HOME is unavailable") from exc
    if real_home != Path(os.path.normpath(os.fspath(configured_home))):
        raise RuntimeError("canonical user HOME must use its real path")
    if (
        not stat.S_ISDIR(home_metadata.st_mode)
        or home_metadata.st_uid != os.getuid()
        or stat.S_IMODE(home_metadata.st_mode) & 0o022
    ):
        raise RuntimeError("canonical user HOME is unsafe")
    return real_home


def child_environment(
    worker_home: Path | None = None,
    *,
    codex_home: Path | None = None,
    tmp_dir: Path | None = None,
) -> dict[str, str]:
    env = {k: os.environ[k] for k in SAFE_ENV_VARS if k in os.environ}
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    account = pwd.getpwuid(os.getuid())
    real_home = canonical_user_home()
    if codex_home is None:
        codex_home = real_home / ".codex"
    if tmp_dir is None:
        tmp_dir = real_home / "tmp"
    env["HOME"] = str(real_home)
    env["USER"] = account.pw_name
    env["LOGNAME"] = account.pw_name
    env["CODEX_HOME"] = str(codex_home)
    env["TMPDIR"] = str(tmp_dir)
    return env


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _reviewed_native_binary(codex_bin: Path) -> Path:
    """Verify the npm launcher and return the reviewed native executable.

    The Node launcher is treated only as installed-package evidence. It is never
    executed because its runtime resolution could select a different native
    package than the one reviewed here.
    """

    try:
        launcher = codex_bin.resolve(strict=True)
    except OSError as exc:
        raise RuntimeError("Codex launcher cannot be resolved") from exc
    if launcher != SUPPORTED_LAUNCHER_REALPATH:
        raise RuntimeError(f"Codex launcher path changed: {launcher}")
    try:
        launcher_hash = _sha256(launcher)
    except OSError as exc:
        raise RuntimeError("Codex launcher cannot be read") from exc
    if launcher_hash != SUPPORTED_LAUNCHER_SHA256:
        raise RuntimeError("Codex launcher hash changed")

    try:
        native = SUPPORTED_NATIVE_REALPATH.resolve(strict=True)
    except OSError as exc:
        raise RuntimeError("reviewed Codex Apple Silicon binary is unavailable") from exc
    if native != SUPPORTED_NATIVE_REALPATH or not native.is_file():
        raise RuntimeError("reviewed Codex Apple Silicon binary path changed")
    try:
        native_hash = _sha256(native)
    except OSError as exc:
        raise RuntimeError("reviewed Codex Apple Silicon binary cannot be read") from exc
    if native_hash != SUPPORTED_NATIVE_SHA256:
        raise RuntimeError("reviewed Codex Apple Silicon binary hash changed")
    return native


def require_chatgpt_login(
    codex_bin: Path,
    worker_home: Path | None = None,
    *,
    codex_home: Path | None = None,
    tmp_dir: Path | None = None,
) -> None:
    effective_codex_home = codex_home or canonical_user_home() / ".codex"
    reject_filesystem_credentials(effective_codex_home)
    native = _reviewed_native_binary(codex_bin)
    try:
        result = subprocess.run(
            [str(native), "login", "status"],
            env=child_environment(
                worker_home, codex_home=codex_home, tmp_dir=tmp_dir
            ),
            text=True,
            capture_output=True,
            timeout=15,
            check=False,
        )
    finally:
        reject_filesystem_credentials(effective_codex_home)
    combined = f"{result.stdout}\n{result.stderr}"
    if result.returncode != 0 or "Logged in using ChatGPT" not in combined:
        raise RuntimeError("Codex must be authenticated with ChatGPT; API-key mode is forbidden")


def require_chatgpt_logged_out(
    codex_bin: Path,
    worker_home: Path | None = None,
    *,
    codex_home: Path | None = None,
    tmp_dir: Path | None = None,
) -> None:
    """Prove the exact isolated CODEX_HOME has no active ChatGPT login."""

    effective_codex_home = codex_home or canonical_user_home() / ".codex"
    reject_filesystem_credentials(effective_codex_home)
    native = _reviewed_native_binary(codex_bin)
    try:
        result = subprocess.run(
            [str(native), "login", "status"],
            env=child_environment(
                worker_home, codex_home=codex_home, tmp_dir=tmp_dir
            ),
            stdin=subprocess.DEVNULL,
            text=True,
            capture_output=True,
            timeout=15,
            check=False,
        )
    finally:
        reject_filesystem_credentials(effective_codex_home)
    combined = f"{result.stdout}\n{result.stderr}"
    if (
        result.returncode != 0
        or "Not logged in" not in combined
        or "Logged in using" in combined
    ):
        raise RuntimeError("Codex ChatGPT logout could not be verified")


def logout_chatgpt(
    codex_bin: Path,
    worker_home: Path | None = None,
    *,
    codex_home: Path | None = None,
    tmp_dir: Path | None = None,
) -> None:
    """Remove only the official credential scoped to the isolated CODEX_HOME."""

    effective_codex_home = codex_home or canonical_user_home() / ".codex"
    reject_filesystem_credentials(effective_codex_home)
    native = _reviewed_native_binary(codex_bin)
    try:
        result = subprocess.run(
            [str(native), "logout"],
            env=child_environment(
                worker_home, codex_home=codex_home, tmp_dir=tmp_dir
            ),
            stdin=subprocess.DEVNULL,
            text=True,
            capture_output=True,
            timeout=30,
            check=False,
        )
    finally:
        reject_filesystem_credentials(effective_codex_home)
    if result.returncode != 0:
        raise RuntimeError("official Codex logout failed for the isolated CODEX_HOME")
    require_chatgpt_logged_out(
        codex_bin,
        worker_home,
        codex_home=codex_home,
        tmp_dir=tmp_dir,
    )


def require_supported_cli(
    codex_bin: Path,
    worker_home: Path | None = None,
    *,
    codex_home: Path | None = None,
    tmp_dir: Path | None = None,
) -> str:
    effective_codex_home = codex_home or canonical_user_home() / ".codex"
    reject_filesystem_credentials(effective_codex_home)
    native = _reviewed_native_binary(codex_bin)
    try:
        result = subprocess.run(
            [str(native), "--version"],
            env=child_environment(
                worker_home, codex_home=codex_home, tmp_dir=tmp_dir
            ),
            text=True,
            capture_output=True,
            timeout=15,
            check=False,
        )
    finally:
        reject_filesystem_credentials(effective_codex_home)
    version = result.stdout.strip()
    if result.returncode != 0 or version != SUPPORTED_CODEX_VERSION:
        raise RuntimeError(
            f"Codex App Server protocol is pinned to {SUPPORTED_CODEX_VERSION}; got {version or 'unknown'}"
        )
    return version


def _schema_bundle_hash(root: Path) -> str:
    digest = hashlib.sha256()
    files = sorted(root.rglob("*.json"))
    for path in files:
        relative = path.relative_to(root).as_posix().encode()
        content = path.read_bytes()
        digest.update(len(relative).to_bytes(4, "big"))
        digest.update(relative)
        digest.update(len(content).to_bytes(8, "big"))
        digest.update(content)
    return digest.hexdigest()


def require_supported_protocol(
    codex_bin: Path,
    worker_home: Path | None = None,
    *,
    codex_home: Path | None = None,
    tmp_dir: Path | None = None,
) -> set[str]:
    effective_codex_home = codex_home or canonical_user_home() / ".codex"
    reject_filesystem_credentials(effective_codex_home)
    native = _reviewed_native_binary(codex_bin)
    with TemporaryDirectory(prefix="codex-app-schema-") as tmp:
        try:
            result = subprocess.run(
                [
                    str(native),
                    "app-server",
                    "generate-json-schema",
                    "--experimental",
                    "--out",
                    tmp,
                ],
                env=child_environment(
                    worker_home, codex_home=codex_home, tmp_dir=tmp_dir
                ),
                text=True,
                capture_output=True,
                timeout=30,
                check=False,
            )
        finally:
            reject_filesystem_credentials(effective_codex_home)
        if result.returncode != 0:
            raise RuntimeError("Codex could not generate its official experimental protocol schema")
        schema_root = Path(tmp)
        schema = json.loads((schema_root / "ServerRequest.json").read_text())
        bundle_hash = _schema_bundle_hash(schema_root)
        if bundle_hash != SUPPORTED_EXPERIMENTAL_SCHEMA_SHA256:
            raise RuntimeError(
                f"Codex experimental schema bundle changed: {bundle_hash}"
            )
    methods: set[str] = set()
    for variant in schema.get("oneOf", []):
        methods.update(variant.get("properties", {}).get("method", {}).get("enum", []))
    if methods != EXPECTED_SERVER_REQUEST_METHODS:
        added = sorted(methods - EXPECTED_SERVER_REQUEST_METHODS)
        removed = sorted(EXPECTED_SERVER_REQUEST_METHODS - methods)
        raise RuntimeError(
            f"Codex experimental ServerRequest schema changed; added={added}, removed={removed}"
        )
    return methods


def app_server_command(
    codex_bin: Path,
    worker_home: Path,
    *,
    codex_home: Path | None = None,
    tmp_dir: Path | None = None,
) -> list[str]:
    require_chatgpt_login(
        codex_bin, worker_home, codex_home=codex_home, tmp_dir=tmp_dir
    )
    require_supported_cli(
        codex_bin, worker_home, codex_home=codex_home, tmp_dir=tmp_dir
    )
    require_supported_protocol(
        codex_bin, worker_home, codex_home=codex_home, tmp_dir=tmp_dir
    )
    native = _reviewed_native_binary(codex_bin)
    return [
        str(native),
        "--dangerously-bypass-hook-trust",
        "app-server",
        "--listen",
        "stdio://",
        "--strict-config",
    ]


def _logout_configured_chatgpt() -> None:
    """Logout entry point for ``uninstall.sh --codex``."""

    from .config import Config
    from .codex_policy import validate_isolated_config

    config = Config.from_discoparty()
    safe_mode = config.sandbox_mode == "workspace-write"
    validate_isolated_config(config.codex_home, config.working_directory, safe_mode)
    try:
        logout_chatgpt(
            config.codex_bin,
            codex_home=config.codex_home,
            tmp_dir=config.state_dir / "tmp",
        )
    finally:
        validate_isolated_config(
            config.codex_home,
            config.working_directory,
            safe_mode,
        )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Disco Party Codex auth lifecycle")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser(
        "logout-configured",
        help="logout the exact isolated ChatGPT credential from Disco Party config",
    )
    args = parser.parse_args(argv)
    if args.command == "logout-configured":
        _logout_configured_chatgpt()
        print("Isolated ChatGPT logout verified.")
        return 0
    raise AssertionError(args.command)


if __name__ == "__main__":
    raise SystemExit(main())
