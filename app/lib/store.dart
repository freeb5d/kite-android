import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// A saved server: the same JSON shape as the desktop app's profile.Server,
/// so it round-trips through the Go core unchanged.
typedef Server = Map<String, dynamic>;

Map<String, String> extraOf(Server s) =>
    Map<String, String>.from((s['extra'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? {});

String newId() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// Persists servers and settings in SharedPreferences.
class Store {
  static late SharedPreferences _p;

  static Future<void> init() async => _p = await SharedPreferences.getInstance();

  static List<Server> servers() {
    final raw = _p.getString('servers');
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> saveServers(List<Server> servers) => _p.setString('servers', jsonEncode(servers));

  static String? getString(String key) => _p.getString(key);
  static Future<void> setString(String key, String value) => _p.setString(key, value);
  static bool getBool(String key, {bool fallback = false}) => _p.getBool(key) ?? fallback;
  static Future<void> setBool(String key, bool value) => _p.setBool(key, value);
}
