import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/env.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/repositories/repositories.dart';
import '../../services/backend_api.dart';

final _appLockEnabledProvider = FutureProvider.autoDispose<bool>(
  (ref) async => await ref.read(kvProvider).get(KvKeys.appLock) == '1',
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final premium = ref.watch(premiumProvider);
    final lock = ref.watch(_appLockEnabledProvider).value ?? false;
    final c = context.colors;

    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        Space.xs,
      ),
      child: Text(title.toUpperCase(), style: context.text.labelSmall),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: AppCard(
              onTap: premium
                  ? () => launchUrl(
                      Uri.parse(
                        'https://play.google.com/store/account/subscriptions',
                      ),
                      mode: LaunchMode.externalApplication,
                    )
                  : () => context.push('/paywall?source=settings'),
              child: Row(
                children: [
                  Icon(
                    premium
                        ? Icons.workspace_premium_rounded
                        : Icons.auto_awesome_rounded,
                    color: c.primary,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          premium ? 'ClearSkin Premium' : 'Upgrade to Premium',
                          style: context.text.titleMedium,
                        ),
                        Text(
                          premium
                              ? 'Manage or cancel in Google Play'
                              : 'Unlimited scans, progress, insights & coach',
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
          section('Your skin'),
          ListTile(
            leading: const Icon(Icons.face_retouching_natural_rounded),
            title: const Text('Skin profile'),
            subtitle: Text(
              profile == null
                  ? ''
                  : '${profile.skinType.label} · ${profile.concerns.length} concerns · ${profile.complexity.label}',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/settings/profile'),
          ),
          section('Account'),
          Builder(
            builder: (context) {
              final account = ref.watch(accountProvider).value;
              if (account == null) {
                return ListTile(
                  leading: const Icon(Icons.person_outline_rounded),
                  title: const Text('Sign in'),
                  subtitle: const Text('Keep Premium on any phone'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/auth?mode=signin'),
                );
              }
              return ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: Text(account.name ?? account.email ?? 'Signed in'),
                subtitle: Text(
                  account.provider == 'google'
                      ? 'Google · ${account.email ?? ''}'
                      : account.email ?? '',
                ),
                trailing: TextButton(
                  onPressed: () async {
                    final ok = await confirm(
                      context,
                      title: 'Sign out?',
                      body: 'Your scans and plan stay on this phone. Sign back in to see them.',
                      confirmLabel: 'Sign out',
                    );
                    if (ok) await ref.read(accountProvider.notifier).signOut();
                  },
                  child: const Text('Sign out'),
                ),
              );
            },
          ),
          section('Reminders'),
          ListTile(
            leading: const Icon(Icons.notifications_none_rounded),
            title: const Text('Reminders & alerts'),
            subtitle: Text(
              profile == null || !profile.remindersEnabled
                  ? 'Off'
                  : '${profile.amReminder.format()} · ${profile.pmReminder.format()}',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/settings/reminders'),
          ),
          section('Privacy & security'),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline_rounded),
            title: const Text('App lock'),
            subtitle: const Text('Require fingerprint, face or PIN to open'),
            value: lock,
            onChanged: (v) async {
              final svc = ref.read(appLockServiceProvider);
              if (v && !await svc.available()) {
                if (context.mounted) {
                  showSnack(
                    context,
                    'Set up a screen lock on your phone first.',
                  );
                }
                return;
              }
              if (v && !await svc.authenticate()) return;
              await ref.read(kvProvider).set(KvKeys.appLock, v ? '1' : '0');
              ref.invalidate(_appLockEnabledProvider);
            },
          ),
          StatefulBuilder(
            builder: (context, setLocal) {
              final telemetry = ref.read(telemetryProvider);
              return SwitchListTile(
                secondary: const Icon(Icons.insights_outlined),
                title: const Text('Share anonymous usage data'),
                subtitle: const Text(
                  'Helps us fix crashes and improve ClearSkin. Never includes photos, names or skin details.',
                ),
                value: !telemetry.optedOut,
                onChanged: (v) async {
                  await telemetry.setOptOut(!v);
                  setLocal(() {});
                },
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.download_rounded),
            title: const Text('Export my data'),
            subtitle: const Text(
              'Profile, scans, check-ins and products as JSON',
            ),
            onTap: () => ref.read(exportServiceProvider).exportAll(),
          ),
          ListTile(
            leading: Icon(Icons.delete_forever_rounded, color: c.bad),
            title: Text(
              'Delete account & all data',
              style: TextStyle(color: c.bad),
            ),
            subtitle: const Text(
              'Permanently erases everything, on this phone and our servers',
            ),
            onTap: () => _deleteEverything(context, ref),
          ),
          section('Support'),
          if (!premium)
            ListTile(
              leading: const Icon(Icons.restore_rounded),
              title: const Text('Restore purchases'),
              onTap: () async {
                final ok = await ref.read(purchasesServiceProvider).restore();
                if (context.mounted) {
                  showSnack(
                    context,
                    ok ? 'Premium restored.' : 'No active subscription found.',
                  );
                }
              },
            ),
          ListTile(
            leading: const Icon(Icons.mail_outline_rounded),
            title: const Text('Contact support'),
            onTap: () => launchUrl(
              Uri(
                scheme: 'mailto',
                path: Env.supportEmail,
                queryParameters: {'subject': 'ClearSkin AI support'},
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy policy'),
            onTap: () => launchUrl(Uri.parse(Env.privacyPolicyUrl)),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms of use'),
            onTap: () => launchUrl(Uri.parse(Env.termsUrl)),
          ),
          if (kDebugMode) ...[
            section('Developer'),
            SwitchListTile(
              title: const Text('Dev Premium'),
              subtitle: Text(
                Env.demoMode
                    ? 'Demo mode: backend not configured'
                    : 'Backend connected',
              ),
              value: premium,
              onChanged: (v) async {
                ref.read(purchasesServiceProvider).setDevPremium(v);
                await ref
                    .read(kvProvider)
                    .set(KvKeys.devPremium, v ? '1' : '0');
              },
            ),
          ],
          const Padding(
            padding: EdgeInsets.all(Space.gutter),
            child: Disclaimer(),
          ),
          Center(
            child: Text(
              'ClearSkin AI · v1.0.0',
              style: context.text.labelSmall,
            ),
          ),
          const SizedBox(height: Space.xl),
        ],
      ),
    );
  }

  Future<void> _deleteEverything(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Delete everything?',
      body:
          'This permanently deletes your profile, scans, photos, check-ins, products and chat — on this phone and on our servers. '
          'An active subscription is NOT cancelled automatically: cancel it in Google Play.',
      confirmLabel: 'Delete everything',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(backendApiProvider).deleteAccount();
    } on ApiException catch (e) {
      if (!context.mounted) return;
      final proceed = await confirm(
        context,
        title: 'Couldn\'t reach our servers',
        body:
            '${e.message}\n\nDelete the data on this phone anyway? You can email ${Env.supportEmail} to remove server records.',
        confirmLabel: 'Delete local data',
        destructive: true,
      );
      if (!proceed) return;
    }
    await wipeAllLocalData(ref);
    if (context.mounted) context.go('/onboarding');
  }
}
