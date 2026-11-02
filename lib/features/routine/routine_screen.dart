import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/text.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/check_in.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/guidance/application_guide.dart';
import '../../domain/guidance/habits.dart';
import '../../domain/routine/routine_engine.dart';
import '../../domain/routine/streaks.dart';
import '../../domain/shop/shop_links.dart';
import '../../services/telemetry.dart';
import '../ads/ad_banner.dart';
import '../scan/first_scan_card.dart';
import '../shop/shop_link.dart';
import 'streak_flame.dart';
import 'streak_widgets.dart';

/// Ticks a step for today and celebrates (quietly) when a slot completes.
/// Shared by the Routine tab and the Today checklist.
Future<void> toggleRoutineStep(
  WidgetRef ref,
  BuildContext context,
  RoutineSlot slot,
  RoutineStep step,
  List<RoutineStep> required,
) async {
  HapticFeedback.lightImpact();
  final streakBefore = ref.read(streakStateProvider);
  final before = ref.read(todayCompletedProvider(slot));
  await ref
      .read(routineLogsProvider.notifier)
      .toggle(Dates.today(), slot, step.id);
  final after = ref.read(todayCompletedProvider(slot));
  final wasDone = required.every((s) => before.contains(s.id));
  final nowDone = required.every((s) => after.contains(s.id));
  if (wasDone || !nowDone) return;
  ref.read(telemetryProvider).track(Ev.routineCompleted, {'slot': slot.name});
  HapticFeedback.mediumImpact();
  final streak = ref.read(streakStateProvider);

  // A milestone gets its own moment (once a day), instead of a snackbar
  // and never alongside an ad.
  final kv = ref.read(kvProvider);
  final today = Dates.today();
  final celebrated = await kv.get(KvKeys.streakCelebrated) == today;
  if (Streaks.milestones.contains(streak.current) && !celebrated) {
    unawaited(kv.set(KvKeys.streakCelebrated, today));
    if (!context.mounted) return;
    final wantsPremium = await showStreakCelebration(context, state: streak);
    if (wantsPremium == true && context.mounted) {
      await context.push('/paywall?source=streak');
      return;
    }
    if (streak.current == 7 || streak.current == 30) {
      unawaited(ref.read(reviewServiceProvider).maybePrompt());
    }
    return;
  }

  if (!streakBefore.doneToday && streak.doneToday && !celebrated) {
    // Today's first routine: the streak goes up. Its own small moment,
    // once a day, like other streak apps.
    unawaited(kv.set(KvKeys.streakCelebrated, today));
    if (!context.mounted) return;
    await showStreakExtended(context, streak);
  } else if (context.mounted) {
    showSnack(
      context,
      '${slot == RoutineSlot.am ? 'Morning' : 'Evening'} done'
      '${streak.current > 1 ? ' · ${streak.current}-day streak' : ''}',
    );
  }
  if (ref.read(showAdsProvider)) {
    // The natural break: the routine is done. Capped and skipped in the
    // first days (see AdsService), and never for Premium.
    final ads = ref.read(adsServiceProvider);
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 1400),
        ads.maybeShowInterstitial,
      ),
    );
  }
}

void showStepSheet(BuildContext context, RoutineStep s) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
    ),
    builder: (_) => _StepSheet(step: s),
  );
}

/// The one line under a step's name: the shelf product if matched, else
/// the key ingredient.
String stepSubtitle(RoutineStep s) {
  if (s.matchedProduct != null) return s.matchedProduct!.displayName;
  if (s.keyIngredients.isNotEmpty) return s.keyIngredients.first;
  return s.category.label;
}

class RoutineScreen extends ConsumerStatefulWidget {
  const RoutineScreen({super.key});

  @override
  ConsumerState<RoutineScreen> createState() => _RoutineScreenState();
}

class _RoutineScreenState extends ConsumerState<RoutineScreen> {
  late RoutineSlot _slot = clock.now().hour >= 15
      ? RoutineSlot.pm
      : RoutineSlot.am;
  String? _appliedSlot;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final slot = GoRouterState.of(context).uri.queryParameters['slot'];
    if (slot != null && slot != _appliedSlot) {
      _appliedSlot = slot;
      _slot = slot == 'pm' ? RoutineSlot.pm : RoutineSlot.am;
    }
  }

  @override
  Widget build(BuildContext context) {
    final routine = ref.watch(routineProvider);
    final c = context.colors;
    if (routine == null) {
      if (ref.watch(profileProvider).value == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return const _ScanFirst();
    }
    final now = clock.now();
    final today = routine.stepsFor(_slot, now);
    final done = ref.watch(todayCompletedProvider(_slot));
    final required = today.where((s) => !s.optional).toList();
    final completed = required.where((s) => done.contains(s.id)).length;
    final weekly = routine.pm.where((s) => s.days.isNotEmpty).toList();
    final profile = ref.watch(profileProvider).value;
    final habits = profile == null
        ? const <Habit>[]
        : HabitCoach.pick(
            profile: profile,
            latest: ref.watch(latestScanProvider)?.analysis,
          );
    final adSpace = ref.watch(showAdsProvider) ? AdBanner.reserve : 0.0;

    return Scaffold(
      body: AuraBackground(
        intensity: 0.6,
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              Space.gutter,
              Space.md,
              Space.gutter,
              Space.navClearance(context) + adSpace,
            ),
            children: [
              Eyebrow(DateFormat('EEEE, d MMMM').format(now)),
              const SizedBox(height: Space.xs),
              Text('Routine', style: context.text.displaySmall),
              const SizedBox(height: Space.lg),
              TextTabs(
                labels: const ['Morning', 'Evening'],
                index: _slot.index,
                onChanged: (i) => setState(() => _slot = RoutineSlot.values[i]),
              ),
              const SizedBox(height: Space.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$completed',
                    style: context.text.displaySmall?.copyWith(
                      fontWeight: FontWeight.w200,
                    ),
                  ),
                  Text(
                    ' / ${required.length} done',
                    style: context.text.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(
                    end: required.isEmpty ? 0 : completed / required.length,
                  ),
                  duration: Motion.slow,
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 3,
                    color: c.ink,
                    backgroundColor: c.line,
                  ),
                ),
              ),
              const SizedBox(height: Space.lg),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: Space.md + 2),
                child: Column(
                  children: [
                    for (var i = 0; i < today.length; i++)
                      StepRow(
                        index: i + 1,
                        step: today[i],
                        done: done.contains(today[i].id),
                        divider: i < today.length - 1,
                        onToggle: () => toggleRoutineStep(
                          ref,
                          context,
                          _slot,
                          today[i],
                          required,
                        ),
                        onOpen: () => showStepSheet(context, today[i]),
                      ),
                  ],
                ),
              ),
              if (_slot == RoutineSlot.pm && weekly.isNotEmpty) ...[
                const SizedBox(height: Space.xl),
                const Eyebrow('This week'),
                const SizedBox(height: Space.md),
                _WeekStrip(steps: weekly),
              ],
              if (habits.isNotEmpty) ...[
                const SizedBox(height: Space.xl),
                const Eyebrow('Habits'),
                const SizedBox(height: Space.xs),
                for (var i = 0; i < habits.length; i++)
                  _HabitRow(
                    n: i + 1,
                    habit: habits[i],
                    last: i == habits.length - 1,
                  ),
              ],
              const SizedBox(height: Space.xl),
              LineItem(
                title: 'Can\'t buy a step yet?',
                subtitle: 'Cheap swaps, and kitchen things that help or harm',
                trailing: Icon(Icons.chevron_right_rounded, color: c.inkFaint),
                onTap: () => context.push('/guide/budget'),
              ),
              LineItem(
                title: 'Skin guides',
                subtitle: 'Food, water, weather, bedding',
                trailing: Icon(Icons.chevron_right_rounded, color: c.inkFaint),
                divider: false,
                onTap: () => context.push('/guides'),
              ),
              const SizedBox(height: Space.md),
              Center(
                child: TextButton(
                  onPressed: () => _showNotes(context, routine.notes),
                  child: const Text('How your routine works'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNotes(BuildContext context, List<String> notes) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
      ),
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.lg,
          Space.gutter,
          Space.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How it works', style: ctx.text.headlineSmall),
            const SizedBox(height: Space.md),
            for (var i = 0; i < notes.length; i++)
              _Numbered(n: i + 1, text: notes[i], last: i == notes.length - 1),
            const SizedBox(height: Space.lg),
            const Eyebrow('Layering'),
            const SizedBox(height: Space.xs),
            for (var i = 0; i < ApplicationGuide.layering.length; i++)
              _Numbered(
                n: i + 1,
                text: ApplicationGuide.layering[i],
                last: i == ApplicationGuide.layering.length - 1,
              ),
            const SizedBox(height: Space.lg),
            const Disclaimer(),
          ],
        ),
      ),
    );
  }
}

/// Before the first scan there's no routine to show: say why, and start it.
class _ScanFirst extends StatelessWidget {
  const _ScanFirst();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuraBackground(
        intensity: 0.6,
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              Space.gutter,
              Space.md,
              Space.gutter,
              Space.navClearance(context),
            ),
            children: [
              Eyebrow(DateFormat('EEEE, d MMMM').format(clock.now())),
              const SizedBox(height: Space.xs),
              Text('Routine', style: context.text.displaySmall),
              const SizedBox(height: Space.sm),
              Text(
                'Your routine comes from your scan. It reads what your skin '
                'needs first, so no step is a guess.',
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.inkMuted,
                ),
              ),
              const SizedBox(height: Space.lg),
              const FirstScanCard(),
            ],
          ),
        ),
      ),
    );
  }
}

/// A routine step: number, name, one line, and a check circle. Tapping the
/// name opens details; tapping the circle ticks it off.
class StepRow extends StatelessWidget {
  const StepRow({
    super.key,
    required this.index,
    required this.step,
    required this.done,
    required this.onToggle,
    required this.onOpen,
    this.divider = true,
  });

  final int index;
  final RoutineStep step;
  final bool done;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        border: divider ? Border(bottom: BorderSide(color: c.line)) : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text(
                        index.toString().padLeft(2, '0'),
                        style: context.text.titleSmall?.copyWith(
                          color: c.inkFaint,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedDefaultTextStyle(
                            duration: Motion.fast,
                            style: context.text.titleMedium!.copyWith(
                              fontWeight: FontWeight.w500,
                              color: done ? c.inkMuted : c.ink,
                            ),
                            child: Text(step.title),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            step.optional
                                ? 'Optional · ${stepSubtitle(step)}'
                                : stepSubtitle(step),
                            style: context.text.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          CheckCircle(
            done: done,
            onTap: onToggle,
            label: done
                ? 'Mark ${step.title} not done'
                : 'Mark ${step.title} done',
          ),
        ],
      ),
    );
  }
}

class _Numbered extends StatelessWidget {
  const _Numbered({required this.n, required this.text, required this.last});
  final int n;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Text(
              n.toString().padLeft(2, '0'),
              style: context.text.titleSmall?.copyWith(
                color: c.inkFaint,
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
          Expanded(child: Text(text, style: context.text.bodyMedium)),
        ],
      ),
    );
  }
}

class _HabitRow extends StatelessWidget {
  const _HabitRow({required this.n, required this.habit, required this.last});
  final int n;
  final Habit habit;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Text(
              n.toString().padLeft(2, '0'),
              style: context.text.titleSmall?.copyWith(
                color: c.inkFaint,
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(habit.title, style: context.text.titleSmall),
                const SizedBox(height: 2),
                // One sentence: the why, not an essay.
                Text(
                  firstSentence(habit.detail),
                  style: context.text.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Amount, how to apply, how long it stays on, the wait before the next
/// layer and how to take it off, as a hairline table.
class _GuideTable extends StatelessWidget {
  const _GuideTable({required this.guide});
  final ApplicationGuide guide;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wait = guide.waitBeforeNext;
    final rows = [
      ('Amount', guide.amount),
      ('Apply', guide.technique),
      ('Stays on', guide.contact),
      if (wait != null)
        (
          'Then wait',
          wait.inMinutes >= 1
              ? '${wait.inMinutes} minute${wait.inMinutes == 1 ? '' : 's'} before the next step'
              : '${wait.inSeconds} seconds before the next step',
        ),
      if (guide.removal != null) ('Remove', guide.removal!),
    ];
    return Column(
      children: [
        for (final (i, (label, text)) in rows.indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: Space.sm + 2),
            decoration: BoxDecoration(
              border: i == rows.length - 1
                  ? null
                  : Border(bottom: BorderSide(color: c.line)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    label.toUpperCase(),
                    style: context.text.labelSmall?.copyWith(
                      color: c.inkMuted,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                Expanded(child: Text(text, style: context.text.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}

class _StepSheet extends StatelessWidget {
  const _StepSheet({required this.step});
  final RoutineStep step;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget block(String title, String body, {Color? color}) => Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(title, color: color),
          const SizedBox(height: 6),
          Text(body, style: context.text.bodyLarge),
        ],
      ),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        Space.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProductGlyph(category: step.category, size: 52),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow(step.category.label),
                    const SizedBox(height: 4),
                    Text(step.title, style: context.text.headlineSmall),
                  ],
                ),
              ),
            ],
          ),
          if (step.keyIngredients.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            Text(
              step.keyIngredients.join('  ·  '),
              style: context.text.bodyMedium?.copyWith(color: c.ink),
            ),
          ],
          if (step.days.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            _DayRow(days: step.days),
          ],
          const SizedBox(height: Space.lg),
          Divider(color: c.line),
          const SizedBox(height: Space.lg),
          // The why in one sentence; the how lives in the table below.
          block('Why', firstSentence(step.why)),
          const Eyebrow('How'),
          const SizedBox(height: 6),
          _GuideTable(guide: ApplicationGuide.forStep(step)),
          const SizedBox(height: Space.lg),
          if (step.caution != null)
            block('Careful', step.caution!, color: c.warn),
          if (step.matchedProduct != null)
            block('From your shelf', step.matchedProduct!.displayName)
          else ...[
            ShopLinkRow(
              query: ShopQuery.forStep(step.category, step.keyIngredients),
            ),
            const SizedBox(height: Space.md),
            ArrowPill(
              label: 'Add a product for this step',
              icon: Icons.add_rounded,
              dark: true,
              onTap: () {
                Navigator.pop(context);
                context.go('/shelf');
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.days});
  final Set<int> days;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      children: [
        for (var d = 1; d <= 7; d++)
          Padding(
            padding: const EdgeInsets.only(right: Space.sm),
            child: Text(
              labels[d - 1],
              style: context.text.titleSmall?.copyWith(
                color: days.contains(d) ? c.ink : c.inkFaint,
                fontWeight: days.contains(d)
                    ? FontWeight.w600
                    : FontWeight.w300,
              ),
            ),
          ),
      ],
    );
  }
}

/// Seven columns, one per night: the day letter, a dot on active nights,
/// and the name of tonight's step under today.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.steps});
  final List<RoutineStep> steps;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final today = clock.now().weekday;
    final tonight = steps.where((s) => s.days.contains(today)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var d = 1; d <= 7; d++)
              Expanded(
                child: Column(
                  children: [
                    Text(
                      labels[d - 1],
                      style: context.text.labelLarge?.copyWith(
                        color: d == today ? c.ink : c.inkMuted,
                        fontWeight: d == today ? FontWeight.w700 : null,
                      ),
                    ),
                    const SizedBox(height: Space.xs),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: steps.any((s) => s.days.contains(d))
                            ? (d == today ? c.ink : c.leaf)
                            : c.line,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.md),
        Text(
          tonight.isEmpty
              ? 'Tonight is a rest night.'
              : 'Tonight: ${tonight.map((s) => s.title).join(' + ')}',
          style: context.text.bodyMedium?.copyWith(color: c.ink),
        ),
      ],
    );
  }
}
