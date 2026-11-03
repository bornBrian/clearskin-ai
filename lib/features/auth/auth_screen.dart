import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/env.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../services/auth_service.dart';

enum AuthMode {
  /// Start of onboarding: everyone has an account before their plan is
  /// built, so scans, plan and Premium belong to a person, not a phone.
  create,

  /// Later, for anyone who still has no account: keep the plan and Premium.
  save,

  /// From the welcome screen: an existing account.
  signIn,
}

/// Sign up / sign in. Google first (one tap on Android), passwordless
/// e-mail as the alternative. Pops `true` when signed in.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.mode = AuthMode.save});
  final AuthMode mode;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _busy = false;
  String? _busyProvider;

  Future<void> _done(Account a) async {
    // Skin photos and results are personal. If this phone holds someone
    // else's, the new account never sees them: erase, or don't sign in.
    final owner = await ref.read(accountProvider.notifier).ownerOfLocalData();
    if (!mounted) return;
    if (owner != null && owner != a.key) {
      final erase = await confirm(
        context,
        title: 'This phone has another account\'s skin data',
        body:
            'To sign in as ${a.email ?? 'this account'}, the scans, photos and plan saved here will be erased. They can\'t be recovered.',
        confirmLabel: 'Erase and continue',
        destructive: true,
      );
      if (!erase) {
        await ref.read(authServiceProvider).signOut();
        return;
      }
      await wipeAllLocalData(ref);
      // Let the wiped account state settle before signing the new one in.
      await ref.read(accountProvider.future);
    }
    await ref.read(accountProvider.notifier).set(a);
    // Re-link purchases in case sign-in switched to an existing account.
    final uid = ref.read(backendApiProvider).userId;
    if (uid != null) await ref.read(purchasesServiceProvider).identify(uid);
    if (mounted) context.pop(true);
  }

  Future<void> _google() =>
      _withProvider('google', ref.read(authServiceProvider).signInWithGoogle);

  Future<void> _apple() =>
      _withProvider('apple', ref.read(authServiceProvider).signInWithApple);

  Future<void> _withProvider(
    String provider,
    Future<Account> Function() signIn,
  ) async {
    HapticFeedback.lightImpact();
    setState(() {
      _busy = true;
      _busyProvider = provider;
    });
    try {
      await _done(await signIn());
    } on AuthFailure catch (e) {
      if (!e.cancelled && mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _email() async {
    final account = await showModalBottomSheet<Account>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
      ),
      builder: (_) => const _EmailSheet(),
    );
    if (account != null) await _done(account);
  }

  @override
  Widget build(BuildContext context) {
    final save = widget.mode == AuthMode.save;
    final (title, subtitle) = switch (widget.mode) {
      AuthMode.create => (
        'Start with\nyour account.',
        'Your plan, scans and Premium stay yours, on any phone.',
      ),
      AuthMode.save => (
        'Keep your plan.',
        'Your Premium and plan, on any phone.',
      ),
      AuthMode.signIn => ('Welcome back.', 'Sign in to restore Premium.'),
    };
    final size = MediaQuery.sizeOf(context);
    final top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: BrandColors.charcoal,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: size.height * 0.62,
              child: const _Portraits().animate().fadeIn(duration: 700.ms),
            ),
            // Blend the photo into the charcoal sheet.
            Positioned(
              left: 0,
              right: 0,
              top: size.height * 0.62 - 2,
              bottom: 0,
              child: const ColoredBox(color: BrandColors.charcoal),
            ),
            Positioned(
              top: top + Space.sm,
              left: Space.gutter,
              right: Space.sm,
              child: Row(
                children: [
                  const BrandMark(size: 52, color: BrandColors.cream),
                  const Spacer(),
                  if (widget.mode == AuthMode.create)
                    TextButton(
                      onPressed: _busy ? null : () => context.pop(false),
                      style: TextButton.styleFrom(
                        foregroundColor: BrandColors.cream,
                      ),
                      child: const Text('Back'),
                    )
                  else if (save)
                    TextButton(
                      onPressed: _busy ? null : () => context.pop(false),
                      style: TextButton.styleFrom(
                        foregroundColor: BrandColors.cream,
                      ),
                      child: const Text('Not now'),
                    )
                  else
                    IconButton(
                      onPressed: () => context.pop(false),
                      tooltip: 'Close',
                      icon: const Icon(
                        Icons.close_rounded,
                        color: BrandColors.cream,
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              left: Space.gutter,
              right: Space.gutter,
              bottom: 0,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: Space.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.text.displaySmall?.copyWith(
                        color: BrandColors.cream,
                      ),
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      subtitle,
                      style: context.text.bodyLarge?.copyWith(
                        color: BrandColors.cream.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: Space.lg),
                    if (AuthService.appleAvailable) ...[
                      _AuthButton(
                        label: 'Continue with Apple',
                        leading: const Icon(
                          Icons.apple,
                          size: 22,
                          color: BrandColors.charcoal,
                        ),
                        light: true,
                        busy: _busy && _busyProvider == 'apple',
                        onTap: _busy ? null : _apple,
                      ),
                      const SizedBox(height: Space.sm),
                    ],
                    if (AuthService.googleAvailable) ...[
                      _AuthButton(
                        label: 'Continue with Google',
                        leading: const GoogleG(size: 20),
                        light: !AuthService.appleAvailable,
                        busy: _busy && _busyProvider == 'google',
                        onTap: _busy ? null : _google,
                      ),
                      const SizedBox(height: Space.sm),
                    ],
                    _AuthButton(
                      label: 'Continue with email',
                      leading: const Icon(
                        Icons.mail_outline_rounded,
                        size: 20,
                        color: BrandColors.cream,
                      ),
                      onTap: _busy ? null : _email,
                    ),
                    const SizedBox(height: Space.md),
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        children: [
                          Text(
                            'By continuing you agree to our ',
                            style: context.text.bodySmall?.copyWith(
                              color: BrandColors.cream.withValues(alpha: 0.5),
                            ),
                          ),
                          _Link('Terms', Env.termsUrl),
                          Text(
                            ' and ',
                            style: context.text.bodySmall?.copyWith(
                              color: BrandColors.cream.withValues(alpha: 0.5),
                            ),
                          ),
                          _Link('Privacy Policy', Env.privacyPolicyUrl),
                        ],
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: 150.ms, duration: Motion.slow),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.text, this.url);
  final String text;
  final String url;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => launchUrl(Uri.parse(url)),
    child: Text(
      text,
      style: context.text.bodySmall?.copyWith(
        color: BrandColors.cream.withValues(alpha: 0.8),
        decoration: TextDecoration.underline,
        decorationColor: BrandColors.cream.withValues(alpha: 0.4),
      ),
    ),
  );
}

class _AuthButton extends StatelessWidget {
  const _AuthButton({
    required this.label,
    required this.leading,
    required this.onTap,
    this.light = false,
    this.busy = false,
  });

  final String label;
  final Widget leading;
  final VoidCallback? onTap;
  final bool light;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final fg = light ? BrandColors.charcoal : BrandColors.cream;
    return Material(
      color: light ? BrandColors.cream : Colors.transparent,
      shape: StadiumBorder(
        side: light
            ? BorderSide.none
            : BorderSide(color: BrandColors.cream.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              else
                leading,
              const SizedBox(width: Space.sm),
              Text(
                label,
                style: context.text.titleMedium?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmailSheet extends ConsumerStatefulWidget {
  const _EmailSheet();

  @override
  ConsumerState<_EmailSheet> createState() => _EmailSheetState();
}

class _EmailSheetState extends ConsumerState<_EmailSheet> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _error;

  /// The store review account: a password instead of an emailed code.
  bool get _review =>
      Env.reviewEmail.isNotEmpty &&
      _email.text.trim().toLowerCase() == Env.reviewEmail.toLowerCase();

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  Future<void> _send() async {
    if (!_emailRe.hasMatch(_email.text.trim())) {
      setState(() => _error = 'Enter a valid email.');
      return;
    }
    if (_review) {
      setState(() {
        _sent = true;
        _error = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).sendEmailCode(_email.text);
      if (mounted) setState(() => _sent = true);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_review ? _code.text.isEmpty : _code.text.trim().length < 6) {
      setState(
        () => _error = _review
            ? 'Enter the password.'
            : 'Enter the 6-digit code.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = ref.read(authServiceProvider);
      final a = _review
          ? await auth.signInWithPassword(_email.text, _code.text)
          : await auth.verifyEmailCode(_email.text, _code.text);
      if (mounted) Navigator.of(context).pop(a);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        MediaQuery.viewInsetsOf(context).bottom + Space.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            !_sent
                ? 'Your email'
                : _review
                ? 'Your password'
                : 'Check your inbox',
            style: context.text.headlineSmall,
          ),
          const SizedBox(height: Space.xxs),
          Text(
            !_sent
                ? 'We\'ll send you a code. No password.'
                : _review
                ? 'This address signs in with a password.'
                : 'We sent a 6-digit code to ${_email.text.trim()}.',
            style: context.text.bodyMedium,
          ),
          const SizedBox(height: Space.lg),
          if (!_sent)
            TextField(
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(hintText: 'name@email.com'),
            )
          else if (_review)
            TextField(
              controller: _code,
              autofocus: true,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _verify(),
              decoration: const InputDecoration(hintText: 'Password'),
            )
          else
            TextField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: 6,
              textAlign: TextAlign.center,
              style: context.text.headlineMedium?.copyWith(letterSpacing: 10),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) {
                if (v.length == 6) _verify();
              },
              decoration: const InputDecoration(
                counterText: '',
                hintText: '••••••',
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: Space.xs),
            Text(
              _error!,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.bad,
              ),
            ),
          ],
          const SizedBox(height: Space.lg),
          FilledButton(
            onPressed: _busy ? null : (_sent ? _verify : _send),
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_sent ? 'Verify' : 'Send code'),
          ),
          if (_sent)
            Center(
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _sent = false;
                        _code.clear();
                      }),
                child: const Text('Use a different email'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Google's four-colour "G", drawn to the brand guidelines' proportions so
/// no image asset or icon font is needed.
class GoogleG extends StatelessWidget {
  const GoogleG({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _GPainter()),
  );
}

class _GPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final w = s * 0.2;
    final rect = Rect.fromCircle(
      center: Offset(s / 2, s / 2),
      radius: s / 2 - w / 2,
    );
    double rad(double deg) => deg * math.pi / 180;
    Paint p(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;

    canvas.drawArc(rect, rad(-40), rad(85), false, p(_blue));
    canvas.drawArc(rect, rad(45), rad(90), false, p(_green));
    canvas.drawArc(rect, rad(135), rad(80), false, p(_yellow));
    canvas.drawArc(rect, rad(215), rad(100), false, p(_red));
    // The crossbar.
    canvas.drawRect(
      Rect.fromLTWH(s / 2, s / 2 - w / 2, s / 2 - w * 0.05, w),
      Paint()..color = _blue,
    );
  }

  @override
  bool shouldRepaint(_GPainter old) => false;
}

/// The sign-in portraits, different skin tones: they slide from one to the
/// next on their own and can be swiped either way. No one face stands for
/// everyone.
class _Portraits extends StatefulWidget {
  const _Portraits();

  @override
  State<_Portraits> createState() => _PortraitsState();
}

class _PortraitsState extends State<_Portraits> {
  static const _every = Duration(seconds: 4);
  static const _photos = Photos.authPortraits;

  // Far from the ends, so swiping back from the first photo works too.
  final _page = PageController(initialPage: 1000 * _photos.length);
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    if (MediaQuery.disableAnimationsOf(context)) return;
    _timer = Timer.periodic(_every, (_) {
      if (_page.hasClients) {
        _page.nextPage(
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Holding or swiping pauses the slideshow; letting go restarts it.
      onPointerDown: (_) => _timer?.cancel(),
      onPointerUp: (_) => _restart(),
      child: PageView.builder(
        controller: _page,
        itemBuilder: (_, i) => PhotoFill(
          _photos[i % _photos.length],
          alignment: const Alignment(0, -0.2),
          scrim: 1,
          scrimStart: 0.45,
          scrimColor: BrandColors.charcoal,
        ),
      ),
    );
  }
}
