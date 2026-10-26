import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await ref.read(appLockServiceProvider).authenticate();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) ref.read(lockProvider.notifier).unlock();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.background,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 48, color: c.primary),
                const SizedBox(height: Space.md),
                Text('ClearSkin is locked', style: context.text.headlineSmall),
                const SizedBox(height: Space.xs),
                Text(
                  'Your skin journal is private.',
                  style: context.text.bodyMedium,
                ),
                const SizedBox(height: Space.lg),
                FilledButton.icon(
                  onPressed: _busy ? null : _unlock,
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: const Text('Unlock'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
