import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/chat.dart';

class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key});

  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  static const _suggestions = [
    'Why am I breaking out on my chin?',
    'Can I use vitamin C and retinol together?',
    'How do I fade dark marks faster?',
    'Which sunscreen won\'t leave a white cast?',
    'Is my routine too harsh?',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? text]) async {
    final msg = text ?? _input.text;
    if (msg.trim().isEmpty) return;
    if (!ref.read(premiumProvider)) {
      await context.push('/paywall?source=coach');
      return;
    }
    _input.clear();
    final future = ref.read(chatProvider.notifier).send(msg);
    _scrollToEnd();
    await future;
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 120,
          duration: Motion.normal,
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    final c = context.colors;
    final state = chat.value;
    final messages = state?.messages ?? const <ChatMessage>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Skin coach'),
        actions: [
          if (messages.isNotEmpty)
            IconButton(
              tooltip: 'Clear conversation',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                final ok = await confirm(
                  context,
                  title: 'Clear conversation?',
                  body: 'Your chat history will be deleted from this phone.',
                  confirmLabel: 'Clear',
                );
                if (ok) await ref.read(chatProvider.notifier).clear();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(Space.gutter),
                    children: [
                      Text(
                        'Ask about\nyour skin.',
                        style: context.text.displaySmall?.copyWith(
                          fontWeight: FontWeight.w300,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: Space.sm),
                      Text(
                        'Knows your scans, routine and shelf.',
                        style: context.text.bodyLarge?.copyWith(
                          color: c.inkMuted,
                        ),
                      ),
                      const SizedBox(height: Space.xl),
                      // Questions as a hairline list, not prompt bubbles.
                      for (final (i, s) in _suggestions.indexed)
                        InkWell(
                          onTap: () => _send(s),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: Space.md,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                top: i == 0
                                    ? BorderSide(color: c.line)
                                    : BorderSide.none,
                                bottom: BorderSide(color: c.line),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(s, style: context.text.bodyLarge),
                                ),
                                const SizedBox(width: Space.sm),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 18,
                                  color: c.inkFaint,
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: Space.md),
                      const Disclaimer(),
                    ],
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(Space.md),
                    itemCount:
                        messages.length + ((state?.sending ?? false) ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= messages.length) return const _Typing();
                      return _Bubble(message: messages[i]);
                    },
                  ),
          ),
          if (state?.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              child: Text(
                state!.error!,
                style: context.text.bodySmall?.copyWith(color: c.bad),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.md,
                Space.xs,
                Space.xs,
                Space.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Ask about your skin…',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    onPressed: (state?.sending ?? false) ? null : _send,
                    icon: Icon(Icons.send_rounded, color: c.primary),
                    tooltip: 'Send',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mine = message.role == ChatRole.user;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.xs),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        decoration: BoxDecoration(
          color: mine ? c.primary : c.surface,
          border: mine ? null : Border.all(color: c.line),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(Radii.md),
            topRight: const Radius.circular(Radii.md),
            bottomLeft: Radius.circular(mine ? Radii.md : 4),
            bottomRight: Radius.circular(mine ? 4 : Radii.md),
          ),
        ),
        child: SelectableText(
          message.text,
          style: context.text.bodyLarge?.copyWith(
            color: mine ? c.onPrimary : c.ink,
          ),
        ),
      ),
    ).animate().fadeIn(duration: Motion.fast).slideY(begin: 0.1);
  }
}

class _Typing extends StatelessWidget {
  const _Typing();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: c.inkFaint,
                      shape: BoxShape.circle,
                    ),
                  )
                  .animate(onPlay: (a) => a.repeat(reverse: true))
                  .fadeOut(delay: (150 * i).ms, duration: 500.ms),
          ],
        ),
      ),
    );
  }
}
