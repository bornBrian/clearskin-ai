import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../services/backend_api.dart';
import '../../services/telemetry.dart';

final referralStatusProvider = FutureProvider.autoDispose<ReferralStatus?>(
  (ref) => ref.read(backendApiProvider).referralStatus(),
);

/// Invite a friend: when they enter your code and finish their first scan,
/// you both get a free scan.
class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({super.key});

  /// The store link, tagged so Play Console can count invited installs.
  static String link(String code) =>
      'https://play.google.com/store/apps/details?id=com.clearskinai.app'
      '&referrer=utm_source%3Dreferral%26utm_campaign%3D$code';

  static String message(String code) =>
      'I check my skin with ClearSkin AI. Get it here: ${link(code)}\n'
      'Enter my code $code in Settings → Invite a friend, and after your '
      'first scan we both get a free scan.';

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _share(String code) async {
    ref.read(telemetryProvider).track(Ev.inviteShared);
    await SharePlus.instance.share(
      ShareParams(text: InviteScreen.message(code)),
    );
  }

  Future<void> _redeem() async {
    final code = _code.text.trim().toUpperCase();
    if (code.length != 6) {
      showSnack(context, 'Codes are 6 letters and numbers.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(backendApiProvider).redeemReferral(code);
      ref.read(telemetryProvider).track(Ev.inviteRedeemed);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _code.clear();
      showSnack(
        context,
        'Code added. Finish your first scan to get your free scan.',
      );
      ref.invalidate(referralStatusProvider);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(referralStatusProvider);
    final signedIn = ref.watch(accountProvider).value != null;

    return Scaffold(
      body: AuraBackground(
        intensity: 0.5,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.xs,
              Space.gutter,
              Space.xxl,
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: CircleButton(
                  icon: Icons.arrow_back_rounded,
                  size: 42,
                  tooltip: 'Back',
                  onTap: () => context.pop(),
                ),
              ),
              const SizedBox(height: Space.lg),
              Text('Invite a friend', style: context.text.displaySmall),
              const SizedBox(height: Space.sm),
              Text(
                'When a friend enters your code and finishes their first '
                'scan, you both get a free scan.',
                style: context.text.bodyLarge?.copyWith(
                  color: context.colors.inkMuted,
                ),
              ),
              const SizedBox(height: Space.xl),
              if (!signedIn)
                Text(
                  'Sign in to get your invite code.',
                  style: context.text.bodyLarge,
                )
              else
                status.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(Space.lg),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => const _Offline(),
                  data: (s) => s == null || s.code.isEmpty
                      ? const _Offline()
                      : _Mine(status: s, onShare: () => _share(s.code)),
                ),
              if (signedIn && !(status.value?.redeemed ?? true)) ...[
                const SizedBox(height: Space.xxl),
                const Eyebrow('Got a code from a friend?'),
                const SizedBox(height: Space.sm),
                TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  autocorrect: false,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                  ],
                  decoration: const InputDecoration(
                    hintText: 'Their 6-character code',
                    counterText: '',
                  ),
                  onSubmitted: (_) => _redeem(),
                ),
                const SizedBox(height: Space.md),
                ArrowPill(
                  label: _busy ? 'Adding…' : 'Add code',
                  onTap: _busy ? null : _redeem,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Mine extends StatelessWidget {
  const _Mine({required this.status, required this.onShare});

  final ReferralStatus status;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final n = status.rewarded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Your code'),
        const SizedBox(height: Space.xs),
        GestureDetector(
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: status.code));
            showSnack(context, 'Code copied');
          },
          child: Text(
            status.code,
            style: context.text.displayMedium?.copyWith(
              letterSpacing: 6,
              fontWeight: FontWeight.w300,
            ),
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(
          n == 0
              ? 'No friends have scanned with it yet.'
              : '$n ${n == 1 ? 'friend has' : 'friends have'} scanned with it. '
                    'That\'s $n free ${n == 1 ? 'scan' : 'scans'} for you.',
          style: context.text.bodyMedium?.copyWith(
            color: context.colors.inkMuted,
          ),
        ),
        const SizedBox(height: Space.lg),
        ArrowPill(
          label: 'Share invite',
          icon: Icons.ios_share_rounded,
          dark: true,
          onTap: onShare,
        ),
      ],
    );
  }
}

class _Offline extends StatelessWidget {
  const _Offline();

  @override
  Widget build(BuildContext context) => Text(
    'Your code needs a connection. Try again in a moment.',
    style: context.text.bodyLarge,
  );
}
