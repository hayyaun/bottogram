# bottogram

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## ADB WSL Issue Fix

1. Phone: Revoke - Connect USB
1. Windows: taskkill /F /IM adb.exe && adb devices && adb tcpip 5555
1. WSL: adb connect

if the above didn't work... please forcefully disconnect 5037

1. netstat -ano | findstr :5037
1. taskkill /PID <PID> /F
