import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/repositories/repositories.dart';

/// Reads ingredient lists from product labels, fully on-device.
class OcrService {
  TextRecognizer? _recognizer;

  Future<String> readText(String imagePath) async {
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    final result = await _recognizer!.processImage(
      InputImage.fromFilePath(imagePath),
    );
    return result.text;
  }

  /// Keeps only the part of label text that looks like an INCI list.
  static String extractIngredients(String text) {
    final lower = text.toLowerCase();
    final start = RegExp(r'(ingredients|ingrédients|inci)\s*[:：]')
        .firstMatch(lower);
    var body = start == null ? text : text.substring(start.start);
    // Lists end before usage/warnings/marketing blocks.
    final end = RegExp(
      r'\n\s*(directions|how to use|warning|caution|made in|distributed by|for external use)',
      caseSensitive: false,
    ).firstMatch(body);
    if (end != null) body = body.substring(0, end.start);
    return body.trim();
  }

  Future<void> dispose() async => _recognizer?.close();
}

/// Optional biometric/PIN lock for a private photo journal.
class AppLockService {
  final _auth = LocalAuthentication();

  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock ClearSkin to see your skin journal',
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException catch (e) {
      debugPrint('Auth failed: ${e.code}');
      return false;
    } on PlatformException catch (e) {
      debugPrint('Auth failed: ${e.message}');
      return false;
    }
  }
}

/// Asks for a store review only after a genuinely positive moment, at most
/// once every 90 days, using the native in-app review sheet.
class ReviewService {
  ReviewService(this._kv);
  final KeyValueStore _kv;
  final _review = InAppReview.instance;

  Future<void> maybePrompt() async {
    final last = await _kv.get(KvKeys.reviewPrompted);
    if (last != null) {
      final at = DateTime.tryParse(last);
      if (at != null && clock.now().difference(at).inDays < 90) return;
    }
    try {
      if (await _review.isAvailable()) {
        await _review.requestReview();
        await _kv.set(KvKeys.reviewPrompted, clock.now().toIso8601String());
      }
    } catch (_) {}
  }
}

/// Exports everything stored about the user as a JSON file (GDPR-style data
/// portability) through the system share sheet.
class ExportService {
  ExportService({
    required this.profile,
    required this.scans,
    required this.checkIns,
    required this.products,
    required this.logs,
  });

  final ProfileRepository profile;
  final ScanRepository scans;
  final CheckInRepository checkIns;
  final ProductRepository products;
  final RoutineLogRepository logs;

  Future<void> exportAll() async {
    final data = {
      'exported_at': clock.now().toIso8601String(),
      'profile': (await profile.load())?.toJson(),
      'scans': [
        for (final s in await scans.all())
          {
            'id': s.id,
            'created_at': s.createdAt.toIso8601String(),
            'analysis': s.analysis.toJson(),
            'radiance': s.radiance?.toJson(),
          },
      ],
      'check_ins': [for (final c in await checkIns.all()) c.toRow()],
      'routine_logs': [for (final l in await logs.all()) l.toRow()],
      'products': [for (final pr in await products.all()) pr.toRow()],
    };
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'clearskin-export.json'));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'My ClearSkin data',
      ),
    );
  }
}
