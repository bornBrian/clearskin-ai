import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/guidance/hydration.dart';

/// One tick per glass of the day's target, darker as they're drunk: the
/// brand's tick motif, not a fill bar.
class WaterTicks extends StatelessWidget {
  const WaterTicks({super.key, required this.done, required this.goal});
  final int done;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < goal; i++)
          AnimatedContainer(
            duration: Motion.fast,
            width: 3,
            height: i < done ? 30 : 22,
            decoration: BoxDecoration(
              color: i < done ? c.ink : c.inkFaint.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}

/// Water on Today: glasses so far against the day's target, one tap to add.
class WaterCard extends ConsumerWidget {
  const WaterCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final target = ref.watch(hydrationTargetProvider);
    if (target == null) return const SizedBox.shrink();
    final done = ref.watch(waterTodayProvider).value ?? 0;
    final goal = target.glasses;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/water'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Eyebrow('Water'),
              const Spacer(),
              Text(
                done >= goal ? 'Done for today' : '$done of $goal glasses',
                style: context.text.labelMedium,
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          WaterTicks(done: done, goal: goal),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${(target.ml / 1000).toStringAsFixed(1)} L for you today',
                  style: context.text.bodySmall?.copyWith(color: c.inkMuted),
                ),
              ),
              TextButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  ref.read(waterTodayProvider.notifier).add(1);
                },
                child: const Text('Add a glass'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The water target worked out from the person's body, exercise and today's
/// weather, with each reason shown, and today's glasses.
class WaterScreen extends ConsumerStatefulWidget {
  const WaterScreen({super.key});

  @override
  ConsumerState<WaterScreen> createState() => _WaterScreenState();
}

class _WaterScreenState extends ConsumerState<WaterScreen> {
  final _weight = TextEditingController();
  final _height = TextEditingController();
  final _active = TextEditingController();
  bool _filled = false;

  @override
  void dispose() {
    _weight.dispose();
    _height.dispose();
    _active.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final w = double.tryParse(_weight.text.replaceAll(',', '.'));
    final h = double.tryParse(_height.text.replaceAll(',', '.'));
    final a = int.tryParse(_active.text) ?? 0;
    await ref
        .read(hydrationSettingsProvider.notifier)
        .save(
          HydrationSettings(
            weightKg: w != null && w >= 25 && w <= 300 ? w : null,
            heightCm: h != null && h >= 100 && h <= 250 ? h : null,
            activeMinutes: a.clamp(0, 600),
          ),
        );
    if (mounted) showSnack(context, 'Saved. Your target is updated.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final settings = ref.watch(hydrationSettingsProvider).value;
    if (settings != null && !_filled) {
      _filled = true;
      String fmt(double? v) => v == null ? '' : v.round().toString();
      _weight.text = fmt(settings.weightKg);
      _height.text = fmt(settings.heightCm);
      _active.text = settings.activeMinutes == 0
          ? ''
          : '${settings.activeMinutes}';
    }
    final target = ref.watch(hydrationTargetProvider);
    final done = ref.watch(waterTodayProvider).value ?? 0;

    Widget field(TextEditingController ctl, String label, String unit) =>
        Expanded(
          child: TextField(
            controller: ctl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: label, suffixText: unit),
          ),
        );

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
              Text('Water', style: context.text.displaySmall),
              const SizedBox(height: Space.xl),
              if (target != null) ...[
                const Eyebrow('Your target today'),
                const SizedBox(height: Space.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      (target.ml / 1000).toStringAsFixed(1),
                      style: TextStyle(
                        fontFamily: kFontFamily,
                        fontSize: 72,
                        height: 1,
                        letterSpacing: -2.5,
                        fontWeight: FontWeight.w200,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(width: Space.xs),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'litres · ${target.glasses} glasses',
                        style: context.text.titleMedium?.copyWith(
                          color: c.inkMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                for (final r in target.reasons)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      r,
                      style: context.text.bodySmall?.copyWith(
                        color: c.inkMuted,
                      ),
                    ),
                  ),
                const SizedBox(height: Space.xl),
                Row(
                  children: [
                    const Eyebrow('Today'),
                    const Spacer(),
                    Text(
                      '$done of ${target.glasses}',
                      style: context.text.labelMedium,
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                WaterTicks(done: done, goal: target.glasses),
                const SizedBox(height: Space.sm),
                Row(
                  children: [
                    TextButton(
                      onPressed: done == 0
                          ? null
                          : () => ref.read(waterTodayProvider.notifier).add(-1),
                      child: const Text('Remove one'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        ref.read(waterTodayProvider.notifier).add(1);
                      },
                      child: const Text('Add a glass'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: Space.xl),
              const Eyebrow('Make it yours'),
              const SizedBox(height: Space.sm),
              Row(
                children: [
                  field(_weight, 'Weight', 'kg'),
                  const SizedBox(width: Space.md),
                  field(_height, 'Height', 'cm'),
                ],
              ),
              const SizedBox(height: Space.md),
              Row(children: [field(_active, 'Exercise on a usual day', 'min')]),
              const SizedBox(height: Space.lg),
              ArrowPill(label: 'Save', dark: true, onTap: _save),
              const SizedBox(height: Space.lg),
              Text(
                'About 33 ml per kg a day, most of it from drinks, plus more '
                'for exercise, heat and pregnancy. Height adjusts the number '
                'for larger bodies. Stays on this phone.',
                style: context.text.bodySmall?.copyWith(color: c.inkFaint),
              ),
              const SizedBox(height: Space.md),
              LineItem(
                title: 'Water and your skin',
                subtitle: 'What water does and doesn\'t do',
                trailing: Icon(Icons.chevron_right_rounded, color: c.inkFaint),
                divider: false,
                onTap: () => context.push('/guide/water'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
