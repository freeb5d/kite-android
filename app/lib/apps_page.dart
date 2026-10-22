import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'core.dart';

/// Per-app VPN: route all apps, only the chosen ones, or all but the chosen
/// ones through Kite. Applied by the VPN service on the next connect.
class AppsPage extends StatefulWidget {
  const AppsPage({super.key, required this.t});

  final String Function(String key, [List<Object?> args]) t;

  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> {
  String mode = 'all'; // all | only | except
  final picked = <String>{};
  List<Map<String, dynamic>>? apps;
  String query = '';

  String t(String k) => widget.t(k);

  @override
  void initState() {
    super.initState();
    Core.getSplit().then((s) => setState(() {
          mode = s.mode;
          picked.addAll(s.apps);
        }));
    Core.apps().then((a) => setState(() => apps = a));
  }

  void _save() => Core.setSplit(mode, picked.toList());

  @override
  Widget build(BuildContext context) {
    final list = (apps ?? [])
        .where((a) => query.isEmpty || '${a['name']} ${a['pkg']}'.toLowerCase().contains(query.toLowerCase()))
        .toList()
      // chosen apps first
      ..sort((a, b) => (picked.contains(b['pkg']) ? 1 : 0) - (picked.contains(a['pkg']) ? 1 : 0));
    return Scaffold(
      appBar: AppBar(title: Text(t('perAppVpn'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'all', label: Text(t('allApps'))),
              ButtonSegment(value: 'only', label: Text(t('onlySelected'))),
              ButtonSegment(value: 'except', label: Text(t('exceptSelected'))),
            ],
            selected: {mode},
            onSelectionChanged: (v) {
              setState(() => mode = v.first);
              _save();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(t('perAppHint'), style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
        ),
        if (mode != 'all') ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: t('searchApps'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          Expanded(
            child: apps == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final a = list[i];
                      final pkg = '${a['pkg']}';
                      final icon = a['icon'];
                      return CheckboxListTile(
                        value: picked.contains(pkg),
                        secondary: icon is Uint8List
                            ? Image.memory(icon, width: 36, height: 36, gaplessPlayback: true)
                            : const Icon(Icons.android),
                        title: Text('${a['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(pkg, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                        onChanged: (v) {
                          setState(() => v == true ? picked.add(pkg) : picked.remove(pkg));
                          _save();
                        },
                      );
                    },
                  ),
          ),
        ],
      ]),
    );
  }
}
