#!/usr/bin/env python3
"""Probe the actual desktop release libraries, never a system SQLite fallback."""

import argparse
import ctypes
import json
import os
from pathlib import Path
import sys

SOURCE_ID = (
    "2026-10-16 14:45:20 "
    "555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76"
)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("library_directory", type=Path)
    args = parser.parse_args()
    directory = args.library_directory.resolve(strict=True)
    if sys.platform == "win32":
        core_name, guard_name = "sqlite3.dll", "bottogram_sqlite_guard.dll"
    elif sys.platform == "linux":
        core_name, guard_name = "libsqlite3.so", "libbottogram_sqlite_guard.so"
    else:
        parser.error("This desktop bundle probe supports Linux and Windows.")
    # Keep this documented Windows DLL search context alive throughout the probe.
    dll_directory = os.add_dll_directory(str(directory)) if os.name == "nt" else None
    try:
        core = ctypes.CDLL(str((directory / core_name).resolve(strict=True)))
        guard = ctypes.CDLL(str((directory / guard_name).resolve(strict=True)))
        core.sqlite3_libversion_number.restype = ctypes.c_int
        core.sqlite3_sourceid.restype = ctypes.c_char_p
        require(core.sqlite3_libversion_number() == 3054001, "Unexpected SQLite version")
        require(core.sqlite3_sourceid().decode() == SOURCE_ID, "Unexpected SQLite source")
        core.sqlite3_auto_extension.argtypes = [ctypes.c_void_p]
        entry = ctypes.cast(guard.sqlite3_bottogramsecurity_init, ctypes.c_void_p)
        require(core.sqlite3_auto_extension(entry) == 0, "Extension registration failed")
        core.sqlite3_open_v2.argtypes = [
            ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p), ctypes.c_int,
            ctypes.c_char_p,
        ]
        core.sqlite3_close_v2.argtypes = [ctypes.c_void_p]
        guard.bottogram_sqlite_security_probe.argtypes = [ctypes.c_void_p]
        guard.bottogram_sqlite_core_version.restype = ctypes.c_int
        database = ctypes.c_void_p()
        try:
            require(
                core.sqlite3_open_v2(b":memory:", ctypes.byref(database), 6, None) == 0,
                "Database open failed",
            )
            require(guard.bottogram_sqlite_core_version() == 3054001, "Core mismatch")
            require(guard.bottogram_sqlite_security_probe(database) == 7, "Security probe failed")
        finally:
            if database.value:
                require(core.sqlite3_close_v2(database) == 0, "Database close failed")
        print(json.dumps({"sqliteVersion": "3.54.1", "securityProbe": 7, "platform": sys.platform}))
    finally:
        if dll_directory is not None:
            dll_directory.close()


if __name__ == "__main__":
    main()
