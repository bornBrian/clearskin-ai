import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/profile.dart';

class QuestionStep extends StatelessWidget {
  const QuestionStep({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        Space.lg,
      ),
      children: [
        Text(title, style: context.text.headlineLarge),
        if (subtitle != null) ...[
          const SizedBox(height: Space.xs),
          Text(subtitle!, style: context.text.bodyMedium),
        ],
        const SizedBox(height: Space.lg),
        child,
      ],
    );
  }
}

class SkinTonePicker extends StatelessWidget {
  const SkinTonePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final SkinTone? value;
  final ValueChanged<SkinTone?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        for (final t in SkinTone.values)
          Semantics(
            label: t.label,
            selected: value == t,
            button: true,
            child: GestureDetector(
              onTap: () => onChanged(value == t ? null : t),
              child: SizedBox(
                width: 96,
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: Motion.fast,
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Color(t.swatch),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: value == t ? c.primary : c.line,
                          width: value == t ? 3.5 : 1,
                        ),
                      ),
                      child: value == t
                          ? const Icon(Icons.check_rounded, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t.label,
                      style: context.text.labelMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class RemindersPicker extends StatelessWidget {
  const RemindersPicker({
    super.key,
    required this.enabled,
    required this.am,
    required this.pm,
    required this.onChanged,
  });

  final bool enabled;
  final ReminderTime am;
  final ReminderTime pm;
  final void Function(bool enabled, ReminderTime am, ReminderTime pm) onChanged;

  Future<ReminderTime?> _pick(BuildContext context, ReminderTime t) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: t.hour, minute: t.minute),
    );
    return picked == null ? null : ReminderTime(picked.hour, picked.minute);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget row(
      IconData icon,
      String label,
      ReminderTime t,
      ValueChanged<ReminderTime> set,
    ) => ListTile(
      enabled: enabled,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: c.primary),
      title: Text(label, style: context.text.titleMedium),
      trailing: Text(
        t.format(),
        style: context.text.titleMedium?.copyWith(color: c.primary),
      ),
      onTap: () async {
        final v = await _pick(context, t);
        if (v != null) set(v);
      },
    );

    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: enabled,
          title: Text('Routine reminders', style: context.text.titleMedium),
          onChanged: (v) => onChanged(v, am, pm),
        ),
        const Divider(),
        row(
          Icons.wb_sunny_rounded,
          'Morning',
          am,
          (v) => onChanged(enabled, v, pm),
        ),
        row(
          Icons.nightlight_round,
          'Evening',
          pm,
          (v) => onChanged(enabled, am, v),
        ),
      ],
    );
  }
}

class CityPicker extends ConsumerStatefulWidget {
  const CityPicker({super.key, required this.value, required this.onChanged});
  final Location? value;
  final ValueChanged<Location?> onChanged;

  @override
  ConsumerState<CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends ConsumerState<CityPicker> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<Location> _results = const [];
  bool _loading = false;
  String? _error;

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ref.read(weatherServiceProvider).searchCity(q);
      if (mounted) setState(() => _results = r);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Couldn\'t search right now. You can add this later.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final selected = widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selected != null)
          Card(
            child: ListTile(
              leading: Icon(Icons.place_rounded, color: c.primary),
              title: Text(selected.name),
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Clear',
                onPressed: () => widget.onChanged(null),
              ),
            ),
          )
        else ...[
          TextField(
            controller: _ctrl,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search your city',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(_error!, style: context.text.bodySmall),
            ),
          const SizedBox(height: Space.xs),
          for (final r in _results)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.place_outlined),
              title: Text(r.name),
              onTap: () {
                FocusScope.of(context).unfocus();
                widget.onChanged(r);
                _ctrl.clear();
                setState(() => _results = const []);
              },
            ),
        ],
      ],
    );
  }
}
