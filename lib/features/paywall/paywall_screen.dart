import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_store.dart';
import '../../core/config/env.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/repositories/repositories.dart';
import '../../services/purchases_service.dart';
import '../../services/telemetry.dart';

final _plansProvider = FutureProvider.autoDispose<List<Plan>>(
  (ref) => ref.read(purchasesServiceProvider).plans(),
);

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, required this.source});

  /// Where the paywall was opened from (analytics + copy).
  final String source;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  Plan? _selected;

  @override
  void initState() {
    super.initState();
    ref.read(telemetryProvider).track(Ev.paywallView, {
      'source': widget.source,
    });
  }

  bool _busy = false;
  bool _remindTrial = true;

  String get _headline => switch (widget.source) {
    'coach' => 'Answers that\nknow your skin.',
    'compare' || 'trends' => 'See every bit\nof progress.',
    'insights' => 'Find what breaks\nyou out.',
    'scan' => 'Scan every week.\nWatch it change.',
    'products' => 'Check everything\nyou own.',
    'renewal' => 'Keep your\nprogress going.',
    'ads' => 'No ads.\nJust your skin.',
    _ => 'Everything your\nskin plan needs.',
  };

  Future<void> _buy() async {
    final plan = _selected;
    if (plan == null || _busy) return;
    setState(() => _busy = true);
    final outcome = await ref.read(purchasesServiceProvider).purchase(plan);
    if (!mounted) return;
    setState(() => _busy = false);
    ref.read(telemetryProvider).track(Ev.purchaseResult, {
      'outcome': outcome.name,
      'plan': plan.title,
      'trial': plan.trialDays != null,
      'source': widget.source,
    });
    switch (outcome) {
      case PurchaseOutcome.success:
        if (_remindTrial && plan.trialDays != null) {
          unawaited(
            ref
                .read(notificationServiceProvider)
                .scheduleTrialEndingReminder(plan.trialDays!),
          );
        }
        showSnack(context, 'Welcome to Premium');
        Navigator.of(context).pop(true);
      case PurchaseOutcome.pending:
        showSnack(
          context,
          'Payment pending. Premium unlocks as soon as it\'s confirmed.',
        );
      case PurchaseOutcome.cancelled:
        break;
      case PurchaseOutcome.failed:
        showSnack(context, 'Purchase didn\'t go through. Please try again.');
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    final ok = await ref.read(purchasesServiceProvider).restore();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      showSnack(context, 'Premium restored.');
      Navigator.of(context).pop(true);
    } else {
      showSnack(context, 'No active subscription found for this account.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(_plansProvider);
    const cream = BrandColors.cream;
    final dim = cream.withValues(alpha: 0.6);

    return Scaffold(
      backgroundColor: BrandColors.charcoal,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.xs,
                  Space.xxs,
                  Space.sm,
                  0,
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: Icon(Icons.close_rounded, color: dim),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _busy ? null : _restore,
                      style: TextButton.styleFrom(foregroundColor: dim),
                      child: const Text('Restore'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    Space.gutter,
                    Space.xs,
                    Space.gutter,
                    Space.lg,
                  ),
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: BrandMark(size: 56, color: cream),
                    ),
                    const SizedBox(height: Space.lg),
                    Eyebrow('ClearSkin Premium', color: dim),
                    const SizedBox(height: Space.sm),
                    Text(
                      _headline,
                      style: context.text.displaySmall?.copyWith(
                        color: cream,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: Space.xl),
                    const _Comparison(),
                    const SizedBox(height: Space.xl),
                    plans.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(Space.xl),
                        child: Center(
                          child: CircularProgressIndicator(color: cream),
                        ),
                      ),
                      error: (e, _) => _Unavailable(
                        issue: e is PlansUnavailable
                            ? e.issue
                            : PlansIssue.storeUnavailable,
                        onRetry: () => ref.invalidate(_plansProvider),
                      ),
                      data: (list) {
                        if (list.isEmpty) {
                          return _Unavailable(
                            issue: PlansIssue.noProducts,
                            onRetry: () => ref.invalidate(_plansProvider),
                          );
                        }
                        _selected ??= list.firstWhere(
                          (p) => p.isAnnual,
                          orElse: () => list.first,
                        );
                        final maxWeekly = list
                            .map((p) => p.pricePerWeek)
                            .reduce((a, b) => a > b ? a : b);
                        final trial = _selected?.trialDays;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (trial != null) ...[
                              _TrialTimeline(days: trial),
                              const SizedBox(height: Space.xl),
                            ],
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var i = 0; i < list.length; i++) ...[
                                    if (i > 0) const SizedBox(width: Space.sm),
                                    Expanded(
                                      child: _PlanTile(
                                        plan: list[i],
                                        selected: _selected == list[i],
                                        best: i == 0,
                                        savings: maxWeekly <= 0
                                            ? 0
                                            : ((1 -
                                                          list[i].pricePerWeek /
                                                              maxWeekly) *
                                                      100)
                                                  .round(),
                                        onTap: () =>
                                            setState(() => _selected = list[i]),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (trial != null)
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _remindTrial,
                                onChanged: (v) =>
                                    setState(() => _remindTrial = v),
                                activeThumbColor: BrandColors.charcoal,
                                activeTrackColor: cream,
                                title: Text(
                                  'Remind me before I\'m charged',
                                  style: context.text.titleSmall?.copyWith(
                                    color: cream,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.xs,
                  Space.gutter,
                  Space.xs,
                ),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: cream,
                          foregroundColor: BrandColors.charcoal,
                          disabledBackgroundColor: cream.withValues(alpha: 0.3),
                        ),
                        onPressed: _selected == null || _busy ? null : _buy,
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: BrandColors.charcoal,
                                ),
                              )
                            : Text(
                                _selected?.trialDays != null
                                    ? 'Start my ${_selected!.trialDays}-day free trial'
                                    : 'Continue',
                              ),
                      ),
                    ),
                    const SizedBox(height: Space.sm),
                    Text(
                      _finePrint(_selected),
                      style: context.text.bodySmall?.copyWith(
                        color: cream.withValues(alpha: 0.5),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          style: TextButton.styleFrom(foregroundColor: dim),
                          onPressed: () => launchUrl(Uri.parse(Env.termsUrl)),
                          child: const Text('Terms'),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(foregroundColor: dim),
                          onPressed: () =>
                              launchUrl(Uri.parse(Env.privacyPolicyUrl)),
                          child: const Text('Privacy'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _finePrint(Plan? p) {
    if (p == null) return '';
    if (p.prepaid) {
      return '${p.priceString} for one ${p.periodLabel}. Doesn\'t renew '
          'automatically; we\'ll remind you a week before it ends.';
    }
    final period = p.periodLabel.isEmpty ? '' : ' a ${p.periodLabel}';
    final trial = p.trialDays != null
        ? '${p.trialDays} days free, then ${p.priceString}$period. '
        : '${p.priceString}$period. ';
    return '${trial}Renews automatically. Cancel anytime ${AppStore.manageIn}.';
  }
}

/// What Premium adds, side by side with free. Only features that are
/// really gated are listed.
class _Comparison extends StatelessWidget {
  const _Comparison();

  static const _rows = [
    ('Skin scans', '2 a month', 'Unlimited'),
    ('Ads', 'Yes', 'None'),
    ('AI skin coach', null, '✓'),
    ('Before & after, with cards', null, '✓'),
    ('Every measure, over time', null, '✓'),
    ('Breakout triggers', null, '✓'),
    ('Product checks', '3 a day', 'Unlimited'),
  ];

  @override
  Widget build(BuildContext context) {
    const cream = BrandColors.cream;
    final dim = cream.withValues(alpha: 0.45);
    final line = cream.withValues(alpha: 0.12);
    Widget cell(String? text, {bool strong = false}) => SizedBox(
      width: 86,
      child: text == '✓'
          ? const Icon(Icons.check_rounded, size: 20, color: cream)
          : Text(
              text ?? '—',
              textAlign: TextAlign.center,
              style: context.text.titleSmall?.copyWith(
                color: strong ? cream : dim,
                fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
    );
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: SizedBox()),
            SizedBox(
              width: 86,
              child: Text(
                'FREE',
                textAlign: TextAlign.center,
                style: context.text.labelSmall?.copyWith(
                  color: dim,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Container(
              width: 86,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: const BoxDecoration(
                color: cream,
                borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
              ),
              child: Text(
                'PREMIUM',
                textAlign: TextAlign.center,
                style: context.text.labelSmall?.copyWith(
                  color: BrandColors.charcoal,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        for (final (feature, free, premium) in _rows)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    feature,
                    style: context.text.bodyMedium?.copyWith(color: cream),
                  ),
                ),
                cell(free),
                cell(premium, strong: true),
              ],
            ),
          ),
      ],
    );
  }
}

/// The honest trial: what happens today, when we remind you, when you pay.
class _TrialTimeline extends StatelessWidget {
  const _TrialTimeline({required this.days});
  final int days;

  @override
  Widget build(BuildContext context) {
    const cream = BrandColors.cream;
    final steps = [
      ('Today', 'Full Premium, free'),
      ('Day ${days - 1}', 'We remind you'),
      ('Day $days', 'Your plan starts'),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == 0 ? cream : Colors.transparent,
                        border: Border.all(color: cream),
                      ),
                    ),
                    if (i < steps.length - 1)
                      Expanded(
                        child: Container(
                          height: 1,
                          color: cream.withValues(alpha: 0.25),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                Text(
                  steps[i].$1,
                  style: context.text.titleSmall?.copyWith(color: cream),
                ),
                const SizedBox(height: 2),
                Text(
                  steps[i].$2,
                  style: context.text.bodySmall?.copyWith(
                    color: cream.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.selected,
    required this.best,
    required this.savings,
    required this.onTap,
  });

  final Plan plan;
  final bool selected;
  final bool best;
  final int savings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const cream = BrandColors.cream;
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: selected ? cream.withValues(alpha: 0.08) : null,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: selected ? cream : cream.withValues(alpha: 0.2),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    plan.title.toUpperCase(),
                    style: context.text.labelSmall?.copyWith(
                      color: cream.withValues(alpha: 0.7),
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  if (best && savings >= 10)
                    Text(
                      '−$savings%',
                      style: context.text.labelMedium?.copyWith(
                        color: cream,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Space.md),
              Text(
                plan.pricePerWeekString ?? plan.priceString,
                style: context.text.headlineMedium?.copyWith(
                  color: cream,
                  fontWeight: FontWeight.w300,
                ),
              ),
              Text(
                plan.pricePerWeekString == null ? '' : 'a week',
                style: context.text.bodySmall?.copyWith(
                  color: cream.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: Space.sm),
              Text(
                plan.prepaid
                    ? '${plan.priceString} once'
                    : '${plan.priceString} / ${plan.periodLabel}',
                style: context.text.labelMedium?.copyWith(
                  color: cream.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Unavailable extends ConsumerWidget {
  const _Unavailable({required this.issue, required this.onRetry});
  final PlansIssue issue;
  final VoidCallback onRetry;

  /// What went wrong, in words that point at the fix. Debug builds say
  /// exactly which piece of setup is missing.
  String get _message => switch (issue) {
    PlansIssue.notConfigured =>
      kDebugMode
          ? 'Billing isn\'t set up in this build: RC_ANDROID_KEY is empty in env/dev.json.'
          : 'Premium is opening very soon. Everything free stays free.',
    PlansIssue.noProducts =>
      kDebugMode
          ? 'RevenueCat has no packages in its current offering. Create the subscriptions in Play Console, import them in RevenueCat and add them to the "default" offering.'
          : 'Plans aren\'t available in your region yet. Please check back soon.',
    PlansIssue.storeUnavailable => AppStore.billingUnavailable,
    PlansIssue.offline => 'You\'re offline. Connect to see plans.',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const cream = BrandColors.cream;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.lg),
      child: Column(
        children: [
          Text(
            _message,
            style: context.text.bodyMedium?.copyWith(color: cream),
            textAlign: TextAlign.center,
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: cream),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
          if (kDebugMode)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: BrandColors.charcoal,
              ),
              onPressed: () async {
                ref.read(purchasesServiceProvider).setDevPremium(true);
                await ref.read(kvProvider).set(KvKeys.devPremium, '1');
                if (context.mounted) Navigator.of(context).pop(true);
              },
              child: const Text('Debug: enable dev Premium'),
            ),
        ],
      ),
    );
  }
}
