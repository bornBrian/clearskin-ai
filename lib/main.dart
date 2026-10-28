import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/providers.dart';
import 'data/db/app_database.dart';
import 'data/repositories/repositories.dart';
import 'services/notification_service.dart';
import 'services/purchases_service.dart';
import 'services/telemetry.dart';

Telemetry? _telemetry;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // debugPrint still writes to logcat in release builds, which any app with
  // log access or a USB cable can read. Nothing sensitive is logged, but
  // release builds say nothing at all.
  if (kReleaseMode) debugPrint = (String? message, {int? wrapWidth}) {};

  // Central error sink. Wire Crashlytics or Sentry here before launch.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _report(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _report(error, stack);
    return true;
  };

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final db = await AppDatabase.open();
  final kv = KeyValueStore(db);

  final telemetry = Telemetry(kv);
  await telemetry.init();
  _telemetry = telemetry;
  telemetry.track(Ev.appOpen);

  final notifications = NotificationService();
  unawaited(notifications.init());

  if (Env.hasBackend) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabasePublishableKey,
    );
  }

  final purchases = PurchasesService();
  // Configure anonymously now; the backend user id is linked after the
  // first frame (see ClearSkinApp._linkIdentity) so startup never waits on
  // the network.
  final existingUid = Env.hasBackend
      ? Supabase.instance.client.auth.currentUser?.id
      : null;
  await purchases.configure(appUserId: existingUid);
  if (kDebugMode && await kv.get(KvKeys.devPremium) == '1') {
    purchases.setDevPremium(true);
  }

  final startLocked = await kv.get(KvKeys.appLock) == '1';

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        purchasesServiceProvider.overrideWithValue(purchases),
        notificationServiceProvider.overrideWithValue(notifications),
        telemetryProvider.overrideWithValue(telemetry),
      ],
      child: ClearSkinApp(startLocked: startLocked),
    ),
  );
}

void _report(Object error, StackTrace? stack) {
  if (kDebugMode) {
    debugPrint('Uncaught: $error\n$stack');
  }
  _telemetry?.captureError(error, stack);
}
