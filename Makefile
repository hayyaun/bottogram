run: icon gen
	flutter run

apk: icon gen
	flutter build apk --split-per-abi

apk-clean: clean pub icon gen
	flutter build apk --split-per-abi

linux: icon gen
	flutter build linux --release

gen:
	dart run build_runner build --delete-conflicting-outputs

icon:
	flutter pub run flutter_launcher_icons

clean:
	flutter clean

pub:
	flutter pub get
