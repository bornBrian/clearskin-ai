import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/profile.dart';

/// Every reminder and alert in one calm list. Changes save and reschedule
/// immediately.
class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  static const _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider).value;
    if (p == null) return const Scaffold(body: SizedBox.expand());
    final r = p.reminders;

    Future<void> save(UserProfile next, {bool turnedOn = false}) async {
      if (turnedOn) {
        unawaited(ref.read(notificationServiceProvider).requestPermission());
      }
      await ref.read(profileProvider.notifier).save(next);
    }

    Future<ReminderTime?> pick(ReminderTime t) async {
      final v = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: t.hour, minute: t.minute),
      );
      return v == null ? null : ReminderTime(v.hour, v.minute);
    }

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
              Text('Reminders', style: context.text.displaySmall),
              const SizedBox(height: Space.xl),
              const Eyebrow('Routine'),
              _Row(
                title: 'Morning',
                time: p.amReminder,
                enabled: p.remindersEnabled,
                onToggle: (v) =>
                    save(p.copyWith(remindersEnabled: v), turnedOn: v),
                onTime: () async {
                  final t = await pick(p.amReminder);
                  if (t != null) await save(p.copyWith(amReminder: t));
                },
              ),
              _Row(
                title: 'Evening',
                subtitle: 'Names tonight\'s step',
                time: p.pmReminder,
                enabled: p.remindersEnabled,
                onToggle: (v) =>
                    save(p.copyWith(remindersEnabled: v), turnedOn: v),
                onTime: () async {
                  final t = await pick(p.pmReminder);
                  if (t != null) await save(p.copyWith(pmReminder: t));
                },
              ),
              const SizedBox(height: Space.xl),
              const Eyebrow('Tracking'),
              _Row(
                title: 'Daily check-in',
                time: r.checkInTime,
                enabled: r.checkIn,
                onToggle: (v) => save(
                  p.copyWith(reminders: r.copyWith(checkIn: v)),
                  turnedOn: v,
                ),
                onTime: () async {
                  final t = await pick(r.checkInTime);
                  if (t != null) {
                    await save(
                      p.copyWith(reminders: r.copyWith(checkInTime: t)),
                    );
                  }
                },
              ),
              _Row(
                title: 'Weekly scan',
                time: r.scanTime,
                enabled: r.weeklyScan,
                divider: false,
                onToggle: (v) => save(
                  p.copyWith(reminders: r.copyWith(weeklyScan: v)),
                  turnedOn: v,
                ),
                onTime: () async {
                  final t = await pick(r.scanTime);
                  if (t != null) {
                    await save(p.copyWith(reminders: r.copyWith(scanTime: t)));
                  }
                },
              ),
              if (r.weeklyScan)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var d = 1; d <= 7; d++)
                        _DayDot(
                          label: _days[d - 1],
                          selected: r.scanWeekday == d,
                          onTap: () => save(
                            p.copyWith(reminders: r.copyWith(scanWeekday: d)),
                          ),
                        ),
                    ],
                  ),
                ),
              Divider(color: context.colors.line),
              const SizedBox(height: Space.xl),
              const Eyebrow('Alerts'),
              _Row(
                title: 'Smart alerts',
                subtitle: 'Streaks, high UV, gentle come-backs',
                enabled: r.smart,
                divider: false,
                onToggle: (v) => save(
                  p.copyWith(reminders: r.copyWith(smart: v)),
                  turnedOn: v,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.enabled,
    required this.onToggle,
    this.subtitle,
    this.time,
    this.onTime,
    this.divider = true,
  });

  final String title;
  final String? subtitle;
  final ReminderTime? time;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onTime;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LineItem(
      title: title,
      subtitle: subtitle,
      divider: divider,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (time != null)
            TextButton(
              onPressed: enabled ? onTime : null,
              style: TextButton.styleFrom(
                foregroundColor: c.ink,
                textStyle: context.text.titleSmall,
              ),
              child: Text(time!.format()),
            ),
          Switch(value: enabled, onChanged: onToggle),
        ],
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // A letter, bold and dark when chosen: no circles.
        child: SizedBox(
          width: 38,
          height: 38,
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: Motion.fast,
              style: context.text.titleMedium!.copyWith(
                color: selected ? c.ink : c.inkFaint,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
              child: Text(label),
            ),
          ),
        ),
      ),
    );
  }
}
