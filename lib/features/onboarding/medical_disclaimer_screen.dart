import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/env.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';

/// Required, full-screen acknowledgement before anything else in the app:
/// ClearSkin is cosmetic guidance, not medical diagnosis or treatment. No
/// close button, no back gesture; the only way on is to accept.
class MedicalDisclaimerScreen extends ConsumerStatefulWidget {
  const MedicalDisclaimerScreen({super.key});

  @override
  ConsumerState<MedicalDisclaimerScreen> createState() =>
      _MedicalDisclaimerScreenState();
}

class _MedicalDisclaimerScreenState
    extends ConsumerState<MedicalDisclaimerScreen> {
  bool _understood = false;
  bool _busy = false;

  static const _points = [
    (
      'Not a diagnosis',
      'Cosmetic care only. No diagnosis, treatment or prescriptions.',
    ),
    ('Not a doctor', 'Your dermatologist\'s advice always comes first.'),
    (
      'When to get help',
      'Changing moles, painful acne, spreading rashes or infection: see a professional. In an emergency, call your local number.',
    ),
  ];

  Future<void> _accept() async {
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    await ref.read(disclaimerProvider.notifier).accept();
  }

  @override
  Widget build(BuildContext context) {
    const cream = BrandColors.cream;
    final dim = cream.withValues(alpha: 0.65);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: BrandColors.charcoal,
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      Space.xl,
                      Space.gutter,
                      Space.lg,
                    ),
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: BrandMark(size: 48, color: cream),
                      ),
                      const SizedBox(height: Space.xl),
                      Eyebrow('Before you start', color: dim),
                      const SizedBox(height: Space.sm),
                      Text(
                        'Skin guidance,\nnot medical advice.',
                        style: context.text.displaySmall?.copyWith(
                          color: cream,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: Space.xl),
                      for (final (i, (title, body)) in _points.indexed)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: Space.md,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: cream.withValues(alpha: 0.14),
                              ),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 36,
                                child: Text(
                                  '0${i + 1}',
                                  style: context.text.labelLarge?.copyWith(
                                    color: dim,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: context.text.titleMedium?.copyWith(
                                        color: cream,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      body,
                                      style: context.text.bodyMedium?.copyWith(
                                        color: dim,
                                        height: 1.45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: dim,
                          padding: EdgeInsets.zero,
                          alignment: Alignment.centerLeft,
                        ),
                        onPressed: () => launchUrl(Uri.parse(Env.termsUrl)),
                        child: const Text('Read the full terms'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.gutter,
                    0,
                    Space.gutter,
                    Space.md,
                  ),
                  child: Column(
                    children: [
                      Semantics(
                        checked: _understood,
                        child: InkWell(
                          onTap: () =>
                              setState(() => _understood = !_understood),
                          borderRadius: BorderRadius.circular(Radii.sm),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: Space.sm,
                            ),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: _understood,
                                  onChanged: (v) =>
                                      setState(() => _understood = v ?? false),
                                  side: BorderSide(color: dim, width: 1.5),
                                  activeColor: cream,
                                  checkColor: BrandColors.charcoal,
                                ),
                                Expanded(
                                  child: Text(
                                    'I understand this isn\'t medical advice.',
                                    style: context.text.bodyMedium?.copyWith(
                                      color: cream,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: cream,
                            foregroundColor: BrandColors.charcoal,
                            disabledBackgroundColor: cream.withValues(
                              alpha: 0.25,
                            ),
                          ),
                          onPressed: _understood && !_busy ? _accept : null,
                          child: const Text('I understand, continue'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
