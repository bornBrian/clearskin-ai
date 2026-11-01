import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/profile.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/journey/journey_engine.dart';
import '../../services/telemetry.dart';
import 'onboarding_widgets.dart';

/// Personalisation quiz. Every answer changes the routine engine's output,
/// and the flow builds investment before the paywall (a proven pattern for
/// subscription apps) without ever blocking safety information.
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key, this.startAt = 0});

  /// Step to open on, for screenshots of a single question.
  final int startAt;

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

enum _Step {
  welcome,
  journey,
  name,
  gender,
  age,
  skinType,
  sensitivity,
  concerns,
  insight,
  goals,
  tone,
  pregnancy,
  shaving,
  complexity,
  reminders,
  city,
  building,
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  // Created on first use, after initState has picked the starting step.
  late final _page = PageController(
    initialPage: _index > _firstQuestion ? _index - _firstQuestion : 0,
  );
  final _nameField = TextEditingController();
  int _index = 0;

  String _name = '';
  Gender? _gender;
  AgeRange? _age;
  bool _underAge = false;
  SkinType? _skinType;
  Sensitivity? _sensitivity;
  final Set<Concern> _concerns = {};
  final Set<Goal> _goals = {};
  SkinTone? _tone;
  bool? _pregnant;
  bool? _shaves;
  RoutineComplexity? _complexity;
  ReminderTime _am = const ReminderTime(7, 30);
  ReminderTime _pm = const ReminderTime(21, 30);
  bool _reminders = true;
  Location? _location;

  List<_Step> get _steps => [
    _Step.welcome,
    _Step.journey,
    _Step.name,
    _Step.gender,
    _Step.age,
    _Step.skinType,
    _Step.sensitivity,
    _Step.concerns,
    _Step.insight,
    _Step.goals,
    _Step.tone,
    if (_gender != Gender.man) _Step.pregnancy,
    if (_gender != Gender.woman) _Step.shaving,
    _Step.complexity,
    _Step.reminders,
    _Step.city,
    _Step.building,
  ];

  _Step get _current => _steps[_index];

  @override
  void initState() {
    super.initState();
    ref.read(telemetryProvider).track(Ev.onboardingStarted);
    // Already signed in (say the app closed during setup): never the
    // welcome or sign-in screen again, straight on with the setup.
    if (ref.read(accountProvider).value != null) {
      _index = 1;
      unawaited(_restoreDraft());
    }
    if (widget.startAt > _index) _index = widget.startAt;
  }

  /// Picks up where setup stopped if the app closed part-way through.
  Future<void> _restoreDraft() async {
    final j = await ref.read(kvProvider).getJson(KvKeys.onboardingDraft);
    if (j == null || !mounted) return;
    T? pick<T extends Enum>(List<T> values, Object? name) =>
        values.where((v) => v.name == name).firstOrNull;
    List<T> picks<T extends Enum>(List<T> values, Object? names) => [
      for (final n in (names as List?) ?? const []) ?pick(values, n),
    ];
    setState(() {
      _name = j['name'] as String? ?? '';
      _nameField.text = _name;
      _gender = pick(Gender.values, j['gender']);
      _age = pick(AgeRange.values, j['age']);
      _skinType = pick(SkinType.values, j['skinType']);
      _sensitivity = pick(Sensitivity.values, j['sensitivity']);
      _concerns
        ..clear()
        ..addAll(picks(Concern.values, j['concerns']));
      _goals
        ..clear()
        ..addAll(picks(Goal.values, j['goals']));
      _tone = pick(SkinTone.values, j['tone']);
      _pregnant = j['pregnant'] as bool?;
      _shaves = j['shaves'] as bool?;
      _complexity = pick(RoutineComplexity.values, j['complexity']);
      _reminders = j['reminders'] as bool? ?? true;
      // Never straight into "building": the last question is shown again.
      final saved = (j['index'] as int? ?? _index).clamp(
        _index,
        _steps.length - 2,
      );
      _index = saved;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _page.hasClients && _index >= _firstQuestion) {
        _page.jumpToPage(_index - _firstQuestion);
      }
    });
  }

  void _saveDraft() {
    if (_index < _firstQuestion) return;
    unawaited(
      ref.read(kvProvider).setJson(KvKeys.onboardingDraft, {
        'index': _index,
        'name': _name,
        'gender': _gender?.name,
        'age': _age?.name,
        'skinType': _skinType?.name,
        'sensitivity': _sensitivity?.name,
        'concerns': [for (final c in _concerns) c.name],
        'goals': [for (final g in _goals) g.name],
        'tone': _tone?.name,
        'pregnant': _pregnant,
        'shaves': _shaves,
        'complexity': _complexity?.name,
        'reminders': _reminders,
      }),
    );
  }

  /// Index of the first quiz question (after welcome and the journey).
  static const _firstQuestion = 2;

  bool get _canContinue => switch (_current) {
    _Step.welcome ||
    _Step.journey ||
    _Step.name ||
    _Step.tone ||
    _Step.city ||
    _Step.insight => true,
    _Step.gender => _gender != null,
    _Step.age => _age != null && !_underAge,
    _Step.skinType => _skinType != null,
    _Step.sensitivity => _sensitivity != null,
    _Step.concerns => _concerns.isNotEmpty,
    _Step.goals => _goals.isNotEmpty,
    _Step.pregnancy => _pregnant != null,
    _Step.shaving => _shaves != null,
    _Step.complexity => _complexity != null,
    _Step.reminders => true,
    _Step.building => false,
  };

  void _next() {
    FocusScope.of(context).unfocus();
    if (_index >= _steps.length - 1) return;
    if (_current == _Step.journey) {
      unawaited(_accountFirst());
      return;
    }
    if (_current == _Step.reminders && _reminders) {
      unawaited(ref.read(notificationServiceProvider).requestPermission());
    }
    setState(() => _index++);
    _saveDraft();
    if (_index > _firstQuestion && _page.hasClients) {
      _page.animateToPage(
        _index - _firstQuestion,
        duration: Motion.normal,
        curve: Curves.easeOutCubic,
      );
    }
    if (_current == _Step.building) unawaited(_finish());
  }

  void _back() {
    if (_index == 0) return;
    setState(() => _index--);
    _saveDraft();
    if (_index >= _firstQuestion && _page.hasClients) {
      _page.animateToPage(
        _index - _firstQuestion,
        duration: Motion.normal,
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Everyone has an account before the questions: the plan, scans and
  /// Premium then belong to a person, not a phone. Google also gives us a
  /// first name, so that question arrives already answered.
  Future<void> _accountFirst() async {
    var account = ref.read(accountProvider).value;
    if (account == null) {
      final ok = await context.push<bool>('/auth?mode=create');
      if (ok != true || !mounted) return;
      account = ref.read(accountProvider).value;
    }
    if (!mounted || await _welcomeBack()) return;
    final first = (account?.name ?? '').trim().split(RegExp(r'\s+')).first;
    if (_name.trim().isEmpty && first.isNotEmpty) {
      _name = first;
      _nameField.text = first;
    }
    setState(() => _index++);
  }

  /// Signed back in to a phone that already has this person's plan: straight
  /// back to it, no questions.
  Future<bool> _welcomeBack() async {
    final profile = await ref.read(profileProvider.future);
    if (profile == null || !mounted) return false;
    context.go('/today');
    return true;
  }

  Future<void> _signIn() async {
    final ok = await context.push<bool>('/auth?mode=signin');
    if (ok != true || !mounted || await _welcomeBack()) return;
    if (!mounted) return;
    showSnack(context, 'Signed in. A few questions to set up this phone.');
    _next();
  }

  Future<void> _finish() async {
    final profile = UserProfile(
      name: _name.trim(),
      gender: _gender!,
      ageRange: _age!,
      skinType: _skinType!,
      sensitivity: _sensitivity!,
      concerns: _concerns,
      goals: _goals,
      complexity: _complexity!,
      budget: Budget.mid,
      skinTone: _tone,
      pregnantOrNursing: _pregnant ?? false,
      shaves: _shaves ?? false,
      location: _location,
      amReminder: _am,
      pmReminder: _pm,
      remindersEnabled: _reminders,
      createdAt: clock.now(),
    );
    // Let the "building your plan" moment breathe; it reads as care, not lag.
    await Future<void>.delayed(const Duration(milliseconds: 2600));
    if (!mounted) return;
    // Plan reveal → (paywall) → save. Saving last means an interrupted
    // flow simply restarts onboarding instead of leaving a half state.
    final t = ref.read(telemetryProvider);
    t.track(Ev.onboardingComplete, {
      'gender': profile.gender.name,
      'age': profile.ageRange.name,
      'skin_type': profile.skinType.name,
      'complexity': profile.complexity.name,
      'concerns': profile.concerns.length,
      'has_city': profile.location != null,
    });
    t.track(Ev.planRevealView);
    // Saving the profile moves the router on to Today, so keep the router
    // to open the first scan from there: the routine is built from it.
    final router = GoRouter.of(context);
    await context.push('/plan', extra: profile);
    if (!mounted) return;
    await ref.read(profileProvider.notifier).save(profile);
    await ref.read(kvProvider).remove(KvKeys.onboardingDraft);
    router
      ..go('/today')
      ..push('/scan');
  }

  @override
  void dispose() {
    _page.dispose();
    _nameField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_current) {
      case _Step.welcome:
        return WelcomeStep(onStart: _next, onSignIn: _signIn);
      case _Step.journey:
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _back();
          },
          child: JourneyIntro(onDone: _next),
        );
      case _Step.building:
        return PopScope(
          canPop: false,
          child: BuildingPlanStep(name: _name.trim()),
        );
      default:
        break;
    }
    final c = context.colors;
    final questions = _steps.length - _firstQuestion - 1;
    final number = _index - _firstQuestion + 1;
    final progress = number / questions;
    const showChrome = true;

    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: AuraBackground(
          intensity: 0.6,
          child: SafeArea(
            child: Column(
              children: [
                if (showChrome)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      Space.xs,
                      Space.gutter,
                      0,
                    ),
                    child: Row(
                      children: [
                        CircleButton(
                          icon: Icons.arrow_back_rounded,
                          size: 42,
                          tooltip: 'Back',
                          onTap: _back,
                        ),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(Radii.pill),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(end: progress),
                              duration: Motion.normal,
                              builder: (_, v, _) => LinearProgressIndicator(
                                value: v,
                                minHeight: 4,
                                color: c.ink,
                                backgroundColor: c.surface,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: Space.md),
                        Text(
                          '$number/$questions',
                          style: context.text.labelMedium,
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: PageView(
                    controller: _page,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (final s in _steps.skip(_firstQuestion))
                        if (s != _Step.building) _buildStep(s),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.gutter,
                    Space.xs,
                    Space.gutter,
                    Space.md,
                  ),
                  child: FilledButton(
                    onPressed: _canContinue ? _next : null,
                    child: Text(switch (_current) {
                      _Step.tone when _tone == null => 'Skip',
                      _Step.city when _location == null => 'Skip for now',
                      _Step.city => 'Build my plan',
                      _ => 'Continue',
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(_Step step) {
    return switch (step) {
      _Step.welcome ||
      _Step.journey ||
      _Step.building => const SizedBox.shrink(),
      _Step.insight => InsightStep(
        track: JourneyEngine.trackFor(
          UserProfile(
            name: '',
            gender: _gender ?? Gender.preferNotToSay,
            ageRange: _age ?? AgeRange.a25,
            skinType: _skinType ?? SkinType.unsure,
            sensitivity: _sensitivity ?? Sensitivity.medium,
            concerns: _concerns,
            goals: const {},
            complexity: RoutineComplexity.balanced,
            budget: Budget.mid,
            shaves: _gender == Gender.man,
            createdAt: clock.now(),
          ),
          null,
        ),
        gender: _gender,
      ),
      _Step.name => QuestionStep(
        title: 'What should we call you?',
        subtitle: 'Optional. Stays on your phone.',
        child: TextField(
          controller: _nameField,
          autofocus: false,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(hintText: 'First name'),
          onChanged: (v) => _name = v,
          onSubmitted: (_) => _next(),
        ),
      ),
      _Step.gender => QuestionStep(
        title: 'How do you identify?',
        subtitle: 'Hormones and shaving change what works.',
        child: Column(
          children: [
            for (final g in Gender.values)
              OptionTile(
                title: g.label,
                selected: _gender == g,
                onTap: () => setState(() => _gender = g),
              ),
          ],
        ),
      ),
      _Step.age => QuestionStep(
        title: 'How old are you?',
        child: Column(
          children: [
            OptionTile(
              title: 'Under 13',
              selected: _underAge,
              onTap: () => setState(() {
                _underAge = true;
                _age = null;
              }),
            ),
            for (final a in AgeRange.values)
              OptionTile(
                title: a.label,
                selected: _age == a,
                onTap: () => setState(() {
                  _age = a;
                  _underAge = false;
                }),
              ),
            if (_underAge)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text(
                  'ClearSkin is for ages 13 and up. A parent, school nurse or doctor is the best place to start with skin questions.',
                  style: context.text.bodyMedium?.copyWith(
                    color: context.colors.warn,
                  ),
                ),
              ),
          ],
        ),
      ),
      _Step.skinType => QuestionStep(
        title: 'By midday, your skin feels…',
        child: Column(
          children: [
            for (final t in SkinType.values)
              OptionTile(
                title: t.label,
                subtitle: t.hint,
                selected: _skinType == t,
                onTap: () => setState(() => _skinType = t),
              ),
          ],
        ),
      ),
      _Step.sensitivity => QuestionStep(
        title: 'New products usually…',
        child: Column(
          children: [
            for (final s in Sensitivity.values)
              OptionTile(
                title: s.label,
                selected: _sensitivity == s,
                onTap: () => setState(() => _sensitivity = s),
              ),
          ],
        ),
      ),
      _Step.concerns => QuestionStep(
        title: 'What do you want to work on?',
        subtitle: 'Pick all that apply.',
        child: Column(
          children: [
            for (final cn in Concern.values)
              if (cn != Concern.razorBumps || _gender != Gender.woman)
                OptionTile(
                  title: cn.label,
                  multi: true,
                  selected: _concerns.contains(cn),
                  onTap: () => setState(
                    () => _concerns.contains(cn)
                        ? _concerns.remove(cn)
                        : _concerns.add(cn),
                  ),
                ),
          ],
        ),
      ),
      _Step.goals => QuestionStep(
        title: 'What does great skin mean to you?',
        subtitle: 'Pick up to three.',
        child: Column(
          children: [
            for (final g in Goal.values)
              OptionTile(
                title: g.label,
                multi: true,
                selected: _goals.contains(g),
                onTap: () => setState(() {
                  if (_goals.contains(g)) {
                    _goals.remove(g);
                  } else if (_goals.length < 3) {
                    _goals.add(g);
                  }
                }),
              ),
          ],
        ),
      ),
      _Step.tone => QuestionStep(
        title: 'Which is closest to your skin tone?',
        subtitle: 'Optional. Sharpens sunscreen and dark-mark advice.',
        child: SkinTonePicker(
          value: _tone,
          onChanged: (t) => setState(() => _tone = t),
        ),
      ),
      _Step.pregnancy => QuestionStep(
        title: 'Pregnant, trying or breastfeeding?',
        subtitle: 'We\'ll keep your plan safe.',
        child: Column(
          children: [
            OptionTile(
              title: 'Yes',
              selected: _pregnant == true,
              onTap: () => setState(() => _pregnant = true),
            ),
            OptionTile(
              title: 'No',
              selected: _pregnant == false,
              onTap: () => setState(() => _pregnant = false),
            ),
          ],
        ),
      ),
      _Step.shaving => QuestionStep(
        title: 'Do you shave your face?',
        child: Column(
          children: [
            OptionTile(
              title: 'Yes, regularly',
              selected: _shaves == true,
              onTap: () => setState(() => _shaves = true),
            ),
            OptionTile(
              title: 'No / rarely',
              selected: _shaves == false,
              onTap: () => setState(() => _shaves = false),
            ),
          ],
        ),
      ),
      _Step.complexity => QuestionStep(
        title: 'How much time do you have?',
        child: Column(
          children: [
            for (final r in RoutineComplexity.values)
              OptionTile(
                title: r.label,
                subtitle: r.hint,
                selected: _complexity == r,
                onTap: () => setState(() => _complexity = r),
              ),
          ],
        ),
      ),
      _Step.reminders => QuestionStep(
        title: 'When should we remind you?',
        subtitle: 'Consistency is what changes skin.',
        child: RemindersPicker(
          enabled: _reminders,
          am: _am,
          pm: _pm,
          onChanged: (enabled, am, pm) => setState(() {
            _reminders = enabled;
            _am = am;
            _pm = pm;
          }),
        ),
      ),
      _Step.city => QuestionStep(
        title: 'Where are you based?',
        subtitle: 'For your daily UV and humidity forecast.',
        child: CityPicker(
          value: _location,
          onChanged: (l) => setState(() => _location = l),
        ),
      ),
    };
  }
}

/// First screen: the C·skin mark in soft rings, one promise, three facts.
class WelcomeStep extends StatelessWidget {
  const WelcomeStep({super.key, required this.onStart, required this.onSignIn});
  final VoidCallback onStart;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: AuraBackground(
        intensity: 1.3,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.lg,
              Space.gutter,
              Space.sm,
            ),
            // Fills the screen on tall phones; scrolls on short ones or with
            // large text instead of overflowing.
            child: LayoutBuilder(
              builder: (context, box) {
                final ring = (box.maxHeight * 0.32).clamp(150.0, 260.0);
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Spacer(),
                          Center(
                            child:
                                _Rings(
                                      size: ring,
                                      child: BrandMark(size: ring * 120 / 260),
                                    )
                                    .animate()
                                    .scale(
                                      begin: const Offset(0.9, 0.9),
                                      duration: 900.ms,
                                      curve: Curves.easeOutCubic,
                                    )
                                    .fadeIn(),
                          ),
                          const Spacer(),
                          Text(
                                'Your skin,\nunderstood.',
                                style: context.text.displayMedium,
                              )
                              .animate(delay: 150.ms)
                              .fadeIn(duration: Motion.slow)
                              .slideY(begin: 0.15, curve: Curves.easeOutCubic),
                          const SizedBox(height: Space.sm),
                          Text(
                                'A skin coach for every skin tone.',
                                style: context.text.bodyLarge?.copyWith(
                                  color: c.inkMuted,
                                ),
                              )
                              .animate(delay: 250.ms)
                              .fadeIn(duration: Motion.slow),
                          const SizedBox(height: Space.lg),
                          ArrowPill(label: 'Get started', onTap: onStart),
                          Center(
                            child: TextButton(
                              onPressed: onSignIn,
                              child: const Text('I have an account'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Concentric hairline rings with a soft fill — the welcome halo.
class _Rings extends StatelessWidget {
  const _Rings({required this.size, required this.child});
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (final f in [1.0, 0.78, 0.58])
            Container(
              width: size * f,
              height: size * f,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.surface.withValues(alpha: 0.25 + (1 - f) * 0.6),
                border: Border.all(color: c.surface),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

class _Milestone {
  const _Milestone(this.title, this.eyebrow, this.body, this.weeks);
  final String title;
  final String eyebrow;
  final String body;

  /// Where it sits on the 12-week arc.
  final double weeks;
}

/// "This is your journey": Day 1 → Week 12 along an arc, before the quiz.
class JourneyIntro extends StatefulWidget {
  const JourneyIntro({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<JourneyIntro> createState() => _JourneyIntroState();
}

class _JourneyIntroState extends State<JourneyIntro> {
  static const _steps = [
    _Milestone(
      'Day 1',
      'Your journey begins',
      'A 10-second scan.\nA plan made for your skin.',
      0,
    ),
    _Milestone(
      'Week 2',
      'The habit forms',
      'Two minutes, morning and night.\nWe remind you.',
      2,
    ),
    _Milestone(
      'Week 6',
      'Real change',
      'Weekly scans show\nwhat\'s working.',
      6,
    ),
    _Milestone(
      'Week 12',
      'Your best skin',
      'Clearer, calmer, even.\nAnd you know how to keep it.',
      12,
    ),
  ];

  final _page = PageController();
  int _i = 0;

  void _advance() {
    if (_i == _steps.length - 1) {
      widget.onDone();
      return;
    }
    _page.nextPage(duration: Motion.slow, curve: Curves.easeInOutCubic);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final last = _i == _steps.length - 1;
    return Scaffold(
      body: JourneyBackdrop(
        tone: _i.toDouble(),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.xs,
                  Space.xs,
                  0,
                ),
                child: Row(
                  children: [
                    Eyebrow('This is your journey', color: c.ink),
                    const Spacer(),
                    TextButton(
                      onPressed: widget.onDone,
                      child: const Text('Skip'),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              JourneyArc(weeks: _steps[_i].weeks, height: 120),
              const SizedBox(height: Space.lg),
              SizedBox(
                height: 236,
                child: PageView.builder(
                  controller: _page,
                  itemCount: _steps.length,
                  onPageChanged: (i) => setState(() => _i = i),
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.gutter,
                    ),
                    child: Column(
                      children: [
                        Text(
                          _steps[i].title,
                          style: context.text.displayLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                            letterSpacing: -2,
                          ),
                        ),
                        const SizedBox(height: Space.xs),
                        Eyebrow(_steps[i].eyebrow, color: c.ink),
                        const SizedBox(height: Space.lg),
                        Text(
                          _steps[i].body,
                          textAlign: TextAlign.center,
                          style: context.text.bodyLarge?.copyWith(
                            color: c.inkMuted,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  0,
                  Space.gutter,
                  Space.md,
                ),
                child: FilledButton(
                  onPressed: _advance,
                  child: Text(last ? 'Start my journey' : 'Next'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A calm, honest "here's what to expect" moment after choosing concerns.
class InsightStep extends StatelessWidget {
  const InsightStep({super.key, required this.track, required this.gender});
  final JourneyTrack track;
  final Gender? gender;

  @override
  Widget build(BuildContext context) {
    final (photo, title, body) = switch (track) {
      JourneyTrack.clear => (
        Photos.gelSwirl,
        'Breakouts are\nvery treatable.',
        'Most people see fewer new spots in 6–8 weeks of steady care.',
      ),
      JourneyTrack.fade => (
        Photos.dropperAmber,
        'Dark marks\ndo fade.',
        'Daily SPF plus gentle brighteners. Visible change from week 6.',
      ),
      JourneyTrack.calm => (
        Photos.creamBeige,
        'Calm comes\nfirst.',
        'Two weeks of a gentle routine resets most sensitive skin.',
      ),
      JourneyTrack.smooth => (
        Photos.serumPour,
        'Smoother skin\ntakes 8 weeks.',
        'We start low and slow, so your skin never fights back.',
      ),
      JourneyTrack.balance => (
        Photos.leafDew,
        'Less shine,\nnot less moisture.',
        'Balanced skin makes less oil. Results from week 4.',
      ),
      JourneyTrack.shave => (
        Photos.water,
        'Bumps are about\ntechnique.',
        'Small shaving changes clear most bumps within weeks.',
      ),
      JourneyTrack.glow => (
        Photos.serumPlates,
        'Glow is built,\nnot bought.',
        'Hydration, protection, consistency. That\'s the secret.',
      ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow('Your focus · ${track.title}'),
          const SizedBox(height: Space.sm),
          Text(title, style: context.text.displaySmall),
          const SizedBox(height: Space.sm),
          Text(body, style: context.text.bodyLarge),
          const SizedBox(height: Space.lg),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.lg),
              child: PhotoFill(photo, scrim: 0),
            ),
          ),
        ],
      ).animate().fadeIn(duration: Motion.slow),
    );
  }
}

/// The "Day 1" moment while the plan is generated: the twelve weeks light
/// up along the arc as the plan is laid out, one honest line at a time.
class BuildingPlanStep extends StatelessWidget {
  const BuildingPlanStep({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const lines = [
      'Matching ingredients to your skin',
      'Checking what\'s safe for you',
      'Spacing actives so they never clash',
    ];
    return Scaffold(
      body: JourneyBackdrop(
        child: SafeArea(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 2600),
            curve: Curves.easeInOutCubic,
            builder: (context, v, _) {
              final line = (v * lines.length).floor().clamp(
                0,
                lines.length - 1,
              );
              return Column(
                children: [
                  const SizedBox(height: Space.md),
                  Eyebrow(
                    name.isEmpty
                        ? 'This is your journey'
                        : 'This is your journey, $name',
                    color: c.ink,
                  ),
                  const Spacer(),
                  JourneyArc(weeks: v * 12, height: 120),
                  const SizedBox(height: Space.lg),
                  Text(
                    'Day 1',
                    style: context.text.displayLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      letterSpacing: -2,
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Eyebrow('Building your plan', color: c.ink),
                  const SizedBox(height: Space.lg),
                  AnimatedSwitcher(
                    duration: Motion.slow,
                    child: Text(
                      lines[line],
                      key: ValueKey(line),
                      style: context.text.bodyLarge?.copyWith(
                        color: c.inkMuted,
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
