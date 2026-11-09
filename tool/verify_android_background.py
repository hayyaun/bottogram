"""Observe the integration test on the task's disposable, read-only emulator.

Run alongside flutter test -d emulator-5554 integration_test/background_service_test.dart.
Only Android's documented adb testing commands are used; no production debug API.
"""
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
LOG = ROOT / 'build/verification/android-service-integration.log'
REPORT = ROOT / 'build/verification/android-background-observation.json'
ADB = '/home/garfield/Android/Sdk/platform-tools/adb'
SERIAL = 'emulator-5554'
PACKAGE = 'com.hayyaun.bottogram.bottogram'


def adb(*args):
    return subprocess.run([ADB, '-s', SERIAL, *args], check=True,
                          capture_output=True, text=True, timeout=12).stdout.strip()


def main():
    # Never change idle/battery settings on a personal device or writable AVD.
    candidates = []
    for path in Path('/proc').glob('[0-9]*/cmdline'):
        try:
            candidates.append(path.read_bytes())
        except (OSError, PermissionError):
            pass
    if not any(b'qemu-system' in c and b'-read-only' in c and b'-no-window' in c
               and b'@Resizable_Experimental_API_35' in c for c in candidates):
        raise RuntimeError('The disposable read-only test emulator is required.')
    if not adb('emu', 'avd', 'name').startswith('Resizable_Experimental_API_35'):
        raise RuntimeError('Unexpected emulator identity.')
    report = {}
    deadline = time.monotonic() + 900
    resumed = False
    changed = False
    try:
        while time.monotonic() < deadline:
            text = LOG.read_text(errors='replace') if LOG.exists() else ''
            if 'All tests passed!' in text:
                raise RuntimeError('Start a fresh integration test log before this observer.')
            # Resume a deliberately paused emulator as compilation completes.
            if not resumed and ('Built build/' in text or 'Installing ' in text):
                report['emulator_resume'] = adb('emu', 'avd', 'start')
                resumed = True
            if 'BACKGROUND_PROBE_START' in text:
                report['package_pid'] = adb('shell', 'pidof', PACKAGE)
                services = adb('shell', 'dumpsys', 'activity', 'services', PACKAGE)
                report['foreground_service'] = 'isForeground=true' in services
                report['service_dump'] = services
                activities = adb('shell', 'dumpsys', 'activity', 'activities')
                report['resumed_activity_lines'] = [line.strip() for line in activities.splitlines()
                                                    if 'mResumedActivity' in line or 'topResumedActivity' in line]
                report['wake_lock_lines'] = [line.strip() for line in adb('shell', 'dumpsys', 'power').splitlines()
                                             if 'bottogram:running-bots' in line]
                adb('shell', 'cmd', 'deviceidle', 'whitelist', '+' + PACKAGE)
                changed = True
                adb('shell', 'dumpsys', 'battery', 'unplug')
                adb('shell', 'input', 'keyevent', 'KEYCODE_SLEEP')
                report['force_idle'] = adb('shell', 'cmd', 'deviceidle', 'force-idle')
                report['idle_state_lines'] = [line.strip() for line in adb('shell', 'dumpsys', 'deviceidle').splitlines()
                                               if 'mState=' in line or 'mLightState=' in line]
                REPORT.write_text(json.dumps(report, indent=2))
                print('Background service and idle-state observation saved.', flush=True)
                while time.monotonic() < deadline:
                    text = LOG.read_text(errors='replace')
                    if 'BACKGROUND_PROBE_END' in text or 'Some tests failed' in text:
                        report['test_result_lines'] = [line for line in text.splitlines()
                                                       if 'BACKGROUND_PROBE_' in line or 'tests passed' in line or 'tests failed' in line]
                        return
                    time.sleep(1)
                raise TimeoutError('Background probe did not finish.')
            if 'Some tests failed' in text or 'FAILURE:' in text:
                raise RuntimeError('Android integration build/test failed; see its log.')
            time.sleep(1)
        raise TimeoutError('Android integration probe did not start.')
    finally:
        if changed:
            for args in [('shell', 'cmd', 'deviceidle', 'unforce'),
                         ('shell', 'dumpsys', 'battery', 'reset'),
                         ('shell', 'cmd', 'deviceidle', 'whitelist', '-' + PACKAGE)]:
                try:
                    adb(*args)
                except (subprocess.SubprocessError, OSError) as error:
                    report.setdefault('cleanup_errors', []).append(type(error).__name__)
        REPORT.write_text(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
