import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/profile.dart';
import '../onboarding/onboarding_widgets.dart';

/// Edits the skin profile. Every change immediately regenerates the routine.
class EditProfileScreen extends ConsumerWidget {
  const EditProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    Future<void> save(UserProfile p) =>
        ref.read(profileProvider.notifier).save(p);

    Widget header(String t) => Padding(
      padding: const EdgeInsets.only(top: Space.lg, bottom: Space.xs),
      child: Text(t, style: context.text.titleLarge),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Skin profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          Space.xxl,
        ),
        children: [
          header('Name'),
          TextFormField(
            initialValue: profile.name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'First name'),
            onFieldSubmitted: (v) => save(profile.copyWith(name: v.trim())),
          ),
          header('Skin type'),
          for (final t in SkinType.values)
            OptionTile(
              title: t.label,
              subtitle: t.hint,
              selected: profile.skinType == t,
              onTap: () => save(profile.copyWith(skinType: t)),
            ),
          header('Sensitivity'),
          for (final s in Sensitivity.values)
            OptionTile(
              title: s.label,
              selected: profile.sensitivity == s,
              onTap: () => save(profile.copyWith(sensitivity: s)),
            ),
          header('Concerns'),
          for (final cn in Concern.values)
            OptionTile(
              title: cn.label,
              multi: true,
              selected: profile.concerns.contains(cn),
              onTap: () {
                final next = {...profile.concerns};
                next.contains(cn) ? next.remove(cn) : next.add(cn);
                if (next.isNotEmpty) save(profile.copyWith(concerns: next));
              },
            ),
          header('I react to'),
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Text(
              'Anything that has made your skin sting, itch or break out. Product checks flag it, and your routine leaves it out.',
              style: context.text.bodyMedium,
            ),
          ),
          for (final r in Reaction.values)
            OptionTile(
              title: r.label,
              multi: true,
              selected: profile.reactsTo.contains(r),
              onTap: () {
                final next = {...profile.reactsTo};
                next.contains(r) ? next.remove(r) : next.add(r);
                save(profile.copyWith(reactsTo: next));
              },
            ),
          header('Routine style'),
          for (final r in RoutineComplexity.values)
            OptionTile(
              title: r.label,
              subtitle: r.hint,
              selected: profile.complexity == r,
              onTap: () => save(profile.copyWith(complexity: r)),
            ),
          header('Skin tone'),
          SkinTonePicker(
            value: profile.skinTone,
            onChanged: (t) => save(
              t == null
                  ? profile.copyWith(clearSkinTone: true)
                  : profile.copyWith(skinTone: t),
            ),
          ),
          header('Life stage'),
          if (profile.gender != Gender.man)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Pregnant, trying or breastfeeding'),
              subtitle: const Text(
                'Removes retinoids and other cautioned actives',
              ),
              value: profile.pregnantOrNursing,
              onChanged: (v) => save(profile.copyWith(pregnantOrNursing: v)),
            ),
          if (profile.gender != Gender.woman)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('I shave my face'),
              value: profile.shaves,
              onChanged: (v) => save(profile.copyWith(shaves: v)),
            ),
          header('City (skin forecast)'),
          CityPicker(
            value: profile.location,
            onChanged: (l) => save(
              l == null
                  ? profile.copyWith(clearLocation: true)
                  : profile.copyWith(location: l),
            ),
          ),
          const SizedBox(height: Space.lg),
          const Disclaimer(
            text: 'Your profile is stored only on this phone. Name and city are never sent to our AI.',
          ),
        ],
      ),
    );
  }
}
