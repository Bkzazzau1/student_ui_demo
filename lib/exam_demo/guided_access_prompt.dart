import 'dart:async';

import 'package:flutter/material.dart';

import 'exam_lockdown_service.dart';

/// Asks the student to turn on Guided Access on an iPad and waits until it is
/// on. Returns true once Guided Access is active, false if the student
/// cancels.
///
/// Guided Access keeps the iPad on K-SLAS until the exam ends. An ordinary
/// app cannot turn it on by itself (only a school-managed iPad can), so the
/// student does it with a triple-click.
abstract final class GuidedAccessPrompt {
  static Future<bool> show(
    BuildContext context, {
    ExamLockdownService lockdown = const ExamLockdownService(),
    Duration pollInterval = const Duration(seconds: 1),
  }) async {
    final started = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _GuidedAccessDialog(lockdown: lockdown, pollInterval: pollInterval),
    );
    return started == true;
  }
}

class _GuidedAccessDialog extends StatefulWidget {
  const _GuidedAccessDialog({
    required this.lockdown,
    required this.pollInterval,
  });

  final ExamLockdownService lockdown;
  final Duration pollInterval;

  @override
  State<_GuidedAccessDialog> createState() => _GuidedAccessDialogState();
}

class _GuidedAccessDialogState extends State<_GuidedAccessDialog> {
  Timer? _poll;
  StreamSubscription<ExamLockdownEvent>? _events;
  bool _checking = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _events = widget.lockdown.events.listen((event) {
      if (event.guidedAccessStarted) _finish();
    });
    _poll = Timer.periodic(widget.pollInterval, (_) => _check());
    unawaited(_check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    unawaited(_events?.cancel());
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking || _done) return;
    _checking = true;
    try {
      final status = await widget.lockdown.status();
      if (status.lockTaskActive) _finish();
    } catch (_) {
      // Keep waiting; the student can cancel.
    } finally {
      _checking = false;
    }
  }

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Turn on Guided Access'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Guided Access keeps this iPad on your exam until you submit.',
            ),
            const SizedBox(height: 12),
            const _Step(
              number: 1,
              text:
                  'Triple-click the top button (or the Home button on an iPad '
                  'that has one).',
            ),
            const _Step(number: 2, text: 'Tap Start.'),
            const SizedBox(height: 12),
            Text(
              'Nothing happens? Turn it on first: Settings > Accessibility > '
              'Guided Access, then set a passcode.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your exam opens as soon as Guided Access is on.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 22, child: Text('$number.')),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
