import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/account_status.dart';
import '../../data/models/scan.dart';
import '../../data/repositories/repositories.dart';
import '../../services/backend_api.dart';
import '../../domain/scan/face_zones.dart';
import '../../domain/scan/live_guidance.dart';
import '../../services/photo_service.dart';
import '../../services/telemetry.dart';
import '../paywall/out_of_scans_sheet.dart';
import 'live_face_guide.dart';

enum _Phase { gate, consent, issues, camera, checking, analyzing }

class ScanCaptureScreen extends ConsumerStatefulWidget {
  const ScanCaptureScreen({super.key});

  @override
  ConsumerState<ScanCaptureScreen> createState() => _ScanCaptureScreenState();
}

class _ScanCaptureScreenState extends ConsumerState<ScanCaptureScreen>
    with WidgetsBindingObserver {
  _Phase _phase = _Phase.gate;
  CameraController? _camera;
  String? _cameraError;
  ProcessedPhoto? _photo;
  List<Offset> _facePoints = const [];
  FaceGeometry? _geometry;
  LiveFaceGuide? _guide;
  final Set<SkinIssue> _issues = {};

  /// Front first (hairline to chin), then each side for the cheeks,
  /// jawline and temples a straight-on photo foreshortens.
  ScanPose _pose = ScanPose.front;
  ProcessedPhoto? _front;
  final List<ProcessedPhoto> _sides = [];

  /// When the live camera last (re)started. The shutter waits for the live
  /// checks, but never forever: on a phone where live detection struggles,
  /// it opens after [_shutterFallback] and the photo is checked after.
  DateTime _cameraSince = clock.now();
  static const _shutterFallback = Duration(seconds: 8);

  bool get _shutterLocked {
    final g = _guide;
    if (g == null || !g.active || g.hint.ready) return false;
    return clock.now().difference(_cameraSince) < _shutterFallback;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _guide?.dispose();
    _camera?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _guide?.dispose();
      _guide = null;
      cam.dispose();
      _camera = null;
    } else if (state == AppLifecycleState.resumed && _phase == _Phase.camera) {
      _initCamera();
    }
  }

  Future<void> _start() async {
    if (!await _ensureScanAllowed()) {
      if (mounted) context.pop();
      return;
    }
    final consent = await ref.read(kvProvider).get(KvKeys.photoConsent);
    if (!mounted) return;
    ref.read(telemetryProvider).track(Ev.scanStarted);
    setState(() => _phase = consent == '1' ? _Phase.issues : _Phase.consent);
  }

  /// Free plan: 2 scans per rolling 30 days (the server's numbers when
  /// online, this phone's history when not). Out of scans → Premium, or a
  /// rewarded video for one more. The server enforces all of this anyway.
  Future<bool> _ensureScanAllowed() async {
    if (ref.read(premiumProvider)) return true;
    final status = await ref.read(accountStatusProvider.notifier).refresh();
    final bool allowed;
    if (status != null) {
      allowed = status.canScan;
    } else {
      // Only usable scans count, matching the server (a blurry photo
      // shouldn't cost a scan).
      final since = clock.now().subtract(
        const Duration(days: FreeLimits.scanWindowDays),
      );
      final recent = (await ref.read(scansProvider.future))
          .where((s) => s.analysis.usable && s.createdAt.isAfter(since));
      allowed = recent.length < FreeLimits.scansPerWindow;
    }
    if (allowed) return true;
    return _outOfScans(status);
  }

  Future<bool> _outOfScans(AccountStatus? status) async {
    if (!mounted) return false;
    ref.read(telemetryProvider).track(Ev.outOfScans);
    final choice = await showOutOfScansSheet(context, status);
    if (!mounted) return false;
    switch (choice) {
      case OutOfScansChoice.premium:
        final bought = await context.push<bool>('/paywall?source=scan');
        return bought == true || ref.read(premiumProvider);
      case OutOfScansChoice.video:
        return earnScanWithVideo(ref, context);
      case null:
        return false;
    }
  }

  Future<void> _issuesDone() async {
    setState(() => _phase = _Phase.camera);
    await _initCamera();
  }

  Future<void> _acceptConsent() async {
    await ref.read(kvProvider).set(KvKeys.photoConsent, '1');
    setState(() => _phase = _Phase.issues);
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        front,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        // Single-plane formats ML Kit can read directly for live guidance.
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await ctrl.initialize();
      await ctrl.setFlashMode(FlashMode.off);
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      _guide?.dispose();
      final guide = LiveFaceGuide(
        controller: ctrl,
        description: front,
        onReady: () {
          HapticFeedback.mediumImpact();
          ref.read(telemetryProvider).track(Ev.scanAutoCaptured);
          unawaited(_capture());
        },
      );
      setState(() {
        _camera = ctrl;
        _guide = guide;
        _cameraError = null;
        _cameraSince = clock.now();
      });
      await guide.start();
    } on CameraException catch (e) {
      setState(
        () => _cameraError = e.code == 'CameraAccessDenied'
            ? 'Camera access is off. Enable it in Settings, or pick a photo from your gallery.'
            : 'Camera unavailable. You can pick a photo from your gallery instead.',
      );
    } catch (_) {
      setState(
        () => _cameraError = 'Camera unavailable. You can pick a photo from your gallery instead.',
      );
    }
  }

  Future<void> _capture() async {
    final cam = _camera;
    if (_phase != _Phase.camera ||
        cam == null ||
        !cam.value.isInitialized ||
        cam.value.isTakingPicture) {
      return;
    }
    HapticFeedback.mediumImpact();
    // Frames must stop streaming before a still can be taken.
    await _guide?.stop();
    try {
      final file = await cam.takePicture();
      await _check(file.path);
    } on CameraException {
      if (mounted) showSnack(context, 'Couldn\'t take the photo. Try again.');
      await _guide?.start();
    }
  }

  /// Back to the live camera after a retake.
  void _backToCamera() {
    setState(() {
      _phase = _Phase.camera;
      _cameraSince = clock.now();
    });
    unawaited(_guide?.start());
  }

  Future<void> _pickFromGallery() async {
    await _guide?.stop();
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2400,
      requestFullMetadata: false,
    );
    if (picked != null) {
      await _check(picked.path);
    } else {
      await _guide?.start();
    }
  }

  Future<void> _check(String path) async {
    setState(() => _phase = _Phase.checking);
    try {
      final check = await ref
          .read(photoServiceProvider)
          .process(path, pose: _pose);
      if (!mounted) return;
      if (check.issues.isNotEmpty) {
        ref.read(telemetryProvider).track(Ev.scanQualityIssue, {
          'issues': check.issues.map((i) => i.name).join(','),
        });
      }
      if (check.issues.isEmpty) {
        await _accept(check);
        return;
      }
      final useAnyway = await _showIssues(check);
      if (!mounted) return;
      if (useAnyway) {
        await _accept(check);
      } else {
        ref.read(photoServiceProvider).discard(check.photo);
        _backToCamera();
      }
    } on FormatException {
      if (!mounted) return;
      showSnack(context, 'That image format isn\'t supported.');
      _backToCamera();
    }
  }

  /// A photo passed its checks: move on to the next pose, or analyse.
  Future<void> _accept(CaptureCheck check) async {
    switch (_pose) {
      case ScanPose.front:
        _front = check.photo;
        _facePoints = check.facePoints;
        _geometry = check.geometry;
        // No live camera (gallery-only phone): the front photo alone.
        if (_camera == null) return _analyze(check.photo);
        _goToPose(ScanPose.sideA);
      case ScanPose.sideA:
        _sides.add(check.photo);
        _guide?.firstSideYaw = _guide?.lastYaw;
        _goToPose(ScanPose.sideB);
      case ScanPose.sideB:
        _sides.add(check.photo);
        await _analyze(_front!);
    }
  }

  void _goToPose(ScanPose pose) {
    HapticFeedback.selectionClick();
    setState(() => _pose = pose);
    _guide?.pose = pose;
    _backToCamera();
  }

  /// Side photos make the report better; only the first scan requires them.
  Future<void> _skipSides() async {
    await _guide?.stop();
    final front = _front;
    if (front != null) await _analyze(front);
  }

  void _resetPoses() {
    for (final s in _sides) {
      ref.read(photoServiceProvider).discard(s);
    }
    _sides.clear();
    _front = null;
    _pose = ScanPose.front;
    _guide?.firstSideYaw = null;
    _guide?.pose = ScanPose.front;
  }

  Future<bool> _showIssues(CaptureCheck check) async {
    final c = context.colors;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            0,
            Space.gutter,
            Space.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Let\'s get a better photo', style: ctx.text.headlineMedium),
              const SizedBox(height: Space.xs),
              Text(
                'Consistent photos make your progress tracking accurate.',
                style: ctx.text.bodyMedium,
              ),
              const SizedBox(height: Space.md),
              for (final i in check.issues)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        color: c.warn,
                        size: 20,
                      ),
                      const SizedBox(width: Space.xs),
                      Expanded(
                        child: Text(i.message, style: ctx.text.bodyLarge),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: Space.md),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Retake'),
              ),
              if (!check.blocking) ...[
                const SizedBox(height: Space.xs),
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Use this photo anyway'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  Future<void> _analyze(ProcessedPhoto photo) async {
    setState(() {
      _phase = _Phase.analyzing;
      _photo = photo;
    });
    await _camera?.dispose();
    _camera = null;

    final profile = ref.read(profileProvider).value;
    if (profile == null) return;
    try {
      final analysis = await ref
          .read(backendApiProvider)
          .analyzeSkin(
            jpeg: photo.aiJpeg,
            profile: profile,
            previous: ref.read(latestScanProvider)?.analysis,
            issues: _issues,
            sideJpegs: [for (final s in _sides) s.aiJpeg],
          );
      unawaited(ref.read(accountStatusProvider.notifier).refresh());
      final id = newId();
      final path = await ref.read(photoServiceProvider).persist(photo, id);
      // Side photos are only for the analysis; the front one is kept.
      for (final s in _sides) {
        ref.read(photoServiceProvider).discard(s);
      }
      await ref
          .read(scansProvider.notifier)
          .add(
            SkinScan(
              id: id,
              createdAt: clock.now(),
              photoPath: path,
              analysis: analysis,
              face: _geometry,
            ),
          );
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      ref.read(telemetryProvider).track(Ev.scanCompleted, {
        'score': analysis.overallScore,
        'usable': analysis.usable,
        'red_flags': analysis.redFlags.length,
      });
      context.pushReplacement('/scan/$id?fresh=1');
    } on ApiException catch (e) {
      ref.read(telemetryProvider).track(Ev.scanFailed, {'kind': e.kind.name});
      if (!mounted) return;
      switch (e.kind) {
        case ApiErrorKind.premiumRequired:
          final status = await ref
              .read(accountStatusProvider.notifier)
              .refresh();
          if (await _outOfScans(status)) {
            await _analyze(photo);
            return;
          }
        case ApiErrorKind.badImage:
          showSnack(context, e.message);
        default:
          await _showError(e.message);
      }
      ref.read(photoServiceProvider).discard(photo);
      if (!mounted) return;
      _resetPoses();
      setState(() => _phase = _Phase.camera);
      await _initCamera();
    }
  }

  Future<void> _showError(String message) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Scan didn\'t finish'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _Phase.gate => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      _Phase.consent => _ConsentView(onAccept: _acceptConsent),
      _Phase.issues => _IssuesView(
        selected: _issues,
        onToggle: (i) => setState(
          () => _issues.contains(i) ? _issues.remove(i) : _issues.add(i),
        ),
        onDone: _issuesDone,
      ),
      _Phase.camera || _Phase.checking => _cameraView(),
      _Phase.analyzing => _AnalyzingView(photo: _photo, points: _facePoints),
    };
  }

  Widget _cameraView() {
    final cam = _camera;
    final checking = _phase == _Phase.checking;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (cam != null && cam.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: 1 / cam.value.aspectRatio,
                child: CameraPreview(cam),
              ),
            )
          else if (_cameraError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Text(
                  _cameraError!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          IgnorePointer(
            child: ListenableBuilder(
              listenable: _guide ?? const _NoGuide(),
              builder: (context, _) => CustomPaint(
                size: Size.infinite,
                painter: _FaceGuidePainter(
                  aligned: _guide?.hint.ready ?? false,
                  progress: _guide?.progress ?? 0,
                  readyColor: context.colors.leaf,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                      tooltip: 'Close',
                    ),
                    const Spacer(),
                    // The first scan builds the routine, so it needs the
                    // cheeks and jawline from both sides.
                    if (_pose.isSide && ref.watch(latestScanProvider) != null)
                      TextButton(
                        onPressed: checking ? null : _skipSides,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Skip sides'),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.xs),
                  child: Text(
                    '${_pose.index + 1} of ${ScanPose.values.length} · '
                    '${_pose.label}',
                    style: context.text.labelMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                if (_guide != null && !checking)
                  ListenableBuilder(
                    listenable: _guide!,
                    builder: (context, _) => _HintPill(hint: _guide!.hint),
                  )
                else
                  const _Tips(),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.xl),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        onPressed: checking || _pose.isSide
                            ? null
                            : _pickFromGallery,
                        icon: const Icon(
                          Icons.photo_library_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        tooltip: 'Choose from gallery',
                      ),
                      ListenableBuilder(
                        listenable: _guide ?? const _NoGuide(),
                        builder: (context, _) {
                          final locked = _shutterLocked;
                          return AnimatedOpacity(
                            duration: Motion.fast,
                            opacity: locked ? 0.4 : 1,
                            child: Semantics(
                              button: true,
                              label: locked
                                  ? 'Take photo, waiting for a clear view'
                                  : 'Take photo',
                              child: GestureDetector(
                                onTap: checking
                                    ? null
                                    : locked
                                    ? HapticFeedback.selectionClick
                                    : _capture,
                                child: Container(
                                  width: 78,
                                  height: 78,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 4,
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(5),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                    child: checking
                                        ? const Padding(
                                            padding: EdgeInsets.all(20),
                                            child: CircularProgressIndicator(
                                              strokeWidth: 3,
                                            ),
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tips extends StatelessWidget {
  const _Tips();

  @override
  Widget build(BuildContext context) {
    Widget tip(IconData i, String t) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(i, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(
            t,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        tip(Icons.light_mode_rounded, 'Face a window'),
        tip(Icons.face_retouching_off_rounded, 'No makeup or filters'),
        tip(Icons.content_cut_rounded, 'Hair off your face'),
      ],
    );
  }
}

class _FaceGuidePainter extends CustomPainter {
  const _FaceGuidePainter({
    this.aligned = false,
    this.progress = 0,
    this.readyColor = const Color(0xFF4E9A5F),
  });

  final bool aligned;
  final double progress;
  final Color readyColor;

  @override
  void paint(Canvas canvas, Size size) {
    final oval = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.45),
      width: size.width * 0.68,
      height: size.width * 0.68 * 1.32,
    );
    final mask = Path()
      ..addRect(Offset.zero & size)
      ..addOval(oval)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      mask,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    canvas.drawOval(
      oval,
      Paint()
        ..color = aligned ? readyColor : Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = aligned ? 3.5 : 2.5,
    );
    if (progress > 0) {
      // Auto-capture countdown traced around the oval.
      final path = Path()..addOval(oval.inflate(8));
      for (final metric in path.computeMetrics()) {
        canvas.drawPath(
          metric.extractPath(0, metric.length * progress),
          Paint()
            ..color = readyColor
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_FaceGuidePainter old) =>
      old.aligned != aligned || old.progress != progress;
}

/// The one thing to fix right now, and under it the three checks a good
/// scan needs — Light, Position, Still — each lighting up as it passes.
class _HintPill extends StatelessWidget {
  const _HintPill({required this.hint});
  final LiveHint hint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final passed = LiveGuidance.passed(hint);
    return Column(
      children: [
        AnimatedSwitcher(
          duration: Motion.fast,
          child: Container(
            key: ValueKey(hint),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: hint.ready ? c.leaf : Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Text(
              hint.message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.sm),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final check in LiveCheck.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                child: AnimatedDefaultTextStyle(
                  duration: Motion.fast,
                  style: TextStyle(
                    fontFamily: kFontFamily,
                    fontSize: 12,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(
                      alpha: passed.contains(check) ? 1 : 0.4,
                    ),
                    shadows: const [
                      Shadow(color: Color(0x80000000), blurRadius: 6),
                    ],
                  ),
                  child: Text(check.label.toUpperCase()),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Placeholder listenable while the camera is starting.
class _NoGuide implements Listenable {
  const _NoGuide();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

/// "Anything bothering you today?" One tap each, optional. Tells the AI
/// where to look and shapes the report's priorities.
class _IssuesView extends StatelessWidget {
  const _IssuesView({
    required this.selected,
    required this.onToggle,
    required this.onDone,
  });

  final Set<SkinIssue> selected;
  final ValueChanged<SkinIssue> onToggle;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [TextButton(onPressed: onDone, child: const Text('Skip'))],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Anything bothering\nyour skin today?',
                style: context.text.headlineMedium,
              ),
              const SizedBox(height: Space.xs),
              Text(
                'Pick any. The scan looks closer at these.',
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.inkMuted,
                ),
              ),
              const SizedBox(height: Space.lg),
              for (final issue in SkinIssue.values)
                OptionTile(
                  title: issue.label,
                  multi: true,
                  selected: selected.contains(issue),
                  onTap: () => onToggle(issue),
                ),
              const Spacer(),
              FilledButton(
                onPressed: onDone,
                child: Text(selected.isEmpty ? 'Nothing today' : 'Continue'),
              ),
              const SizedBox(height: Space.md),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConsentView extends StatelessWidget {
  const _ConsentView({required this.onAccept});
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget point(IconData i, String t) => Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(i, color: c.primary),
          const SizedBox(width: Space.sm),
          Expanded(child: Text(t, style: context.text.bodyLarge)),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your photos, your control',
                style: context.text.headlineMedium,
              ),
              const SizedBox(height: Space.lg),
              point(
                Icons.phone_android_rounded,
                'Your scan photos are saved only on this phone. You can delete them anytime.',
              ),
              point(
                Icons.cloud_sync_outlined,
                'For analysis, your photo is sent encrypted to our AI provider and processed in real time. We don\'t store it on our servers or use it to train AI.',
              ),
              point(
                Icons.location_off_outlined,
                'Location and device details are stripped from every photo before it leaves your phone.',
              ),
              point(
                Icons.health_and_safety_outlined,
                'ClearSkin gives cosmetic guidance, not a diagnosis. If we notice something that needs a doctor, we\'ll tell you.',
              ),
              const Spacer(),
              FilledButton(
                onPressed: onAccept,
                child: const Text('I agree, continue'),
              ),
              const SizedBox(height: Space.md),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalyzingView extends StatefulWidget {
  const _AnalyzingView({required this.photo, required this.points});
  final ProcessedPhoto? photo;

  /// Real facial contour points (0..1) from on-device detection.
  final List<Offset> points;

  @override
  State<_AnalyzingView> createState() => _AnalyzingViewState();
}

class _AnalyzingViewState extends State<_AnalyzingView>
    with SingleTickerProviderStateMixin {
  static const _messages = [
    'Mapping skin zones',
    'Checking texture and pores',
    'Looking at tone and redness',
    'Assessing hydration and oil',
    'Comparing with your goals',
    'Writing your report',
  ];
  int _i = 0;
  late final Timer _timer;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();
  late final List<(int, int)> _edges = _buildEdges(widget.points);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(milliseconds: 2200),
      (_) => setState(() => _i = (_i + 1) % _messages.length),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    _pulse.dispose();
    super.dispose();
  }

  /// Sparse mesh: connect each point to its two nearest neighbours.
  static List<(int, int)> _buildEdges(List<Offset> pts) {
    final step = pts.length > 90 ? 2 : 1;
    final idx = [for (var i = 0; i < pts.length; i += step) i];
    final edges = <(int, int)>{};
    for (final a in idx) {
      final nearest = [...idx.where((b) => b != a)]
        ..sort(
          (x, y) => (pts[x] - pts[a]).distanceSquared.compareTo(
            (pts[y] - pts[a]).distanceSquared,
          ),
        );
      for (final b in nearest.take(2)) {
        edges.add(a < b ? (a, b) : (b, a));
      }
    }
    return edges.toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final photo = widget.photo;
    final aspect = photo == null ? 0.75 : photo.width / photo.height;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: AuraBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Space.gutter),
              child: Column(
                children: [
                  const Pill(
                    'Analysing your skin',
                    icon: Icons.auto_awesome_outlined,
                  ),
                  const Spacer(),
                  if (photo != null)
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 280,
                        maxHeight: 400,
                      ),
                      child: AspectRatio(
                        aspectRatio: aspect,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.lg),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                File(photo.tempPath),
                                fit: BoxFit.fill,
                              ),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.25),
                                    ],
                                  ),
                                ),
                              ),
                              AnimatedBuilder(
                                animation: _pulse,
                                builder: (_, _) => CustomPaint(
                                  painter: _MeshPainter(
                                    points: widget.points,
                                    edges: _edges,
                                    t: _pulse.value,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: Space.xl),
                  AnimatedSwitcher(
                    duration: Motion.normal,
                    child: Text(
                      _messages[_i],
                      key: ValueKey(_i),
                      style: context.text.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Text('About 15 seconds', style: context.text.bodyMedium),
                  const SizedBox(height: Space.md),
                  SizedBox(
                    width: 120,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.pill),
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        color: c.ink,
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MeshPainter extends CustomPainter {
  _MeshPainter({required this.points, required this.edges, required this.t});
  final List<Offset> points;
  final List<(int, int)> edges;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      // No contours (e.g. gallery photo): a simple scan line instead.
      final y = size.height * t;
      canvas.drawRect(
        Rect.fromLTWH(0, y - 1, size.width, 2),
        Paint()..color = Colors.white.withValues(alpha: 0.8),
      );
      return;
    }
    Offset at(int i) =>
        Offset(points[i].dx * size.width, points[i].dy * size.height);

    // Reveal sweeps top-to-bottom, then holds and gently pulses.
    final sweepY = (t * 1.6).clamp(0.0, 1.0) * size.height;
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 0.7;
    for (final (a, b) in edges) {
      final pa = at(a), pb = at(b);
      if (pa.dy <= sweepY && pb.dy <= sweepY) canvas.drawLine(pa, pb, line);
    }
    final glow = 0.6 + 0.4 * (1 - (t * 2 - 1).abs());
    final dot = Paint()..color = Colors.white.withValues(alpha: glow);
    for (var i = 0; i < points.length; i++) {
      final p = at(i);
      if (p.dy <= sweepY) canvas.drawCircle(p, 1.6, dot);
    }
    if (sweepY < size.height) {
      canvas.drawRect(
        Rect.fromLTWH(0, sweepY - 1, size.width, 2),
        Paint()..color = Colors.white.withValues(alpha: 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(_MeshPainter old) => old.t != t;
}
