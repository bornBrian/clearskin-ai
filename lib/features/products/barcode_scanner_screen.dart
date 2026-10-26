import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/product.dart';

class BarcodeScannerScreen extends ConsumerStatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  ConsumerState<BarcodeScannerScreen> createState() =>
      _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends ConsumerState<BarcodeScannerScreen> {
  final _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _looking = false;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_looking) return;
    final code = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (code == null) return;
    setState(() => _looking = true);
    HapticFeedback.mediumImpact();
    await _controller.stop();

    ProductDraft? draft;
    try {
      draft = await ref.read(productLookupProvider).byBarcode(code);
    } catch (_) {
      draft = null;
    }
    if (!mounted) return;

    if (draft != null && draft.ingredientsRaw.isNotEmpty) {
      context.pushReplacement('/product/review', extra: draft);
      return;
    }

    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          draft == null ? 'Product not found' : 'No ingredient list on file',
        ),
        content: Text(
          draft == null
              ? 'This product isn\'t in the open database yet. Photograph its ingredient list or type it in.'
              : 'We found "${draft.name}" but not its ingredients. You can add them manually.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'retry'),
            child: const Text('Scan again'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'manual'),
            child: const Text('Enter manually'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (next == 'manual') {
      context.pushReplacement(
        '/product/review',
        extra: ProductDraft(
          name: draft?.name ?? '',
          brand: draft?.brand ?? '',
          barcode: code,
          imageUrl: draft?.imageUrl,
          category: draft?.category ?? ProductCategory.other,
        ),
      );
    } else {
      setState(() => _looking = false);
      await _controller.start();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final window = Rect.fromCenter(
      center: Offset(
        MediaQuery.sizeOf(context).width / 2,
        MediaQuery.sizeOf(context).height * 0.42,
      ),
      width: 280,
      height: 160,
    );
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan barcode'),
        actions: [
          IconButton(
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flashlight_on_rounded),
            tooltip: 'Torch',
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            scanWindow: window,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Text(
                  'Camera unavailable. Check camera permission in Settings.',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: CustomPaint(
              size: Size.infinite,
              painter: _WindowPainter(window),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: window.bottom + Space.lg,
            child: _looking
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : const Text(
                    'Point at the barcode on the product',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
          ),
        ],
      ),
    );
  }
}

class _WindowPainter extends CustomPainter {
  _WindowPainter(this.window);
  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(window, const Radius.circular(16));
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = Colors.black54);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_WindowPainter old) => old.window != window;
}
