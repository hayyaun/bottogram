run: icon
	flutter run

apk: icon
	flutter build apk --split-per-abi

apk-clean: clean pub icon
	flutter build apk --split-per-abi

linux: icon
	flutter build linux --release

icon:
	flutter pub run flutter_launcher_icons

clean:
	flutter clean

pub:
	flutter pub get
