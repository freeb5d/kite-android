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

/// The map window around [code] in map units (x, y, width), and whether the
/// country lands on the right half — then the info card goes left so it
/// never covers it (e.g. Australia or Japan, at the map's edge).
({double x, double y, double w, bool cardOnLeft}) _view(_MapData data, String code) {
  final b = data.boxes[code];
  if (b == null) return (x: 0, y: 0, w: data.w, cardOnLeft: false);
  final w = min(data.w, max(max(b.width * 3.2, b.height * 2 * _aspect), 240)).toDouble();
  final h = w / _aspect;
  final cx = b.center.dx + w * 0.16;
  final x = (cx - w / 2).clamp(0, data.w - w).toDouble();
  final y = (b.center.dy - h / 2).clamp(0, max(0, data.h - h)).toDouble();
  return (x: x, y: y, w: w, cardOnLeft: (b.center.dx - x) / w > 0.5);
}

/// A map zoomed onto [country] (ISO 3166-1 alpha-2), which is highlighted.
/// [overlay] is drawn on top, e.g. an info card.
class WorldMap extends StatelessWidget {
  const WorldMap({super.key, required this.country, this.overlay});

  final String country;

  /// Builds the overlay; `cardOnLeft` says which side keeps the country clear.
  final Widget Function(bool cardOnLeft)? overlay;

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
              if (snap.hasData && overlay != null) overlay!(_view(snap.data!, country.toUpperCase()).cardOnLeft),
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
    final v = _view(data, code);
    final vw = v.w, vx = v.x, vy = v.y;
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
