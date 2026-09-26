import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'about.dart';
import 'core.dart';
import 'i18n.dart';
import 'store.dart';

const accent = Color(0xFF6366F1);
const releasesApi = 'https://api.github.com/repos/freeb5d/kite-android/releases/latest';
const repoUrl = 'https://github.com/freeb5d/kite-android';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  runApp(const KiteApp());
}

class KiteApp extends StatefulWidget {
  const KiteApp({super.key});

  @override
  State<KiteApp> createState() => _KiteAppState();
}

class _KiteAppState extends State<KiteApp> {
  String lang = Store.getString('lang') ?? 'en';
  bool dark = Store.getBool('dark', fallback: true);

  ThemeData _theme(Brightness b) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: accent, brightness: b),
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kite',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: HomePage(
        lang: lang,
        dark: dark,
        onLang: (l) {
          setState(() => lang = l);
          Store.setString('lang', l);
        },
        onTheme: (d) {
          setState(() => dark = d);
          Store.setBool('dark', d);
        },
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.lang, required this.dark, required this.onLang, required this.onTheme});

  final String lang;
  final bool dark;
  final ValueChanged<String> onLang;
  final ValueChanged<bool> onTheme;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _Group {
  _Group(this.id, this.name, this.url);
  final String id;
  final String name;
  final String url;
  final List<Server> servers = [];
  Map<String, dynamic>? usage;
  List<String> notes = [];
}

class _HomePageState extends State<HomePage> {
  List<Server> servers = Store.servers();
  String? selectedId = Store.getString('selected');
  String mode = Store.getString('mode') ?? 'vpn';
  Map<String, dynamic> status = {'state': 'stopped'};
  Map<String, dynamic>? testResult;
  bool testing = false;
  bool busy = false;
  String error = '';
  final expanded = <String>{};
  final syncing = <String>{};
  final pings = <String, int>{};
  bool pinging = false;
  Map<String, dynamic> info = {};
  Map<String, dynamic> traffic = {'uplink': 0, 'downlink': 0};
  Map<String, double> speed = {'up': 0, 'down': 0};
  DateTime? lastTrafficAt;
  Timer? trafficTimer;
  StreamSubscription? statusSub;
  bool trafficOpen = false;

  String t(String key, [List<Object?> args = const []]) => tr(widget.lang, key, args);

  bool get running => status['state'] == 'running';
  Server? get selected => servers.where((s) => s['id'] == selectedId).firstOrNull;

  @override
  void initState() {
    super.initState();
    statusSub = Core.status().listen((s) {
      setState(() {
        status = s;
        if (s['state'] == 'error') error = '${s['message'] ?? ''}';
        if (s['state'] != 'starting') busy = false;
      });
      if (s['state'] == 'running') {
        _startTraffic();
        _test();
      } else {
        _stopTraffic();
      }
    });
    Core.info().then((i) {
      if (mounted) setState(() => info = i);
      _checkUpdate(silent: true);
    }).catchError((_) {});
    _autoSync();
  }

  @override
  void dispose() {
    statusSub?.cancel();
    trafficTimer?.cancel();
    super.dispose();
  }

  // ---------- helpers ----------

  Future<void> _save() => Store.saveServers(servers);

  void _select(String? id) {
    setState(() => selectedId = id);
    if (id != null) Store.setString('selected', id);
  }

  void _flash(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  String _err(Object e) => e is PlatformException ? (e.message ?? e.code) : '$e';

  (List<Server>, List<_Group>) _grouped() {
    final standalone = <Server>[];
    final groups = <String, _Group>{};
    for (final s in servers) {
      final e = extraOf(s);
      final gid = e['subGroup'];
      if (gid == null || gid.isEmpty) {
        standalone.add(s);
        continue;
      }
      final g = groups.putIfAbsent(gid, () {
        final g = _Group(gid, e['subGroupName'] ?? 'Subscription', e['subURL'] ?? '');
        try {
          if (e['subUsage'] != null) g.usage = Map<String, dynamic>.from(jsonDecode(e['subUsage']!) as Map);
          if (e['subNotes'] != null) g.notes = List<String>.from(jsonDecode(e['subNotes']!) as List);
        } catch (_) {}
        return g;
      });
      g.servers.add(s);
    }
    return (standalone, groups.values.toList());
  }

  // ---------- adding servers ----------

  Future<void> _addDialog() async {
    final ctrl = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('addServer')),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(hintText: t('addLinkPlaceholder'), border: const OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.content_paste),
            label: Text(t('paste')),
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              if (data?.text != null) ctrl.text = data!.text!.trim();
            },
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(t('add'))),
        ],
      ),
    );
    if (value == null || value.isEmpty) return;
    await _addFromText(value);
  }

  Future<void> _addFromText(String value) async {
    setState(() => error = '');
    try {
      if (RegExp(r'^https?://', caseSensitive: false).hasMatch(value)) {
        final added = await _importSubscription(value, newId());
        if (added.isNotEmpty) _select('${added.last['id']}');
        return;
      }
      // Several links pasted at once: add each one.
      final lines = value.split(RegExp(r'\s+')).where((l) => l.contains('://')).toList();
      Server? last;
      for (final line in lines) {
        final s = await Core.parseLink(line);
        s['id'] = newId();
        servers.add(s);
        last = s;
      }
      await _save();
      setState(() {});
      if (last != null) _select('${last['id']}');
    } catch (e) {
      setState(() => error = _err(e));
    }
  }

  /// Fetches a subscription and replaces the group's servers only after a
  /// successful fetch, so a failed sync never loses servers.
  Future<List<Server>> _importSubscription(String url, String groupId, {String? keepName}) async {
    final res = await Core.fetchSubscription(url);
    final list = (res['servers'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final now = '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    for (final s in list) {
      s['id'] = newId();
      final e = extraOf(s);
      e['subGroup'] = groupId;
      e['subGroupName'] = keepName ?? '${res['name'] ?? url}';
      e['subURL'] = url;
      e['subUpdatedAt'] = now;
      if (res['usage'] != null) e['subUsage'] = jsonEncode(res['usage']);
      if ((res['notes'] as List?)?.isNotEmpty ?? false) e['subNotes'] = jsonEncode(res['notes']);
      if (((res['updateHours'] ?? 0) as num) > 0) e['subUpdateHours'] = '${res['updateHours']}';
      s['extra'] = e;
    }
    final oldSelected = selected;
    servers = [...servers.where((s) => extraOf(s)['subGroup'] != groupId), ...list];
    await _save();
    setState(() {});
    // Keep the same server selected across a sync (IDs change).
    if (oldSelected != null && extraOf(oldSelected)['subGroup'] == groupId) {
      final match = list.where((s) => s['address'] == oldSelected['address'] && s['port'] == oldSelected['port']).firstOrNull;
      _select(match == null ? null : '${match['id']}');
    }
    final skipped = (res['skipped'] ?? 0) as num;
    if (skipped > 0) _flash(t('skippedEntries', [list.length, skipped]));
    return list;
  }

  Future<void> _autoSync() async {
    final (_, groups) = _grouped();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final g in groups) {
      final e = extraOf(g.servers.first);
      final hours = int.tryParse(e['subUpdateHours'] ?? '') ?? 0;
      final at = int.tryParse(e['subUpdatedAt'] ?? '') ?? 0;
      if (hours > 0 && now - at > hours * 3600) {
        try {
          await _importSubscription(g.url, g.id, keepName: g.name);
        } catch (_) {}
      }
    }
  }

  Future<void> _syncGroup(_Group g) async {
    setState(() {
      syncing.add(g.id);
      error = '';
    });
    try {
      await _importSubscription(g.url, g.id, keepName: g.name);
    } catch (e) {
      setState(() => error = _err(e));
    } finally {
      setState(() => syncing.remove(g.id));
    }
  }

  Future<void> _deleteGroup(_Group g) async {
    servers.removeWhere((s) => extraOf(s)['subGroup'] == g.id);
    if (selected == null) selectedId = null;
    await _save();
    setState(() {});
  }

  Future<void> _editGroup(_Group g) async {
    final name = TextEditingController(text: g.name);
    final url = TextEditingController(text: g.url);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('editSubscription')),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: t('name'))),
            const SizedBox(height: 12),
            TextField(controller: url, decoration: InputDecoration(labelText: t('subscriptionUrl'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('save'))),
        ],
      ),
    );
    if (ok != true) return;
    final n = name.text.trim(), u = url.text.trim();
    if (n.isEmpty || !RegExp(r'^https?://').hasMatch(u)) return;
    for (final s in servers) {
      final e = extraOf(s);
      if (e['subGroup'] == g.id) {
        e['subGroupName'] = n;
        e['subURL'] = u;
        s['extra'] = e;
      }
    }
    await _save();
    setState(() {});
  }

  Future<void> _shareGroup(_Group g, bool urlOnly) async {
    try {
      var text = g.url;
      if (!urlOnly) {
        final links = <String>[];
        for (final s in g.servers) {
          links.add(await Core.shareLink(s));
        }
        text = links.join('\n');
      }
      await Clipboard.setData(ClipboardData(text: text));
      _flash(t('linkCopied'));
    } catch (e) {
      setState(() => error = _err(e));
    }
  }

  Future<void> _shareServer(Server s) async {
    try {
      await Clipboard.setData(ClipboardData(text: await Core.shareLink(s)));
      _flash(t('linkCopied'));
    } catch (e) {
      setState(() => error = _err(e));
    }
  }

  Future<void> _renameServer(Server s) async {
    final ctrl = TextEditingController(text: '${s['name']}');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('rename')),
        content: TextField(controller: ctrl, autofocus: true, onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(t('save'))),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    s['name'] = name.trim();
    await _save();
    setState(() {});
  }

  Future<void> _deleteServer(Server s) async {
    servers.removeWhere((x) => x['id'] == s['id']);
    if (selectedId == s['id']) selectedId = null;
    await _save();
    setState(() {});
  }

  Future<void> _pingAll() async {
    setState(() {
      pinging = true;
      pings.clear();
    });
    await Future.wait(servers.map((s) async {
      int ms;
      try {
        ms = await Core.ping(s);
      } catch (_) {
        ms = -1;
      }
      if (mounted) setState(() => pings['${s['id']}'] = ms);
    }));
    if (mounted) setState(() => pinging = false);
  }

  // ---------- connection ----------

  Future<void> _toggle() async {
    setState(() {
      error = '';
      testResult = null;
    });
    if (running || status['state'] == 'starting') {
      await Core.disconnect();
      return;
    }
    final s = selected;
    if (s == null) {
      setState(() => error = t('addServerFirst'));
      return;
    }
    setState(() => busy = true);
    try {
      await Core.connect(s, mode);
    } catch (e) {
      setState(() {
        busy = false;
        error = e is PlatformException && e.code == 'vpn_denied' ? t('vpnPermissionDenied') : _err(e);
      });
    }
  }

  Future<void> _test() async {
    setState(() {
      testing = true;
      testResult = null;
    });
    try {
      final r = await Core.test();
      if (mounted) setState(() => testResult = {'ok': true, ...r});
    } catch (e) {
      if (mounted) setState(() => testResult = {'ok': false, 'text': _err(e)});
    } finally {
      if (mounted) setState(() => testing = false);
    }
  }

  void _startTraffic() {
    trafficTimer?.cancel();
    lastTrafficAt = null;
    trafficTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final now = DateTime.now();
      Map<String, dynamic> tr;
      try {
        tr = await Core.traffic();
      } catch (_) {
        return;
      }
      if (!mounted || tr.isEmpty) return;
      setState(() {
        final prevAt = lastTrafficAt;
        if (prevAt != null) {
          final dt = now.difference(prevAt).inMilliseconds / 1000;
          if (dt > 0) {
            final up = (tr['uplink'] as num) - (traffic['uplink'] as num);
            final down = (tr['downlink'] as num) - (traffic['downlink'] as num);
            speed = {'up': up < 0 ? 0 : up / dt, 'down': down < 0 ? 0 : down / dt};
          }
        }
        traffic = tr;
        lastTrafficAt = now;
      });
    });
  }

  void _stopTraffic() {
    trafficTimer?.cancel();
    trafficTimer = null;
    if (!mounted) return;
    setState(() {
      traffic = {'uplink': 0, 'downlink': 0};
      speed = {'up': 0, 'down': 0};
    });
  }

  // ---------- updates, log, about ----------

  Future<void> _checkUpdate({bool silent = false}) async {
    try {
      final r = await http
          .get(Uri.parse(releasesApi), headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) throw Exception('GitHub returned ${r.statusCode}');
      final rel = jsonDecode(r.body) as Map<String, dynamic>;
      final latest = '${rel['tag_name']}'.replaceFirst('v', '');
      final current = '${info['version'] ?? '0.0.0'}';
      final assets = (rel['assets'] as List).map((a) => Map<String, dynamic>.from(a as Map));
      final apk = assets.where((a) => '${a['name']}'.endsWith('.apk')).firstOrNull;
      if (apk == null || !_isNewer(latest, current)) {
        if (!silent) _flash(t('onLatest'));
        return;
      }
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('updateAvailable', [latest])),
          content: Text(t('updateAvailableBanner', [latest, current])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('close'))),
            FilledButton(autofocus: true, onPressed: () => Navigator.pop(ctx, true), child: Text(t('updateNow'))),
          ],
        ),
      );
      if (go == true) {
        _flash(t('downloadingUpdate'));
        await Core.installApk('${apk['browser_download_url']}');
      }
    } catch (e) {
      if (!silent && mounted) setState(() => error = t('updateFailed', [_err(e)]));
    }
  }

  bool _isNewer(String latest, String current) {
    List<int> parts(String v) => [...v.split('.').map((p) => int.tryParse(p) ?? 0), 0, 0, 0];
    final a = parts(latest), b = parts(current);
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  Future<void> _showLog() async {
    final log = await Core.log();
    if (!mounted) return;
    final problems = log
        .split('\n')
        .where((l) => RegExp(r'\[(Warning|Error)\]|failed|rejected|timeout|EOF', caseSensitive: false).hasMatch(l))
        .join('\n');
    var errorsOnly = problems.isNotEmpty;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final shown = errorsOnly ? problems : log;
          return AlertDialog(
            title: Text(t('showLog')),
            content: SizedBox(
              width: 720,
              height: 420,
              child: SingleChildScrollView(
                reverse: true,
                child: SelectableText(shown.isEmpty ? t('logEmpty') : shown,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => setLocal(() => errorsOnly = !errorsOnly),
                child: Text(errorsOnly ? t('showAllLog') : t('errorsOnly')),
              ),
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: shown));
                  _flash(t('logCopied'));
                },
                child: Text(t('copyLog')),
              ),
              FilledButton(autofocus: true, onPressed: () => Navigator.pop(ctx), child: Text(t('close'))),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAbout() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AboutPage(info: info, t: t, onCheckUpdate: () => _checkUpdate()),
    ));
  }

  Future<void> _pickLanguage() async {
    final l = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(t('language')),
        children: [
          for (final (code, label) in languages)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, code),
              child: Text(label, style: TextStyle(fontWeight: code == widget.lang ? FontWeight.bold : null)),
            ),
        ],
      ),
    );
    if (l != null) widget.onLang(l);
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 840 || info['isTv'] == true;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Kite'),
          actions: [
            IconButton(tooltip: t('addServer'), icon: const Icon(Icons.add), onPressed: _addDialog),
            IconButton(
              tooltip: pinging ? t('pinging') : t('ping'),
              icon: pinging
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.network_ping),
              onPressed: pinging ? null : _pingAll,
            ),
            IconButton(tooltip: t('showLog'), icon: const Icon(Icons.terminal), onPressed: _showLog),
            IconButton(tooltip: t('language'), icon: const Icon(Icons.translate), onPressed: _pickLanguage),
            IconButton(
              tooltip: widget.dark ? t('switchToLight') : t('switchToDark'),
              icon: Icon(widget.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
              onPressed: () => widget.onTheme(!widget.dark),
            ),
            IconButton(tooltip: t('about'), icon: const Icon(Icons.info_outline), onPressed: _showAbout),
          ],
        ),
        body: wide
            ? Row(children: [
                SizedBox(width: 420, child: ListView(padding: const EdgeInsets.all(8), children: _serverTiles())),
                const VerticalDivider(width: 1),
                Expanded(
                  child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: _connectPanel(autofocus: true)),
                ),
              ])
            : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                Padding(padding: const EdgeInsets.all(16), child: _connectPanel()),
                const Divider(height: 1),
                ..._serverTiles(),
              ]),
      );
    });
  }

  List<Widget> _serverTiles() {
    final (standalone, groups) = _grouped();
    if (servers.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            Text(t('noServersYet'), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: _addDialog, icon: const Icon(Icons.add), label: Text(t('addServer'))),
          ]),
        ),
      ];
    }
    return [
      for (final s in standalone) _serverTile(s),
      for (final g in groups) _groupTile(g),
    ];
  }

  Widget _serverTile(Server s, {bool indent = false}) {
    final isSel = s['id'] == selectedId;
    final ms = pings['${s['id']}'];
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.fromLTRB(indent ? 24 : 8, 3, 8, 3),
      color: isSel ? scheme.primaryContainer : null,
      child: ListTile(
        onTap: () => _select('${s['id']}'),
        leading: isSel && running ? const Icon(Icons.circle, color: Colors.green, size: 12) : null,
        title: Text('${s['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${s['protocol']} · ${s['address']}:${s['port']}', maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (ms != null)
            Text(ms < 0 ? t('timeout') : '$ms ms',
                style: TextStyle(fontSize: 12, color: ms < 0 ? scheme.error : (ms < 300 ? Colors.green : Colors.orange))),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'share') _shareServer(s);
              if (v == 'rename') _renameServer(s);
              if (v == 'delete') _deleteServer(s);
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'share', child: Text(t('shareLink'))),
              PopupMenuItem(value: 'rename', child: Text(t('rename'))),
              PopupMenuItem(value: 'delete', child: Text(t('remove'))),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _groupTile(_Group g) {
    final open = expanded.contains(g.id);
    final u = g.usage;
    final num used = u == null ? 0 : ((u['uploadBytes'] ?? 0) as num) + ((u['downloadBytes'] ?? 0) as num);
    final num total = u == null ? 0 : (u['totalBytes'] ?? 0) as num;
    final num expire = u == null ? 0 : (u['expireUnix'] ?? 0) as num;
    String gb(num b) => (b / 1e9).toStringAsFixed(1);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        margin: const EdgeInsets.fromLTRB(8, 6, 8, 3),
        child: Column(children: [
          ListTile(
            onTap: () => setState(() => open ? expanded.remove(g.id) : expanded.add(g.id)),
            leading: Icon(open ? Icons.expand_more : Icons.chevron_right),
            title: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(t('servers_n', [g.servers.length]) + (g.notes.isNotEmpty && u == null ? ' · ${g.notes.join(' · ')}' : ''),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: t('syncSubscription'),
                onPressed: syncing.contains(g.id) ? null : () => _syncGroup(g),
                icon: syncing.contains(g.id)
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync),
              ),
              PopupMenuButton<String>(
                tooltip: t('share'),
                icon: const Icon(Icons.share_outlined),
                onSelected: (v) => _shareGroup(g, v == 'url'),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'url', child: Text(t('copySubscriptionUrl'))),
                  PopupMenuItem(value: 'links', child: Text(t('copyAllServerLinks'))),
                ],
              ),
              IconButton(tooltip: t('edit'), icon: const Icon(Icons.edit_outlined), onPressed: () => _editGroup(g)),
              IconButton(tooltip: t('remove'), icon: const Icon(Icons.delete_outline), onPressed: () => _deleteGroup(g)),
            ]),
          ),
          if (u != null && (used > 0 || total > 0 || expire > 0))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(children: [
                if (total > 0) ...[
                  Expanded(child: LinearProgressIndicator(value: (used / total).clamp(0, 1).toDouble())),
                  const SizedBox(width: 8),
                  Text('${gb(used)}/${gb(total)} GB', style: const TextStyle(fontSize: 12)),
                ] else
                  Expanded(child: Text(t('gbUsedUnlimited', [gb(used)]), style: const TextStyle(fontSize: 12))),
                if (expire > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${t('expires')} ${DateTime.fromMillisecondsSinceEpoch(expire.toInt() * 1000).toLocal().toString().split(' ').first}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ]),
            ),
        ]),
      ),
      if (open)
        for (final s in g.servers) _serverTile(s, indent: true),
    ]);
  }

  Widget _connectPanel({bool autofocus = false}) {
    final s = selected;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final starting = busy || status['state'] == 'starting';
    final stateText = starting ? (running ? t('disconnecting') : t('connecting')) : (running ? t('connected') : t('disconnected'));

    return Column(children: [
      Text(s == null ? t('noServerSelected') : '${s['name']}', style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
      if (s != null) Text('${s['protocol']} · ${s['address']}:${s['port']}', style: theme.textTheme.bodySmall),
      const SizedBox(height: 16),
      SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'vpn', icon: const Icon(Icons.vpn_lock), label: Text(t('vpnMode'))),
          ButtonSegment(value: 'proxy', icon: const Icon(Icons.public), label: Text(t('proxyOnly'))),
        ],
        selected: {mode},
        onSelectionChanged: running || starting
            ? null
            : (v) {
                setState(() => mode = v.first);
                Store.setString('mode', mode);
              },
      ),
      const SizedBox(height: 6),
      Text(mode == 'vpn' ? t('vpnModeHint') : t('proxyModeHint'), style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
      const SizedBox(height: 24),
      SizedBox(
        width: 150,
        height: 150,
        child: FilledButton(
          autofocus: autofocus,
          style: FilledButton.styleFrom(
            shape: const CircleBorder(),
            backgroundColor: running ? scheme.primary : scheme.surfaceContainerHighest,
            foregroundColor: running ? scheme.onPrimary : scheme.onSurfaceVariant,
          ),
          onPressed: (s == null && !running) ? null : _toggle,
          child: starting ? const CircularProgressIndicator() : const Icon(Icons.power_settings_new, size: 64),
        ),
      ),
      const SizedBox(height: 12),
      Text(stateText, style: theme.textTheme.titleSmall),
      if (running)
        Text(status['mode'] == 'vpn' ? t('tunAdapterAllTraffic') : 'HTTP 127.0.0.1:10809 · SOCKS5 127.0.0.1:10808',
            style: theme.textTheme.bodySmall),
      if (running) ...[
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: testing ? null : _test,
          icon: const Icon(Icons.speed),
          label: Text(testing ? t('testing') : t('testConnection')),
        ),
      ],
      if (error.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(8)),
          child: Text(error, style: TextStyle(color: scheme.onErrorContainer, fontSize: 12)),
        ),
      if (testResult != null) _testResultBox(scheme),
      if (running) ...[
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => setState(() => trafficOpen = !trafficOpen),
          icon: Icon(trafficOpen ? Icons.expand_less : Icons.expand_more),
          label: Text(trafficOpen ? t('showLess') : t('showMore')),
        ),
        if (trafficOpen)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                _trafficRow(t('liveTraffic'), '${_bytes(speed['up']!)}/s', '${_bytes(speed['down']!)}/s'),
                const Divider(),
                _trafficRow(t('totalTraffic'), _bytes(traffic['uplink'] as num), _bytes(traffic['downlink'] as num)),
              ]),
            ),
          ),
      ],
    ]);
  }

  Widget _testResultBox(ColorScheme scheme) {
    final r = testResult!;
    final ok = r['ok'] == true;
    final country = '${r['country'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ok ? Colors.green.withValues(alpha: 0.15) : scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        ok ? '${_flag(country)} ${r['ip']} $country · ${r['delayMs']}ms' : '✗ ${r['text']}',
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _trafficRow(String label, String up, String down) => Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
        const Icon(Icons.arrow_upward, size: 14, color: Colors.green),
        Text(up, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 12),
        const Icon(Icons.arrow_downward, size: 14, color: Colors.red),
        Text(down, style: const TextStyle(fontSize: 12)),
      ]);

  String _bytes(num n) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var v = n.toDouble();
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v < 10 && i > 0 ? v.toStringAsFixed(1) : v.round()}${units[i]}';
  }

  /// Regional-indicator flag emoji for a two-letter country code.
  String _flag(String cc) {
    if (cc.length != 2) return '';
    return String.fromCharCodes(cc.toUpperCase().codeUnits.map((c) => 0x1F1E6 + c - 65));
  }
}
