import 'package:flutter/material.dart';

import 'core.dart';

const _repoUrl = 'https://github.com/freeb5d/kite-android';
const _desktopUrl = 'https://github.com/freeb5d/kite';

/// Full-screen About page (works with a TV remote as well as touch).
class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.info, required this.t, required this.onCheckUpdate});

  final Map<String, dynamic> info;
  final String Function(String key, [List<Object?> args]) t;
  final VoidCallback onCheckUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(title.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.primary, letterSpacing: 1.2)),
            ),
            Card(margin: EdgeInsets.zero, child: Column(children: children)),
          ]),
        );

    Widget row(IconData icon, String label, String value) => ListTile(
          leading: Icon(icon, color: scheme.onSurfaceVariant),
          title: Text(label),
          trailing: Text(value, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        );

    Widget link(IconData icon, String label, String url) => ListTile(
          leading: Icon(icon, color: scheme.onSurfaceVariant),
          title: Text(label),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () => Core.openUrl(url),
        );

    final version = '${info['version'] ?? '—'}';
    return Scaffold(
      appBar: AppBar(title: Text(t('about'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            const SizedBox(height: 16),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset('assets/logo.png', width: 96, height: 96),
              ),
            ),
            const SizedBox(height: 16),
            Center(child: Text('Kite', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600))),
            const SizedBox(height: 8),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(20)),
                child: Text('v$version', style: theme.textTheme.labelMedium?.copyWith(color: scheme.onPrimaryContainer)),
              ),
            ),
            const SizedBox(height: 16),
            Text(t('aboutDescription'), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 20),
            Center(
              child: FilledButton.icon(
                autofocus: true,
                onPressed: onCheckUpdate,
                icon: const Icon(Icons.system_update_alt),
                label: Text(t('checkForUpdates')),
              ),
            ),
            section(t('about'), [
              row(Icons.info_outline, t('appVersion'), version),
              row(Icons.memory, t('engineLabel'), 'xray-core ${info['core'] ?? '—'}'),
              row(Icons.phone_android, t('device'), 'Android API ${info['sdk'] ?? '—'} · ${info['abi'] ?? '—'}'),
            ]),
            section(t('killSwitch'), [
              ListTile(
                leading: Icon(Icons.shield_outlined, color: scheme.onSurfaceVariant),
                title: Text(t('alwaysOnVpn')),
                subtitle: Text(t('alwaysOnVpnHint')),
                trailing: const Icon(Icons.chevron_right),
                onTap: Core.openAlwaysOnSettings,
              ),
            ]),
            section(t('links'), [
              link(Icons.code, t('repository'), _repoUrl),
              link(Icons.new_releases_outlined, t('releases'), '$_repoUrl/releases'),
              link(Icons.bug_report_outlined, t('reportIssue'), '$_repoUrl/issues'),
              link(Icons.desktop_windows_outlined, t('desktopVersion'), _desktopUrl),
            ]),
            const SizedBox(height: 24),
            Text(t('licenseLine'), textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text('© ${DateTime.now().year} freeb5d', textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}
