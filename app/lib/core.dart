import 'dart:convert';

import 'package:flutter/services.dart';

/// Bridge to the native side: the Go core (link parsing, subscriptions,
/// xray-core) and the Android VpnService, both behind one MethodChannel.
class Core {
  static const _ch = MethodChannel('kite/core');
  static const _events = EventChannel('kite/status');

  static Future<Map<String, dynamic>> parseLink(String link) async =>
      jsonDecode(await _ch.invokeMethod<String>('parseLink', link) ?? '{}');

  static Future<Map<String, dynamic>> fetchSubscription(String url) async =>
      jsonDecode(await _ch.invokeMethod<String>('fetchSubscription', url) ?? '{}');

  static Future<String> shareLink(Map<String, dynamic> server) async =>
      await _ch.invokeMethod<String>('shareLink', jsonEncode(server)) ?? '';

  /// Asks for VPN permission if needed, then connects. [mode] is "vpn" or "proxy".
  static Future<void> connect(Map<String, dynamic> server, String mode) =>
      _ch.invokeMethod('connect', {'server': jsonEncode(server), 'mode': mode, 'name': server['name'] ?? ''});

  static Future<void> disconnect() => _ch.invokeMethod('disconnect');

  static Future<Map<String, dynamic>> traffic() async =>
      jsonDecode(await _ch.invokeMethod<String>('traffic') ?? '{}');

  static Future<Map<String, dynamic>> test() async =>
      jsonDecode(await _ch.invokeMethod<String>('test') ?? '{}');

  static Future<int> ping(Map<String, dynamic> server) async =>
      await _ch.invokeMethod<int>('ping', jsonEncode(server)) ?? -1;

  static Future<String> log() async => await _ch.invokeMethod<String>('log') ?? '';

  static Future<Map<String, dynamic>> info() async =>
      Map<String, dynamic>.from(await _ch.invokeMethod<Map>('info') ?? {});

  static Future<void> openAlwaysOnSettings() => _ch.invokeMethod('openVpnSettings');

  static Future<void> installApk(String url) => _ch.invokeMethod('installApk', url);

  static Future<void> openUrl(String url) => _ch.invokeMethod('openUrl', url);

  /// Connection status updates from the VPN service:
  /// {"state": "stopped"|"starting"|"running"|"error", "server": ..., "mode": ..., "message": ...}
  static Stream<Map<String, dynamic>> status() =>
      _events.receiveBroadcastStream().map((e) => Map<String, dynamic>.from(e as Map));
}
