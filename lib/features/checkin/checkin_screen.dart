import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/check_in.dart';
import '../../data/models/profile.dart';
import '../../services/telemetry.dart';

/// Ten-second daily log that powers trigger insights.
class CheckInScreen extends ConsumerStatefulWidget {
  const CheckInScreen({super.key});

  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen> {
  int _feel = 3;
  int _breakouts = 0;
  double _sleep = 7;
  int _stress = 2;
  int _water = 6;
  final Set<LifeTag> _tags = {};
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(todayCheckInProvider);
    if (existing != null) {
      _feel = existing.skinFeel;
      _breakouts = existing.breakouts;
      _sleep = existing.sleepHours;
      _stress = existing.stress;
      _water = existing.waterGlasses;
      _tags.addAll(existing.tags);
      _note.text = existing.note;
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref
        .read(checkInsProvider.notifier)
        .save(
          CheckIn(
            day: Dates.today(),
            skinFeel: _feel,
            breakouts: _breakouts,
            sleepHours: _sleep,
            stress: _stress,
            waterGlasses: _water,
            tags: _tags,
            note: _note.text.trim(),
          ),
        );
    ref.read(telemetryProvider).track(Ev.checkInSaved, {'tags': _tags.length});
    HapticFeedback.mediumImpact();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final profile = ref.watch(profileProvider).value;
    final tags = LifeTag.values.where((t) {
      if (t == LifeTag.period) {
        return profile != null &&
            profile.gender != Gender.man &&
            !profile.pregnantOrNursing;
      }
      if (t == LifeTag.shaved) return profile?.shaves ?? false;
      return true;
    });

    const feelEmoji = ['😣', '😕', '🙂', '😊', '🤩'];
    const feelLabel = ['Rough', 'Meh', 'OK', 'Good', 'Great'];
    const breakoutLabel = ['None', '1–2', 'Several', 'Many'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily check-in'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
          tooltip: 'Close',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.xs,
          Space.gutter,
          Space.xl,
        ),
        children: [
          Text('How does your skin feel?', style: context.text.titleLarge),
          const SizedBox(height: Space.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 5; i++)
                Semantics(
                  label: feelLabel[i],
                  selected: _feel == i + 1,
                  button: true,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _feel = i + 1);
                    },
                    child: AnimatedContainer(
                      duration: Motion.fast,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _feel == i + 1
                            ? c.primarySoft
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(Radii.md),
                        border: Border.all(
                          color: _feel == i + 1
                              ? c.primary
                              : Colors.transparent,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            feelEmoji[i],
                            style: const TextStyle(fontSize: 30),
                          ),
                          Text(feelLabel[i], style: context.text.labelSmall),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.lg),
          Text('New breakouts today', style: context.text.titleLarge),
          const SizedBox(height: Space.sm),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              for (var i = 0; i < 4; i++)
                ButtonSegment(value: i, label: Text(breakoutLabel[i])),
            ],
            selected: {_breakouts},
            onSelectionChanged: (s) => setState(() => _breakouts = s.first),
          ),
          const SizedBox(height: Space.lg),
          _SliderRow(
            label: 'Sleep last night',
            value: _sleep,
            min: 3,
            max: 11,
            divisions: 16,
            display: '${_sleep.toStringAsFixed(_sleep % 1 == 0 ? 0 : 1)} h',
            onChanged: (v) => setState(() => _sleep = v),
          ),
          _SliderRow(
            label: 'Stress',
            value: _stress.toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            display: const [
              '',
              'Calm',
              'Low',
              'Some',
              'High',
              'Very high',
            ][_stress],
            onChanged: (v) => setState(() => _stress = v.round()),
          ),
          _SliderRow(
            label: 'Water',
            value: _water.toDouble(),
            min: 0,
            max: 12,
            divisions: 12,
            display: '$_water glasses',
            onChanged: (v) => setState(() => _water = v.round()),
          ),
          const SizedBox(height: Space.md),
          Text('Anything notable today?', style: context.text.titleLarge),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final t in tags)
                FilterChip(
                  label: Text('${t.emoji} ${t.label}'),
                  selected: _tags.contains(t),
                  showCheckmark: false,
                  onSelected: (v) =>
                      setState(() => v ? _tags.add(t) : _tags.remove(t)),
                ),
            ],
          ),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _note,
            maxLines: 3,
            maxLength: 300,
            decoration: const InputDecoration(hintText: 'Notes (optional)'),
          ),
          const SizedBox(height: Space.md),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save check-in'),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: context.text.titleMedium)),
            Pill(display),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          label: display,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
