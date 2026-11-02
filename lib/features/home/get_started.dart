import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/repositories/repositories.dart';
import '../../services/telemetry.dart';

/// The two checklist facts that live in the KV store, not in the data.
final getStartedFlagsProvider = FutureProvider<({bool hidden, bool invited})>((
  ref,
) async {
  final kv = ref.watch(kvProvider);
  return (
    hidden: await kv.get(KvKeys.getStartedHidden) == '1',
    invited: await kv.get(KvKeys.inviteShared) == '1',
  );
});

class _Step {
  const _Step(
    this.id,
    this.title,
    this.subtitle,
    this.done,
    this.route, {
    this.tab = false,
  });
  final String id;
  final String title;
  final String subtitle;
  final bool done;
  final String route;

  /// Bottom-nav tabs are gone to; other screens are pushed.
  final bool tab;
}

/// The first-week tour: five things that show what ClearSkin does, each one
/// tap away. It ticks itself from real use and leaves once everything is
/// done, when hidden, or after the first [days]: past that, a checklist at
/// the top of Today is a nag, not a tour.
class GetStartedCard extends ConsumerWidget {
  const GetStartedCard({super.key});

  static const days = 14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(getStartedFlagsProvider).value;
    if (flags == null || flags.hidden) return const SizedBox.shrink();
    final since = ref.watch(profileProvider).value?.createdAt;
    if (since != null && clock.now().difference(since).inDays >= days) {
      return const SizedBox.shrink();
    }
    final steps = [
      _Step(
        'scan',
        'Take your first scan',
        'Your score, and a routine built from it',
        ref.watch(latestScanProvider) != null,
        '/scan',
      ),
      _Step(
        'routine',
        'Finish a routine',
        'Tick every step once to start your streak',
        ref.watch(completedDaysProvider).isNotEmpty,
        '/routine',
        tab: true,
      ),
      _Step(
        'checkin',
        'Do a daily check-in',
        'Sleep, stress and food: it finds what breaks you out',
        (ref.watch(checkInsProvider).value ?? const []).isNotEmpty,
        '/checkin',
      ),
      _Step(
        'product',
        'Check a product you own',
        'Scan its barcode to see if it suits your skin',
        (ref.watch(productsProvider).value ?? const []).isNotEmpty,
        '/shelf',
        tab: true,
      ),
      _Step(
        'invite',
        'Invite a friend',
        'You both get a free scan',
        flags.invited,
        '/invite',
      ),
    ];
    final done = steps.where((s) => s.done).length;
    if (done == steps.length) return const SizedBox.shrink();
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Eyebrow('Get started'),
              const Spacer(),
              Text('$done of ${steps.length}', style: context.text.labelMedium),
            ],
          ),
          const SizedBox(height: Space.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: done / steps.length),
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
          const SizedBox(height: Space.sm),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: Space.md + 2),
            child: Column(
              children: [
                for (var i = 0; i < steps.length; i++)
                  LineItem(
                    title: steps[i].title,
                    subtitle: steps[i].done ? 'Done' : steps[i].subtitle,
                    divider: i < steps.length - 1,
                    leading: _Tick(done: steps[i].done),
                    trailing: steps[i].done
                        ? null
                        : Icon(Icons.chevron_right_rounded, color: c.inkFaint),
                    onTap: steps[i].done
                        ? null
                        : () {
                            ref.read(telemetryProvider).track(
                              Ev.getStartedTapped,
                              {'step': steps[i].id, 'done': done},
                            );
                            steps[i].tab
                                ? context.go(steps[i].route)
                                : context.push(steps[i].route);
                          },
                  ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: c.inkMuted),
              onPressed: () async {
                await ref.read(kvProvider).set(KvKeys.getStartedHidden, '1');
                ref.invalidate(getStartedFlagsProvider);
              },
              child: const Text('Hide'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  const _Tick({required this.done});
  final bool done;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedContainer(
      duration: Motion.normal,
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? c.ink : null,
        border: done ? null : Border.all(color: c.inkFaint, width: 1.5),
      ),
      child: done
          ? Icon(Icons.check_rounded, size: 15, color: c.surface)
          : null,
    );
  }
}
