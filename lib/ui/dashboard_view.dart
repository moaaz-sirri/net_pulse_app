import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/network_repository.dart';
import 'dashboard_strings.dart';
import 'dashboard_view_model.dart';
import 'settings_view_model.dart';

class DashboardView extends StatelessWidget {
  const DashboardView({super.key, required this.model, required this.settings});

  final DashboardViewModel model;
  final SettingsViewModel settings;

  @override
  Widget build(BuildContext context) {
    final strings = DashboardStrings(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('NetPulse'),
        actions: [
          IconButton(
            tooltip: strings[Copy.settings],
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => _SettingsView(model: settings)),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListenableBuilder(
                listenable: model,
                builder: (context, _) {
                  final status = model.connection;
                  final speed = model.speed;
                  final format = NumberFormat.decimalPatternDigits(
                    locale: Localizations.localeOf(context).toLanguageTag(),
                    decimalDigits: 1,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        strings[Copy.title],
                        style: theme.textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        strings[Copy.intro],
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      _FullTestPanel(model: model, format: format),
                      const SizedBox(height: 16),
                      _Panel(
                        title: strings[Copy.connection],
                        info: strings.help(HelpCopy.connection),
                        icon: Icons.wifi,
                        content: status == null
                            ? null
                            : Text(
                                '${strings[_transportLabel(status.transport)]}\n'
                                '${strings[status.online ? Copy.online : Copy.unreachable]}',
                                semanticsLabel:
                                    '${strings[_transportLabel(status.transport)]}. '
                                    '${strings[status.online ? Copy.online : Copy.unreachable]}',
                              ),
                        feedback: _Feedback(model, Diagnostic.connection),
                        action: OutlinedButton(
                          onPressed: model.running == null
                              ? () => model.run(Diagnostic.connection)
                              : null,
                          child: Text(strings[Copy.check]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _Panel(
                        title: strings[Copy.speed],
                        info: strings.help(HelpCopy.speed),
                        icon: Icons.speed_outlined,
                        content: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (speed != null) ...[
                              Text(
                                '${strings[Copy.download]}  ${format.format(speed.download)} Mbps',
                              ),
                              Text(
                                '${strings[Copy.upload]}  ${format.format(speed.upload)} Mbps',
                              ),
                              const SizedBox(height: 8),
                            ],
                            Text(
                              strings[Copy.speedHint],
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        feedback: _Feedback(model, Diagnostic.speed),
                        action: OutlinedButton(
                          onPressed: model.running == null
                              ? () => model.run(Diagnostic.speed)
                              : null,
                          child: Text(strings[Copy.measure]),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Copy _transportLabel(NetworkTransport transport) => switch (transport) {
    NetworkTransport.wifi => Copy.wifi,
    NetworkTransport.mobile => Copy.mobile,
    NetworkTransport.other => Copy.other,
    NetworkTransport.none => Copy.offline,
  };
}

class _FullTestPanel extends StatelessWidget {
  const _FullTestPanel({required this.model, required this.format});

  final DashboardViewModel model;
  final NumberFormat format;

  @override
  Widget build(BuildContext context) {
    final strings = DashboardStrings(context);
    final target = model.reportTarget;
    final running = model.running == Diagnostic.full;
    final theme = Theme.of(context);
    return _Panel(
      title: strings.report(ReportCopy.title),
      info: strings.help(HelpCopy.full),
      icon: Icons.network_check,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(strings.report(ReportCopy.usage)),
          for (final network in DashboardViewModel.reportNetworks)
            if (model.attempted(network)) ...[
              const Divider(height: 24),
              Text(
                strings[network == NetworkTransport.wifi
                    ? Copy.wifi
                    : Copy.mobile],
                style: theme.textTheme.titleMedium,
              ),
              if (model.resultFor(network) case final result?) ...[
                Text(
                  '${format.format(result.download)} Mbps',
                  style: theme.textTheme.headlineSmall,
                ),
                Text(strings[Copy.download]),
                Text(
                  '${strings[Copy.upload]}  ${format.format(result.upload)} Mbps',
                ),
                Text(
                  '${strings.report(ReportCopy.latency)}  ${format.format(result.latencyMs)} ms',
                ),
              ] else
                Text(
                  model.failedFor(network)
                      ? strings[Copy.retry]
                      : strings.report(ReportCopy.unavailable),
                ),
            ],
        ],
      ),
      feedback: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (running && target != null) ...[
            const SizedBox(height: 12),
            Text(
              '${strings[target == NetworkTransport.wifi ? Copy.wifi : Copy.mobile]} · ${strings[Copy.working]}',
            ),
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
        ],
      ),
      action: FilledButton(
        onPressed: model.running == null
            ? () => _chooseNetworks(context)
            : null,
        child: Text(strings.report(ReportCopy.start)),
      ),
    );
  }

  Future<void> _chooseNetworks(BuildContext context) async {
    final strings = DashboardStrings(context);
    final selection = await showDialog<List<NetworkTransport>>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(strings.report(ReportCopy.choose)),
        children: [
          for (final (title, networks) in [
            (strings[Copy.wifi], const [NetworkTransport.wifi]),
            (strings[Copy.mobile], const [NetworkTransport.mobile]),
            (
              strings.report(ReportCopy.both),
              DashboardViewModel.reportNetworks,
            ),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, networks),
              child: Text(title),
            ),
        ],
      ),
    );
    if (context.mounted && selection != null) {
      await model.startReport(selection);
    }
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.info,
    required this.icon,
    required this.content,
    required this.feedback,
    required this.action,
  });

  final String title;
  final String info;
  final IconData icon;
  final Widget? content;
  final Widget feedback;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
              IconButton(
                tooltip:
                    '${DashboardStrings(context).help(HelpCopy.info)} · $title',
                icon: const Icon(Icons.info_outline),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: Text(title),
                    content: Text(info),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: Text(
                          MaterialLocalizations.of(dialogContext)
                              .closeButtonLabel,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (content case final body?) ...[
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: body),
          ],
          feedback,
          const SizedBox(height: 16),
          action,
        ],
      ),
    );
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback(this.model, this.diagnostic);

  final DashboardViewModel model;
  final Diagnostic diagnostic;

  @override
  Widget build(BuildContext context) {
    final strings = DashboardStrings(context);
    final running = model.running == diagnostic;
    if (!running && model.failed != diagnostic) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings[running ? Copy.working : Copy.retry]),
            if (running) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView({required this.model});

  final SettingsViewModel model;

  @override
  Widget build(BuildContext context) {
    final strings = DashboardStrings(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings[Copy.settings])),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            for (final (label, icon, page) in [
              (
                strings[Copy.theme],
                Icons.brightness_6_outlined,
                _AppearanceView(model),
              ),
              (strings[Copy.language], Icons.language, _LanguageView(model)),
              (
                strings.help(HelpCopy.aboutTitle),
                Icons.info_outline,
                const _AboutView(),
              ),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () =>
                    Navigator.of(context)
                        .push<void>(MaterialPageRoute(builder: (_) => page)),
              ),
          ],
        ),
      ),
    );
  }
}

class _AppearanceView extends StatelessWidget {
  const _AppearanceView(this.model);

  final SettingsViewModel model;

  @override
  Widget build(BuildContext context) {
    final strings = DashboardStrings(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings[Copy.theme])),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: model,
          builder: (context, _) => RadioGroup<ThemeMode>(
            groupValue: model.theme,
            onChanged: (value) {
              if (value != null) model.setTheme(value);
            },
            child: ListView(
              children: [
                for (final (mode, label) in [
                  (ThemeMode.system, Copy.system),
                  (ThemeMode.light, Copy.light),
                  (ThemeMode.dark, Copy.dark),
                ])
                  RadioListTile(value: mode, title: Text(strings[label])),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageView extends StatelessWidget {
  const _LanguageView(this.model);

  final SettingsViewModel model;

  @override
  Widget build(BuildContext context) {
    final strings = DashboardStrings(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings[Copy.language])),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: model,
          builder: (context, _) => RadioGroup<String>(
            groupValue: model.locale?.languageCode ?? '',
            onChanged: (value) => model.setLocale(
              value == null || value.isEmpty ? null : Locale(value),
            ),
            child: ListView(
              children: [
                RadioListTile(value: '', title: Text(strings[Copy.system])),
                for (final entry in DashboardStrings.languages.entries)
                  RadioListTile(value: entry.key, title: Text(entry.value)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AboutView extends StatelessWidget {
  const _AboutView();

  @override
  Widget build(BuildContext context) {
    final strings = DashboardStrings(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.help(HelpCopy.aboutTitle))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('NetPulse', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 12),
            Text(strings.help(HelpCopy.about)),
          ],
        ),
      ),
    );
  }
}
