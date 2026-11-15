import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/network_repository.dart';
import 'data/preferences_repository.dart';
import 'ui/dashboard_strings.dart';
import 'ui/dashboard_view.dart';
import 'ui/dashboard_view_model.dart';
import 'ui/net_pulse_theme.dart';
import 'ui/settings_view_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsViewModel(LocalPreferencesRepository());
  await settings.load();
  runApp(
    NetPulseApp(repository: CloudflareNetworkRepository(), settings: settings),
  );
}

class NetPulseApp extends StatefulWidget {
  const NetPulseApp({
    super.key,
    required this.repository,
    required this.settings,
  });

  final NetworkRepository repository;
  final SettingsViewModel settings;

  @override
  State<NetPulseApp> createState() => _NetPulseAppState();
}

class _NetPulseAppState extends State<NetPulseApp> {
  late final _dashboard = DashboardViewModel(widget.repository);

  @override
  void dispose() {
    _dashboard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.settings,
    builder: (context, _) => MaterialApp(
      title: 'NetPulse',
      debugShowCheckedModeBanner: false,
      theme: netPulseTheme(Brightness.light),
      darkTheme: netPulseTheme(Brightness.dark),
      themeMode: widget.settings.theme,
      locale: widget.settings.locale,
      supportedLocales: DashboardStrings.languages.keys.map(Locale.new),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: DashboardView(model: _dashboard, settings: widget.settings),
    ),
  );
}
