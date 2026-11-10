import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('prepare_release', ROOT / 'tool/ci/prepare_release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
SHA = 'a' * 40
REPO = 'hayyaun/bottogram'


class ReleasePreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.downloads = self.root / 'downloads'
        self.output = self.root / 'assets'
        for artifact, filename in release.PACKAGES.items():
            folder = self.downloads / artifact
            folder.mkdir(parents=True)
            if artifact == 'bottogram-linux-x86_64':
                self.linux_archive(folder / filename)
            else:
                data = f'fixture-{filename}'.encode()
                (folder / filename).write_bytes(data)
                (folder / 'SHA256SUMS.txt').write_bytes(
                    f'{hashlib.sha256(data).hexdigest()}  {filename}\r\n'.encode()
                )

    def tearDown(self):
        self.temp.cleanup()

    def linux_archive(self, path, *, tamper=False, executable=True, extra=None):
        data = b'executable AppImage fixture'
        digest = hashlib.sha256(data).hexdigest()
        if tamper:
            data += b'tampered'
        with tarfile.open(path, 'w:gz') as archive:
            image = tarfile.TarInfo(release.LINUX_IMAGE)
            image.size = len(data)
            image.mode = 0o755 if executable else 0o644
            archive.addfile(image, io.BytesIO(data))
            checksum = f'{digest}  {release.LINUX_IMAGE}\n'.encode()
            entry = tarfile.TarInfo('SHA256SUMS.txt')
            entry.size = len(checksum)
            archive.addfile(entry, io.BytesIO(checksum))
            if extra:
                item = tarfile.TarInfo(extra)
                item.size = 1
                archive.addfile(item, io.BytesIO(b'x'))

    def reject(self):
        with self.assertRaises(ValueError):
            release.prepare_assets(self.downloads, self.output)
        self.assertFalse(self.output.exists(), 'Rejected input produced publishable assets')

    def test_valid_platform_assets_and_combined_checksums(self):
        release.prepare_assets(self.downloads, self.output)
        self.assertEqual(
            {p.name for p in self.output.iterdir()},
            set(release.PACKAGES.values()) | {'SHA256SUMS.txt'},
        )
        checksums = (self.output / 'SHA256SUMS.txt').read_text().splitlines()
        self.assertEqual(len(checksums), 5)
        for line in checksums:
            digest, filename = line.split('  ')
            self.assertEqual(digest, hashlib.sha256((self.output / filename).read_bytes()).hexdigest())

    def test_tampered_android_payload_is_rejected(self):
        (self.downloads / 'bottogram-android-release' / 'bottogram-android-release.apk').write_bytes(b'tampered')
        self.reject()

    def test_missing_installer_is_rejected(self):
        shutil.rmtree(self.downloads / 'bottogram-windows-x64-installer')
        self.reject()

    def test_tampered_installer_is_rejected(self):
        (self.downloads / 'bottogram-windows-x64-installer' / 'bottogram-windows-x64-setup.exe').write_bytes(b'tampered')
        self.reject()

    def test_missing_macos_artifact_is_rejected(self):
        shutil.rmtree(self.downloads / 'bottogram-macos-universal')
        self.reject()

    def test_missing_windows_checksum_is_rejected(self):
        (self.downloads / 'bottogram-windows-x64' / 'SHA256SUMS.txt').unlink()
        self.reject()

    def test_wrong_checksum_filename_is_rejected(self):
        checksum = self.downloads / 'bottogram-windows-x64' / 'SHA256SUMS.txt'
        checksum.write_text(checksum.read_text().replace('bottogram-windows-x64.zip', '../payload.zip'))
        self.reject()

    def test_tampered_linux_payload_is_rejected(self):
        self.linux_archive(self.downloads / 'bottogram-linux-x86_64' / release.PACKAGES['bottogram-linux-x86_64'], tamper=True)
        self.reject()

    def test_nonexecutable_linux_payload_is_rejected(self):
        self.linux_archive(self.downloads / 'bottogram-linux-x86_64' / release.PACKAGES['bottogram-linux-x86_64'], executable=False)
        self.reject()

    def test_linux_archive_path_traversal_is_rejected(self):
        self.linux_archive(self.downloads / 'bottogram-linux-x86_64' / release.PACKAGES['bottogram-linux-x86_64'], extra='../escape')
        self.reject()
        self.assertFalse((self.root / 'escape').exists())

    def test_symlinked_payload_is_rejected(self):
        payload = self.downloads / 'bottogram-macos-universal' / 'bottogram-macos-universal.zip'
        other = self.root / 'elsewhere'
        payload.rename(other)
        payload.symlink_to(other)
        self.reject()

    def test_extra_platform_file_is_rejected(self):
        (self.downloads / 'bottogram-windows-x64' / 'unexpected.txt').write_text('unexpected')
        self.reject()

    def test_zero_length_payload_is_rejected(self):
        (self.downloads / 'bottogram-android-release' / 'bottogram-android-release.apk').write_bytes(b'')
        self.reject()

    def test_tag_matches_pubspec_without_build_number(self):
        pubspec = self.root / 'pubspec.yaml'
        pubspec.write_text('name: fixture\nversion: 1.0.0+1\n')
        self.assertEqual(release.validate_version('v1.0.0', pubspec), '1.0.0')
        for tag in ('v1.0.1', 'v01.0.0', '1.0.0', 'v1.0.0-rc.1', 'v1.0.0+1', 'v1.0.0\n'):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release.validate_version(tag, pubspec)

    def test_only_exact_successful_push_main_run_is_selected(self):
        valid = dict(id=42, head_sha=SHA, head_branch='main', event='push', status='completed',
                     conclusion='success', path='.github/workflows/build.yml',
                     head_repository={'full_name': REPO}, run_number=3, run_attempt=1)
        for field, wrong in (('head_sha', 'b'*40), ('head_branch', 'dev'), ('event', 'pull_request'),
                             ('status', 'in_progress'), ('conclusion', 'failure'),
                             ('path', '.github/workflows/release.yml'), ('head_repository', {'full_name':'someone/fork'})):
            invalid = {**valid, field: wrong, 'id': 100}
            with self.subTest(field=field):
                self.assertEqual(release.select_build_run([{'workflow_runs':[invalid, valid]}], REPO, SHA)['id'], 42)
                with self.assertRaises(ValueError):
                    release.select_build_run([{'workflow_runs':[invalid]}], REPO, SHA)

    def test_selection_uses_paginated_exact_successful_runs(self):
        valid = dict(id=42, head_sha=SHA, head_branch='main', event='push', status='completed',
                     conclusion='success', path='.github/workflows/build.yml@main',
                     head_repository={'full_name': REPO}, run_number=3, run_attempt=1)
        newer = {**valid, 'id': 43, 'run_number': 4}
        self.assertEqual(release.select_build_run([{'workflow_runs':[valid]}, {'workflow_runs':[newer]}], REPO, SHA)['id'], 43)


if __name__ == '__main__':
    unittest.main(verbosity=2)
