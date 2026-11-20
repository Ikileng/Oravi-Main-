import 'dart:async';

import 'package:flutter/material.dart';
import '../data/call_media.dart';

import '../domain/models/call_session.dart';
import '../data/ward_board_service.dart';
import 'theme/clinical_theme.dart';

class CallScreen extends StatefulWidget {
  final CallSession session;
  final WardBoardService api;
  final CallMedia? media;

  const CallScreen({super.key, required this.session, required this.api, this.media});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final CallMedia _media;
  Timer? _durationTimer;
  Timer? _statusTimer;
  bool _checkingStatus = false;
  bool _ending = false;
  bool _canPop = false;
  bool _everConnected = false;
  DateTime? _connectedAt;
  String? _error;
  bool _connecting = true;
  bool _muted = false;
  int _durationSeconds = 0;
  late String _callStatus;

  @override
  void initState() {
    super.initState();
    _callStatus = widget.session.status;
    _media = widget.media ?? LiveKitCallMedia();
    _media.addListener(_mediaChanged);
    unawaited(_connect());
    _statusTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkStatus(),
    );
  }

  Future<void> _checkStatus() async {
    if (_checkingStatus || _ending) return;
    _checkingStatus = true;
    try {
      final call = await widget.api.getCall(widget.session.callId);
      final status = call['status'] as String? ?? _callStatus;
      if (mounted && status != _callStatus) {
        setState(() => _callStatus = status);
        _mediaChanged();
      }
      if (mounted &&
          const {
            'ended',
            'declined',
            'cancelled',
            'missed',
          }.contains(call['status'])) {
        await _end(notifyServer: false);
      }
    } catch (_) {
      // Keep connected audio usable through transient API outages.
    } finally {
      _checkingStatus = false;
    }
  }

  Future<void> _connect() async {
    try {
      await _media.connect(widget.session.liveKitUrl, widget.session.token,
        widget.session.isIncoming ? widget.session.callerId : widget.session.recipientId);
      if (!mounted || _ending) return;
      setState(() {
        _connecting = false;
      });
      _mediaChanged();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = 'Could not connect the call (${error.runtimeType}).';
      });
      await _notifyEnded();
      await _media.close();
    }
  }

  void _mediaChanged() {
    if (!mounted || _ending) return;
    setState(() {});
    if (_media.error != null) {
      _durationTimer?.cancel();
      unawaited(_notifyEnded());
    } else if (_callStatus == 'answered' && _media.ready) {
      _everConnected = true;
      _startDurationClock();
    }
  }

  void _startDurationClock() {
    if (_connectedAt != null) return;
    _connectedAt = DateTime.now();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _connectedAt == null) return;
      if (_media.ready) setState(() => _durationSeconds++);
    });
  }

  Future<void> _notifyEnded() async {
    try {
      if (!widget.session.isIncoming && _callStatus == 'ringing') {
        try { await widget.api.cancelCall(widget.session.callId); }
        catch (_) { await widget.api.endCall(widget.session.callId); }
      } else {
        await widget.api.endCall(widget.session.callId);
      }
    } catch (_) { /* Peer departure and server polling provide fallback. */ }
  }

  Future<void> _end({bool notifyServer = true}) async {
    if (_ending) return;
    _ending = true;
    _statusTimer?.cancel();
    _durationTimer?.cancel();
    await Future.wait([
      _media.close().catchError((Object _) {}),
      if (notifyServer) _notifyEnded(),
    ]);
    if (!mounted) return;
    setState(() => _canPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(_everConnected ? _durationSeconds : null);
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _durationTimer?.cancel();
    if (!_ending) unawaited(_notifyEnded());
    unawaited(_media.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final otherParty = widget.session.isIncoming
        ? widget.session.callerName
        : widget.session.recipientName;
    return PopScope<int>(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) { if (!didPop) unawaited(_end()); },
      child: Scaffold(
      backgroundColor: ClinicalTheme.background,
      appBar: AppBar(title: const Text('Oravi call')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircleAvatar(
                radius: 42,
                backgroundColor: ClinicalTheme.routineTeal,
                child: Icon(Icons.person, size: 42, color: Colors.white),
              ),
              const SizedBox(height: 16),
              Text(
                otherParty,
                style: const TextStyle(
                  color: ClinicalTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _error ?? _media.error ??
                    (_connecting
                        ? 'Connecting securely…'
                        : _callStatus == 'ringing'
                        ? 'Calling • waiting for the clinician to answer. If they are offline or do not answer, this call will be marked missed.'
                        : _media.reconnecting
                        ? 'Reconnecting audio…'
                        : !_media.ready
                        ? 'Waiting for the other clinician to connect audio…'
                        : 'Connected • ${_durationSeconds}s'),
                style: TextStyle(
                  color: _error == null
                      ? ClinicalTheme.textSecondary
                      : ClinicalTheme.criticalRed,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_error == null && !_connecting)
                IconButton.filled(
                  onPressed: () async {
                    final nextMuted = !_muted;
                    try {
                      await _media.setMuted(nextMuted);
                      if (mounted) setState(() => _muted = nextMuted);
                    } catch (_) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Could not change microphone state.')));
                    }
                  },
                  icon: Icon(_muted ? Icons.mic_off : Icons.mic),
                  tooltip: _muted ? 'Unmute' : 'Mute',
                ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => _end(),
                style: FilledButton.styleFrom(
                  backgroundColor: ClinicalTheme.criticalRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                ),
                icon: const Icon(Icons.call_end),
                label: const Text('End call'),
              ),
            ],
          ),
        ),
      ),
    ));
  }
}
