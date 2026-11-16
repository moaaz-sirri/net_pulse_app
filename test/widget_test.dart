import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_pulse_app/data/network_repository.dart';
import 'package:net_pulse_app/data/preferences_repository.dart';
import 'package:net_pulse_app/main.dart';
import 'package:net_pulse_app/ui/settings_view_model.dart';

class _Network implements NetworkRepository {
  @override
  Future<ConnectionStatus> checkConnection() async =>
      (transport: NetworkTransport.wifi, online: false);

  final requested = <NetworkTransport>[];

  @override
  Future<SpeedResult?> measureOn(NetworkTransport transport) async {
    requested.add(transport);
    return transport == NetworkTransport.wifi
        ? (download: 100.0, upload: 20.0, latencyMs: 15.0)
        : (download: 40.0, upload: 8.0, latencyMs: 32.0);
  }

  @override
  Future<SpeedResult> measureSpeed() async =>
      (download: 87.5, upload: 12.0, latencyMs: 25.0);
}

class _Preferences implements PreferencesRepository {
  String? provider;

  @override
  Future<String?> readProvider() async => provider;

  @override
  Future<void> saveProvider(String value) async => provider = value;

  @override
  Future<String?> readTheme() async => null;

  @override
  Future<String?> readLanguage() async => null;

  @override
  Future<void> saveTheme(String theme) async {}

  @override
  Future<void> saveLanguage(String? language) async {}
}

void main() {
  testWidgets('selects a test provider and restores the saved choice', (
    tester,
  ) async {
    final preferences = _Preferences();
    final settings = SettingsViewModel(preferences);
    await settings.load();
    expect(settings.provider, TestProvider.cloudflare);

    await tester.pumpWidget(
      NetPulseApp(repository: _Network(), settings: settings),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test provider'));
    await tester.pumpAndSettle();
    expect(find.text('Cloudflare'), findsOneWidget);
    expect(find.text('Clouvider'), findsOneWidget);
    await tester.tap(find.text('CESNET'));
    await tester.pumpAndSettle();

    final restored = SettingsViewModel(preferences);
    await restored.load();
    expect(settings.provider, TestProvider.cesnet);
    expect(restored.provider, TestProvider.cesnet);
    restored.dispose();
  });

  testWidgets('full report measures only the selected networks', (
    tester,
  ) async {
    final repository = _Network();
    final settings = SettingsViewModel(_Preferences());
    await tester.pumpWidget(
      NetPulseApp(repository: repository, settings: settings),
    );
    await tester.pumpAndSettle();
    final choose = find.text('Choose networks');
    await tester.tap(choose);
    await tester.pumpAndSettle();
    expect(repository.requested, isEmpty);
    await tester.tap(find.text('Mobile data'));
    await tester.pumpAndSettle();
    expect(repository.requested, [NetworkTransport.mobile]);
    expect(find.text('40.0 Mbps'), findsOneWidget);
    await tester.ensureVisible(choose);
    await tester.tap(choose);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wi-Fi and mobile data'));
    await tester.pumpAndSettle();
    expect(repository.requested, [
      NetworkTransport.mobile,
      NetworkTransport.wifi,
      NetworkTransport.mobile,
    ]);
    expect(find.text('100.0 Mbps'), findsOneWidget);
    expect(find.text('40.0 Mbps'), findsOneWidget);
  });
  testWidgets(
    'runs independent diagnostics and applies Arabic RTL and dark mode',
    (tester) async {
      final settings = SettingsViewModel(_Preferences());
      await tester.pumpWidget(
        NetPulseApp(repository: _Network(), settings: settings),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Check connection'));
      await tester.tap(find.text('Check connection'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Test server unreachable'), findsOneWidget);

      await tester.ensureVisible(find.text('Run speed test'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Run speed test'));
      await tester.pumpAndSettle();
      expect(find.textContaining('87.5 Mbps'), findsOneWidget);
      expect(find.textContaining('12.0 Mbps'), findsOneWidget);

      settings.setLocale(const Locale('ar'));
      settings.setTheme(ThemeMode.dark);
      await tester.pumpAndSettle();

      final context = tester.element(find.text('تشخيص الإنترنت'));
      expect(Directionality.of(context), TextDirection.rtl);
      expect(Theme.of(context).brightness, Brightness.dark);
    },
  );
}
