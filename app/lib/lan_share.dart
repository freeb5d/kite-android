import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

/// Path prefix of receive URLs, so a scanned code can be recognised as
/// "a TV waiting for configs" rather than a subscription URL.
const receivePath = '/kite-receive/';

bool isReceiveUrl(String s) => RegExp(r'^http://[^/]+' + receivePath, caseSensitive: false).hasMatch(s.trim());

/// Sends [text] (share links, one per line, or a subscription URL) to a TV
/// whose receive URL was scanned from its screen.
Future<void> sendToReceiver(String url, String text) async {
  final res = await http
      .post(Uri.parse(url.trim()), headers: {'Content-Type': 'text/plain; charset=utf-8'}, body: utf8.encode(text))
      .timeout(const Duration(seconds: 8));
  if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
}

/// The device's address on the local network (Wi-Fi / Ethernet), skipping
/// loopback, link-local and Kite's own VPN tunnel.
Future<String?> lanAddress() async {
  final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
  String? fallback;
  for (final i in ifaces) {
    for (final a in i.addresses) {
      final ip = a.address;
      if (a.isLoopback || ip.startsWith('169.254.') || ip.startsWith('10.19.0.')) continue;
      final n = i.name.toLowerCase();
      if (n.startsWith('tun') || n.startsWith('rmnet') || n.startsWith('ccmni')) continue;
      if (n.startsWith('wlan') || n.startsWith('eth')) return ip;
      fallback ??= ip;
    }
  }
  return fallback;
}

/// Shows a QR code and listens on the local network until closed. Each text
/// posted to the receive URL is handed to [onReceive], which returns how
/// many items it added.
class ReceivePage extends StatefulWidget {
  const ReceivePage({super.key, required this.t, required this.onReceive});

  final String Function(String key, [List<Object?> args]) t;
  final Future<int> Function(String text) onReceive;

  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> {
  HttpServer? server;
  String? url;
  String message = '';
  bool failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final ip = await lanAddress();
      if (ip == null) {
        setState(() {
          failed = true;
          message = widget.t('noLan');
        });
        return;
      }
      final rnd = Random.secure();
      final token = List.generate(12, (_) => rnd.nextInt(36).toRadixString(36)).join();
      final s = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      server = s;
      setState(() => url = 'http://$ip:${s.port}$receivePath$token');
      s.listen((req) => _handle(req, token));
    } catch (e) {
      setState(() {
        failed = true;
        message = '$e';
      });
    }
  }

  Future<void> _handle(HttpRequest req, String token) async {
    final res = req.response;
    try {
      if (req.uri.path != '$receivePath$token') {
        res.statusCode = HttpStatus.notFound;
      } else if (req.method == 'GET') {
        // Scanned with a normal camera app: a tiny page to paste links into.
        res.headers.contentType = ContentType.html;
        res.write(_page);
      } else if (req.method == 'POST') {
        var body = await utf8.decodeStream(req);
        if ((req.headers.contentType?.mimeType ?? '') == 'application/x-www-form-urlencoded') {
          body = Uri.splitQueryString(body)['links'] ?? '';
        }
        final n = await widget.onReceive(body.trim());
        if (mounted) setState(() => message = widget.t('received_n', [n]));
        res.headers.contentType = ContentType.html;
        res.write(_done(n));
      } else {
        res.statusCode = HttpStatus.methodNotAllowed;
      }
    } catch (e) {
      res.statusCode = HttpStatus.badRequest;
      res.write('$e');
    }
    await res.close();
  }

  static const _style =
      '<meta name="viewport" content="width=device-width,initial-scale=1"><style>body{font-family:sans-serif;margin:24px;background:#031A5A;color:#fff}textarea{width:100%;height:40vh;border-radius:12px;padding:10px;box-sizing:border-box}button{margin-top:12px;width:100%;padding:14px;border:0;border-radius:24px;font-size:16px;background:#c7d2ff}</style>';
  static const _page =
      '<!doctype html><html><head><meta charset="utf-8"><title>Kite</title>$_style</head><body><h2>Kite</h2><form method="post"><textarea name="links" placeholder="vless://… / https://…"></textarea><button type="submit">Send to TV</button></form></body></html>';
  String _done(int n) =>
      '<!doctype html><html><head><meta charset="utf-8"><title>Kite</title>$_style</head><body><h2>Kite</h2><p>✓ ${htmlEscape.convert(widget.t('received_n', [n]))}</p></body></html>';

  @override
  void dispose() {
    server?.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t('receiveFromPhone'))),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (url != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: QrImageView(data: url!, size: 260, backgroundColor: Colors.white),
              ),
              const SizedBox(height: 16),
              SelectableText(url!, style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Text(t('receiveHint'), textAlign: TextAlign.center),
              ),
            ] else if (!failed)
              const CircularProgressIndicator(),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(message,
                  style: TextStyle(
                      color: failed ? theme.colorScheme.error : Colors.green, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 24),
            FilledButton(autofocus: true, onPressed: () => Navigator.pop(context), child: Text(t('close'))),
          ]),
        ),
      ),
    );
  }
}
