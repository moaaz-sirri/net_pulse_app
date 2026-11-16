# NetPulse

NetPulse is a Flutter app for Android and iOS that checks internet access, measures connection speed, and compares Wi-Fi with mobile data.

## Network diagnostics

| Test | What it does |
| --- | --- |
| Connection | Identifies the active connection type and checks whether it can reach the test server. |
| Speed test | Measures download and upload speeds on the connection the device is currently using. |
| Full internet test | Tests Wi-Fi, mobile data, or both. Reports download speed, upload speed, and latency separately for each selected network. |

The full test uses native Android and iOS networking APIs to send measurements over the selected interface. If you select both networks, it tests Wi-Fi first, then mobile data. Measurements use Cloudflare's speed test endpoints and transfer about 11 MB per tested network.

NetPulse supports light, dark, and system appearance settings. The interface is available in English, Arabic, Simplified Chinese, French, Hindi, Portuguese, and Spanish. Arabic uses the bundled Cairo typeface and a right-to-left layout. Appearance and language preferences are stored on the device.

## Run locally

Use a Flutter SDK that includes Dart 3.13.3 or a compatible newer version. Set up the Android SDK or Xcode for your target platform.

```sh
flutter pub get
flutter devices
flutter run
```

Use a physical phone with Wi-Fi and an active mobile data plan to try the full test on both networks.

Run the analyzer and widget tests with:

```sh
flutter analyze
flutter test
```

To build an Android release APK:

```sh
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`.

## Project structure

NetPulse uses MVVM. Views display diagnostic results and settings, and view models track application state and handle user actions.

- `lib/ui/` contains views, view models, themes, and translations.
- `lib/data/` contains repositories for network diagnostics and preferences.
- `android/` and `ios/` contain the native implementations that route tests over Wi-Fi or mobile data.
- `test/` contains Flutter widget tests for the diagnostic flows.

The bundled Cairo font is distributed under the [SIL Open Font License](assets/fonts/cairo/OFL.txt).
