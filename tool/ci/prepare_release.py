#!/usr/bin/env python3
"""Prepare release assets from one successful main build; never publish or rebuild."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile


PACKAGES = {
    "bottogram-android-release": "bottogram-android-release.apk",
    "bottogram-windows-x64": "bottogram-windows-x64.zip",
    "bottogram-windows-x64-installer": "bottogram-windows-x64-setup.exe",
    "bottogram-macos-universal": "bottogram-macos-universal.zip",
    "bottogram-linux-x86_64": "bottogram-linux-x86_64.AppImage.tar.gz",
}
LINUX_IMAGE = "bottogram-linux-x86_64.AppImage"
STABLE_VERSION = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"


def validate_version(tag: str, pubspec: Path) -> str:
    if not re.fullmatch(rf"v{STABLE_VERSION}", tag):
        raise ValueError("Release tags must be stable SemVer: vMAJOR.MINOR.PATCH.")
    versions = re.findall(
        r"^version:\s*([^\s#]+)\s*(?:#.*)?$", pubspec.read_text(encoding="utf-8"), re.M,
    )
    if len(versions) != 1 or not re.fullmatch(
        rf"{STABLE_VERSION}(?:\+[0-9]+)?", versions[0]
    ):
        raise ValueError("pubspec.yaml must have one stable version with optional +build number.")
    version = versions[0].split("+", 1)[0]
    if tag != f"v{version}":
        raise ValueError(f"Tag {tag} does not match pubspec.yaml version {versions[0]}.")
    return version


def gh_json(*arguments: str):
    result = subprocess.run(
        ["gh", "api", "--method", "GET", "-H", "Accept: application/vnd.github+json",
         *arguments],
        check=True, stdout=subprocess.PIPE, text=True,
    )
    return json.loads(result.stdout)


def select_build_run(pages: list, repo: str, sha: str) -> dict:
    candidates = [
        run
        for page in pages
        for run in page["workflow_runs"]
        if run.get("head_sha") == sha
        and run.get("head_branch") == "main"
        and run.get("event") == "push"
        and run.get("status") == "completed"
        and run.get("conclusion") == "success"
        and run.get("path", "").split("@", 1)[0] == ".github/workflows/build.yml"
        and (run.get("head_repository") or {}).get("full_name") == repo
    ]
    if not candidates:
        raise ValueError(
            f"No successful push/main build.yml run exists for exact commit {sha}. "
            "Wait for that commit's complete build to pass before publishing its tag."
        )
    return max(candidates, key=lambda run: (run["run_number"], run["run_attempt"], run["id"]))


def require_file(path: Path) -> None:
    if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f"Expected a nonempty regular file: {path}")


def verify_checksum(text: str, filename: str, digest: str) -> None:
    lines = text.splitlines()
    if len(lines) != 1:
        raise ValueError(f"Expected exactly one SHA-256 entry for {filename}.")
    match = re.fullmatch(r"([0-9a-fA-F]{64}) [ *](.+)", lines[0])
    if not match or match[2] != filename or match[1].lower() != digest:
        raise ValueError(f"SHA-256 verification failed for {filename}.")


def stream_digest(stream) -> str:
    digest = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b""):
        digest.update(block)
    return digest.hexdigest()


def file_digest(path: Path) -> str:
    with path.open("rb") as stream:
        return stream_digest(stream)


def verify_linux_archive(path: Path) -> None:
    # Read the two expected regular members without extracting arbitrary paths.
    with tarfile.open(path, "r:gz") as archive:
        members = archive.getmembers()
        if len(members) != 2 or {member.name for member in members} != {
            LINUX_IMAGE, "SHA256SUMS.txt"
        } or any(not member.isfile() for member in members):
            raise ValueError("Linux archive must contain only the AppImage and SHA256SUMS.txt.")
        image = archive.getmember(LINUX_IMAGE)
        if image.size == 0 or not image.mode & 0o111:
            raise ValueError("Linux AppImage must be nonempty and executable in its archive.")
        with archive.extractfile(image) as stream:
            digest = stream_digest(stream)
        with archive.extractfile("SHA256SUMS.txt") as stream:
            verify_checksum(stream.read().decode("ascii"), LINUX_IMAGE, digest)


def prepare_assets(downloads: Path, output: Path) -> None:
    if {path.name for path in downloads.iterdir()} != set(PACKAGES):
        raise ValueError("All expected platform artifact directories are required.")
    verified = []
    for artifact, filename in PACKAGES.items():
        directory = downloads / artifact
        if directory.is_symlink() or not directory.is_dir():
            raise ValueError(f"Expected an artifact directory: {directory}")
        expected = {filename} if artifact == "bottogram-linux-x86_64" else {
            filename, "SHA256SUMS.txt"
        }
        if {path.name for path in directory.iterdir()} != expected:
            raise ValueError(f"Unexpected or missing files in artifact {artifact}.")
        payload = directory / filename
        require_file(payload)
        digest = file_digest(payload)
        if artifact == "bottogram-linux-x86_64":
            verify_linux_archive(payload)
        else:
            checksum = directory / "SHA256SUMS.txt"
            require_file(checksum)
            verify_checksum(checksum.read_text(encoding="ascii"), filename, digest)
        verified.append((payload, digest))

    # Validate everything before producing any publishable assets.
    output.mkdir(parents=True, exist_ok=False)
    for payload, _ in verified:
        shutil.copyfile(payload, output / payload.name)
    (output / "SHA256SUMS.txt").write_text(
        "".join(f"{digest}  {payload.name}\n" for payload, digest in verified),
        encoding="ascii",
    )


def release_notes(version: str, repo: str, sha: str, run: dict) -> str:
    source = f"https://github.com/{repo}"
    run_url = f"{source}/actions/runs/{run['id']}"
    return f"""Bottogram {version} runs Telegram bots on your own device.

On Android, the foreground notification shows active and total bots. Reopening
Bottogram after a process kill or device restart resumes the bots left enabled.
Use Stop bots to keep them stopped on the next launch.

Plugin bots can transfer their settings and credentials by QR code between
devices with the exact plugin package installed. Treat the QR code as a
credential. Approved plugin updates restart bots that were already running.

Bottogram includes Telegram Mini Apps, per-bot SQLite storage, bot templates, and
the Persian Inshopa storefront plugin.

### Downloads

- Android: install `bottogram-android-release.apk`, signed with Bottogram's permanent Android key.
- Windows x64: extract the entire `bottogram-windows-x64.zip` before opening `bottogram.exe`.
- Windows installer: run `bottogram-windows-x64-setup.exe` for a per-user installation with a Start menu shortcut and uninstaller. A desktop shortcut is optional. Uninstalling preserves saved bot data.
- macOS Intel and Apple silicon: extract `bottogram-macos-universal.zip`. The app is ad-hoc signed, without Developer ID signing or Apple notarization; macOS may block opening it.
- Linux x86_64: extract `bottogram-linux-x86_64.AppImage.tar.gz` and run the AppImage. A desktop keyring and FUSE are required; Ubuntu 22.04 or newer is the build target.

Check each downloaded package against the attached `SHA256SUMS.txt`. Both Windows
packages include the required Visual C++ runtime DLLs. The Windows installer and
app are unsigned; Windows may show a publisher warning. macOS does not include an
installer. Clean-machine compatibility is not established by CI.

### Build verification

All five packages come from the same [successful main build]({run_url})
(attempt {run['run_attempt']}) for [commit `{sha}`]({source}/commit/{sha}).
Analysis, automated tests, native SQLite/template integration, Android service
continuity, macOS credential storage, and released native-library probes passed
in that run.

See the [build and distribution guide]({source}/blob/{sha}/docs/BUILD_ARTIFACTS.md)
and [plugin authoring guide]({source}/blob/{sha}/docs/PLUGIN_AUTHORING.md).
"""


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--work-dir", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.sha):
        raise ValueError("A full lowercase commit SHA is required.")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repo):
        raise ValueError("Repository must be OWNER/REPO.")
    root = Path(__file__).resolve().parents[2]
    version = validate_version(args.tag, root / "pubspec.yaml")
    head = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=root, check=True, capture_output=True, text=True,
    ).stdout.strip()
    if head != args.sha:
        raise ValueError("The checked-out tag commit does not match the requested build SHA.")
    if args.work_dir.exists():
        raise ValueError("Release work directory already exists; use a fresh workspace.")

    pages = gh_json(
        f"repos/{args.repo}/actions/workflows/build.yml/runs",
        "-f", "branch=main", "-f", "event=push", "-f", "status=success",
        "-f", f"head_sha={args.sha}", "-f", "per_page=100", "--paginate", "--slurp",
    )
    run = select_build_run(pages, args.repo, args.sha)
    print(f"Using successful main build {run['id']} for {args.sha}.")
    args.work_dir.mkdir(parents=True)
    downloads = args.work_dir / "downloads"
    for artifact in PACKAGES:
        subprocess.run(
            ["gh", "run", "download", str(run["id"]), "--repo", args.repo,
             "--name", artifact, "--dir", str(downloads / artifact)],
            check=True,
        )
    prepare_assets(downloads, args.work_dir / "assets")
    (args.work_dir / "notes.md").write_text(
        release_notes(version, args.repo, args.sha, run), encoding="utf-8",
    )
    (args.work_dir / "build-run.json").write_text(
        json.dumps(run, indent=2) + "\n", encoding="utf-8",
    )
    print("Verified five platform packages and wrote combined SHA256SUMS.txt.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, tarfile.TarError, subprocess.CalledProcessError) as error:
        print(f"Release preparation failed: {error}", file=sys.stderr)
        sys.exit(1)
