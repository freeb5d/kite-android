import 'package:flutter/material.dart';

import 'store.dart';

const _fingerprints = ['', 'chrome', 'firefox', 'safari', 'ios', 'android', 'edge', '360', 'qq', 'random', 'randomized'];
const _ssMethods = [
  'aes-128-gcm', 'aes-256-gcm', 'chacha20-poly1305', 'chacha20-ietf-poly1305', 'xchacha20-poly1305',
  'xchacha20-ietf-poly1305', '2022-blake3-aes-128-gcm', '2022-blake3-aes-256-gcm', '2022-blake3-chacha20-poly1305', 'none',
];
const _vmessCiphers = ['auto', 'aes-128-gcm', 'chacha20-poly1305', 'none', 'zero'];
const _flows = ['', 'xtls-rprx-vision', 'xtls-rprx-vision-udp443'];
const _networks = ['tcp', 'kcp', 'ws', 'httpupgrade', 'xhttp', 'h2', 'grpc'];
const _xhttpModes = ['auto', 'packet-up', 'stream-up', 'stream-one'];
const _kcpHeaders = ['none', 'srtp', 'utp', 'wechat-video', 'dtls', 'wireguard', 'dns'];

/// Full-screen editor for one server (existing or new). Pops with the
/// edited server, or null when cancelled.
class ServerEditorPage extends StatefulWidget {
  const ServerEditorPage({super.key, required this.initial, required this.t});

  final Server initial;
  final String Function(String key, [List<Object?> args]) t;

  @override
  State<ServerEditorPage> createState() => _ServerEditorPageState();
}

class _ServerEditorPageState extends State<ServerEditorPage> {
  late final Server s;
  late final Map<String, String> e;
  String error = '';

  String t(String key) => widget.t(key);

  @override
  void initState() {
    super.initState();
    s = Map<String, dynamic>.from(widget.initial);
    // vmess:// links store transport/security as "network"/"tls", the
    // other link types as "type"/"security" -- edit one normalized pair.
    e = extraOf(s);
    e['type'] = e['type'] ?? e['network'] ?? 'tcp';
    e['security'] = e['security'] ?? e['tls'] ?? 'none';
    if (e['security']!.isEmpty) e['security'] = 'none';
    e.remove('network');
    e.remove('tls');
  }

  String get protocol => '${s['protocol']}';

  void _save() {
    final address = '${s['address'] ?? ''}'.trim();
    final port = int.tryParse('${s['port']}') ?? 0;
    if (address.isEmpty) {
      setState(() => error = '${t('address')}?');
      return;
    }
    if (port < 1 || port > 65535) {
      setState(() => error = '${t('port')}: 1–65535');
      return;
    }
    final extra = Map<String, String>.from(e)..removeWhere((_, v) => v.isEmpty);
    if (extra['security'] == 'none') extra.remove('security');
    if (protocol == 'hysteria2' || protocol == 'ssh') {
      extra.remove('type');
      extra.remove('security');
    }
    final name = '${s['name'] ?? ''}'.trim();
    Navigator.pop(context, {
      ...s,
      'name': name.isEmpty ? address : name,
      'address': address,
      'port': port,
      'extra': extra,
    });
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.primary, letterSpacing: 1.2)),
      );

  Widget _text(String label, String? value, ValueChanged<String> onChanged,
          {String hint = '', TextInputType? keyboard}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          initialValue: value ?? '',
          keyboardType: keyboard,
          decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), isDense: true),
          onChanged: onChanged,
        ),
      );

  Widget _select(String label, String value, List<String> options, ValueChanged<String> onChanged) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: options.contains(value) ? value : options.first,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
          items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o.isEmpty ? t('none') : o))],
          onChanged: (v) => setState(() => onChanged(v ?? '')),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final type = e['type'] ?? 'tcp';
    final security = e['security'] ?? 'none';
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.initial['id'] == null ? t('addManually') : t('editServer')} · ${protocol.toUpperCase()}'),
        actions: [
          IconButton(tooltip: t('save'), icon: const Icon(Icons.check), onPressed: _save),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
            _section(t('basic')),
            _text(t('name'), s['name'] as String?, (v) => s['name'] = v),
            _text(t('address'), s['address'] as String?, (v) => s['address'] = v, hint: 'example.com'),
            _text(t('port'), '${s['port'] ?? ''}', (v) => s['port'] = v, hint: '443', keyboard: TextInputType.number),
            if (protocol == 'vmess') ...[
              _text(t('uuid'), s['uuid'] as String?, (v) => s['uuid'] = v),
              _select(t('encryption'), e['scy'] ?? 'auto', _vmessCiphers, (v) => e['scy'] = v),
            ],
            if (protocol == 'vless') ...[
              _text(t('uuid'), s['uuid'] as String?, (v) => s['uuid'] = v),
              _select(t('flow'), e['flow'] ?? '', _flows, (v) => e['flow'] = v),
              _text(t('encryption'), e['encryption'], (v) => e['encryption'] = v, hint: 'none'),
            ],
            if (protocol == 'trojan') _text(t('password'), s['password'] as String?, (v) => s['password'] = v),
            if (protocol == 'ssh') ...[
              _text(t('username'), e['user'], (v) => e['user'] = v, hint: 'root'),
              _text(t('password'), s['password'] as String?, (v) => s['password'] = v),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  initialValue: e['pk'] ?? '',
                  minLines: 3,
                  maxLines: 6,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: InputDecoration(
                      labelText: t('privateKey'),
                      hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
                      border: const OutlineInputBorder(),
                      isDense: true),
                  onChanged: (v) => setState(() => e['pk'] = v),
                ),
              ),
              if ((e['pk'] ?? '').isNotEmpty) _text(t('keyPassphrase'), e['pp'], (v) => e['pp'] = v),
              _text(t('hostKey'), e['hk'], (v) => e['hk'] = v, hint: 'SHA256:…'),
            ],
            if (protocol == 'hysteria2') ...[
              _text(t('password'), s['password'] as String?, (v) => s['password'] = v),
              _text(t('portHopping'), e['mport'], (v) => e['mport'] = v, hint: '20000-30000'),
              _section(t('security')),
              _text(t('sni'), e['sni'], (v) => e['sni'] = v),
              _text(t('pinSHA256'), e['pinSHA256'], (v) => e['pinSHA256'] = v),
              _text(t('ech'), e['ech'], (v) => e['ech'] = v),
              _select(t('obfs'), e['obfs'] ?? '', const ['', 'salamander'], (v) => e['obfs'] = v),
              if (e['obfs'] == 'salamander')
                _text(t('obfsPassword'), e['obfs-password'], (v) => e['obfs-password'] = v),
            ],
            if (protocol == 'shadowsocks') ...[
              _select(t('method'), '${s['method'] ?? 'aes-256-gcm'}', _ssMethods, (v) => s['method'] = v),
              _text(t('password'), s['password'] as String?, (v) => s['password'] = v),
            ],
            if (!const ['shadowsocks', 'hysteria2', 'ssh'].contains(protocol)) ...[
              _section(t('transport')),
              _select(t('network'), type, _networks, (v) {
                e['type'] = v;
                e['headerType'] = '';
                e['mode'] = '';
              }),
              if (type == 'tcp')
                _select(t('headerType'), e['headerType'] == 'http' ? 'http' : 'none', ['none', 'http'],
                    (v) => e['headerType'] = v == 'none' ? '' : v),
              if (const ['ws', 'httpupgrade', 'xhttp', 'h2'].contains(type) ||
                  (type == 'tcp' && e['headerType'] == 'http')) ...[
                _text(t('hostHeader'), e['host'], (v) => e['host'] = v),
                _text(t('path'), e['path'], (v) => e['path'] = v, hint: '/'),
              ],
              if (type == 'xhttp') ...[
                _select(t('mode'), e['mode'] ?? 'auto', _xhttpModes, (v) => e['mode'] = v == 'auto' ? '' : v),
                _text(t('xhttpExtra'), e['extra'], (v) => e['extra'] = v, hint: '{"xPaddingBytes":"100-1000"}'),
              ],
              if (type == 'kcp') ...[
                _select(t('headerType'), e['headerType'] ?? 'none', _kcpHeaders,
                    (v) => e['headerType'] = v == 'none' ? '' : v),
                _text(t('seed'), e['seed'], (v) => e['seed'] = v),
              ],
              if (type == 'grpc') ...[
                _text(t('serviceName'), e['serviceName'], (v) => e['serviceName'] = v),
                _select(t('mode'), e['mode'] ?? 'gun', const ['gun', 'multi'], (v) => e['mode'] = v == 'gun' ? '' : v),
                _text(t('authority'), e['authority'], (v) => e['authority'] = v),
              ],
              _section(t('security')),
              _select(t('security'), security, ['none', 'tls', 'reality'], (v) => e['security'] = v),
              if (security != 'none') ...[
                _text(t('sni'), e['sni'], (v) => e['sni'] = v),
                _select(t('fingerprint'), e['fp'] ?? '', _fingerprints, (v) => e['fp'] = v),
              ],
              if (security == 'tls') _text(t('alpn'), e['alpn'], (v) => e['alpn'] = v, hint: 'h2,http/1.1'),
              if (security == 'tls')
                _text(t('ech'), e['ech'], (v) => e['ech'] = v, hint: 'cloudflare-ech.com+https://1.1.1.1/dns-query'),
              if (security == 'reality') ...[
                _text(t('publicKey'), e['pbk'], (v) => e['pbk'] = v),
                _text(t('shortId'), e['sid'], (v) => e['sid'] = v),
                _text(t('spiderX'), e['spx'], (v) => e['spx'] = v, hint: '/'),
              ],
            ],
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: Text(t('save'))),
          ]),
        ),
      ),
    );
  }
}
