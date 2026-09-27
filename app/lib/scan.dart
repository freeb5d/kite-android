import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen camera QR scanner. Pops with the first code that looks like
/// a share link or subscription URL.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key, required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool done = false;

  static final _useful = RegExp(r'^(vmess|vless|trojan|ss|hysteria2|hy2|ssh|https?)://', caseSensitive: false);

  void _onDetect(BarcodeCapture capture) {
    if (done) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue?.trim();
      if (v != null && _useful.hasMatch(v)) {
        done = true;
        Navigator.of(context).pop(v);
        return;
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(icon: const Icon(Icons.flash_on), onPressed: controller.toggleTorch),
          IconButton(icon: const Icon(Icons.cameraswitch), onPressed: controller.switchCamera),
        ],
      ),
      body: Stack(children: [
        MobileScanner(controller: controller, onDetect: _onDetect),
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 48,
          child: Text(
            widget.hint,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 15, shadows: [Shadow(blurRadius: 6)]),
          ),
        ),
      ]),
    );
  }
}
