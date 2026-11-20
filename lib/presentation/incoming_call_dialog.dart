import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/ward_board_service.dart';

/// Returns true to answer, false to decline, null when the invite has expired.
class IncomingCallDialog extends StatefulWidget {
  final WardBoardService api;
  final String callId;
  final String callerName;
  const IncomingCallDialog({super.key, required this.api,
    required this.callId, required this.callerName});
  @override
  State<IncomingCallDialog> createState() => _IncomingCallDialogState();
}

class _IncomingCallDialogState extends State<IncomingCallDialog> {
  Timer? _timer;
  bool _checking = false;
  bool _finished = false;
  @override
  void initState() {
    super.initState();
    _ring();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _check());
  }
  void _ring() {
    unawaited(SystemSound.play(SystemSoundType.alert).catchError((Object _) {}));
    unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
  }
  Future<void> _check() async {
    if (_checking || _finished) return;
    _checking = true;
    try {
      final call = await widget.api.getCall(widget.callId);
      if (!mounted || _finished) return;
      if (call['status'] != 'ringing') { _finish(null); return; }
      _ring();
    } catch (_) { /* Acceptance revalidates state after a transient outage. */ }
    finally { _checking = false; }
  }
  void _finish(bool? answer) {
    if (_finished || !mounted) return;
    _finished = true;
    _timer?.cancel();
    Navigator.of(context).pop(answer);
  }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      title: const Text('Incoming Oravi call'),
      content: Text('Call from ${widget.callerName}.'),
      actions: [
        TextButton(onPressed: () => _finish(false), child: const Text('Decline')),
        FilledButton(onPressed: () => _finish(true), child: const Text('Answer')),
      ],
    ),
  );
}
