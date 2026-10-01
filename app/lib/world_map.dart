import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Country outlines from Natural Earth (public domain), Mercator-projected and
/// simplified into integer rings: { w, h, c: { "DE": [[x,y,x,y,...], ...] } }.
class _MapData {
  _MapData(this.w, this.h, this.paths, this.boxes);
  final double w, h;
  final Map<String, Path> paths;
  final Map<String, Rect> boxes; // largest ring per country (mainland)

  static Future<_MapData>? _loading;
  static Future<_MapData> load() => _loading ??= () async {
        final j = jsonDecode(await rootBundle.loadString('assets/worldmap.json')) as Map<String, dynamic>;
        final paths = <String, Path>{};
        final boxes = <String, Rect>{};
        (j['c'] as Map<String, dynamic>).forEach((code, rings) {
          final p = Path();
          Rect? best;
          for (final r in (rings as List)) {
            final pts = (r as List).cast<num>();
            p.moveTo(pts[0].toDouble(), pts[1].toDouble());
            var x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
            for (var i = 0; i < pts.length; i += 2) {
              final x = pts[i].toDouble(), y = pts[i + 1].toDouble();
              if (i > 0) p.lineTo(x, y);
              x0 = min(x0, x);
              x1 = max(x1, x);
              y0 = min(y0, y);
              y1 = max(y1, y);
            }
            p.close();
            final box = Rect.fromLTRB(x0, y0, x1, y1);
            if (best == null || box.width * box.height > best.width * best.height) best = box;
          }
          paths[code] = p;
          if (best != null) boxes[code] = best;
        });
        return _MapData((j['w'] as num).toDouble(), (j['h'] as num).toDouble(), paths, boxes);
      }();
}

const _aspect = 2.2;

/// A map zoomed onto [country] (ISO 3166-1 alpha-2), which is highlighted.
/// [overlay] is drawn on top, e.g. an info card.
class WorldMap extends StatelessWidget {
  const WorldMap({super.key, required this.country, this.overlay});

  final String country;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AspectRatio(
      aspectRatio: _aspect,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          color: dark ? const Color(0xFF0D1420) : const Color(0xFFE8EEF7),
          child: FutureBuilder<_MapData>(
            future: _MapData.load(),
            builder: (context, snap) => Stack(fit: StackFit.expand, children: [
              if (snap.hasData)
                CustomPaint(
                  painter: _MapPainter(
                    snap.data!,
                    country.toUpperCase(),
                    land: dark ? const Color(0xFF263042) : const Color(0xFFC5CFDD),
                    border: dark ? const Color(0xFF0D1420) : const Color(0xFFE8EEF7),
                    highlight: scheme.primary,
                    highlightBorder: dark ? scheme.primaryContainer : scheme.onPrimaryContainer,
                  ),
                ),
              ?overlay,
            ]),
          ),
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.data, this.code,
      {required this.land, required this.border, required this.highlight, required this.highlightBorder});

  final _MapData data;
  final String code;
  final Color land, border, highlight, highlightBorder;

  @override
  void paint(Canvas canvas, Size size) {
    // View window in map units: ~3x the country, country left of centre
    // (the info card sits on the right), clamped to the map.
    final b = data.boxes[code];
    double vw = data.w, vx = 0, vy = 0;
    if (b != null) {
      vw = min(data.w, max(max(b.width * 3.2, b.height * 3.2 * _aspect), 240));
      final vh = vw / _aspect;
      final cx = b.center.dx + vw * 0.16;
      vx = (cx - vw / 2).clamp(0, data.w - vw).toDouble();
      vy = (b.center.dy - vh / 2).clamp(0, max(0, data.h - vh)).toDouble();
    }
    final scale = size.width / vw;
    canvas.save();
    canvas.scale(scale);
    canvas.translate(-vx, -vy);
    final stroke = 1.2 / scale;
    final fill = Paint()..color = land;
    final line = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    data.paths.forEach((c, p) {
      if (c == code) return;
      canvas.drawPath(p, fill);
      canvas.drawPath(p, line);
    });
    final hp = data.paths[code];
    if (hp != null) {
      canvas.drawPath(hp, Paint()..color = highlight);
      canvas.drawPath(
          hp,
          Paint()
            ..color = highlightBorder
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke * 2.2);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.code != code || old.highlight != highlight || old.land != land;
}
