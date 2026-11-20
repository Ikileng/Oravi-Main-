import 'dart:async';
import 'dart:ui';

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
    _media.removeListener(_mediaChanged);
    if (!_ending) unawaited(_notifyEnded());
    unawaited(_media.close());
    super.dispose();
  }

  String get _formattedDuration {
    final minutes = (_durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_durationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String get _statusLabel {
    if (_error != null) return 'Connection failed';
    if (_connecting) return 'Connecting securely';
    if (_callStatus == 'ringing') return 'Waiting for answer';
    if (_callStatus == 'answered') return 'Secure call connected';
    return _callStatus.replaceAll('_', ' ');
  }

  String get _supportingMessage {
    if (_error != null) return _error!;
    if (_connecting) {
      return 'Setting up an encrypted audio connection.';
    }
    if (_media.reconnecting) {
      return 'The audio connection is reconnecting. Keep this call open.';
    }
    if (_media.error != null) {
      return _media.error!;
    }
    if (_callStatus == 'ringing') {
      return 'The clinician has been notified. If they are unavailable, this call will be marked as missed.';
    }
    return 'Audio is connected. Document the agreed outcome after ending the call.';
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2);
    return parts.map((part) => part[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final otherParty = widget.session.isIncoming
        ? widget.session.callerName
        : widget.session.recipientName;
    final otherRole = widget.session.isIncoming
        ? widget.session.callerRole
        : widget.session.recipientRole;
    final active = _error == null &&
        _media.error == null &&
        !_connecting &&
        _media.ready;
    return PopScope<int>(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) { if (!didPop) unawaited(_end()); },
      child: Scaffold(
      backgroundColor: ClinicalTheme.background,
      appBar: AppBar(
        title: Text(
          widget.session.isIncoming ? 'Incoming call' : 'Clinical call',
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 40,
              ),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: ClinicalTheme.surfaceAccent,
                          borderRadius: BorderRadius.circular(
                            ClinicalTheme.radiusLarge,
                          ),
                          border: Border.all(
                            color: ClinicalTheme.clinicalBlue.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_outline,
                              size: 16,
                              color: ClinicalTheme.clinicalBlue,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Secure clinical audio',
                              style: TextStyle(
                                color: ClinicalTheme.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    CircleAvatar(
                      radius: 52,
                      backgroundColor: ClinicalTheme.clinicalBlue.withValues(
                        alpha: 0.16,
                      ),
                      child: Text(
                        _initials(otherParty),
                        style: const TextStyle(
                          color: ClinicalTheme.clinicalBlue,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      otherParty,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: ClinicalTheme.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      otherRole.replaceAll('_', ' ').toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: ClinicalTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _CallStatusCard(
                      label: _statusLabel,
                      message: _supportingMessage,
                      duration: _everConnected
                          ? _formattedDuration
                          : null,
                      isError: _error != null || _media.error != null,
                      isLoading: _connecting,
                    ),
                    const Spacer(),
                    const SizedBox(height: 28),
                    if (active)
                      _CallControl(
                        icon: _muted ? Icons.mic_off : Icons.mic,
                        label: _muted ? 'Unmute' : 'Mute',
                        active: _muted,
                        onPressed: () async {
                          final nextMuted = !_muted;
                          try {
                            await _media.setMuted(nextMuted);
                            if (mounted) setState(() => _muted = nextMuted);
                          } catch (_) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Could not change microphone state.',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                      )
                    else
                      const SizedBox(height: 84),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _ending ? null : () => _end(),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          backgroundColor: ClinicalTheme.criticalRed,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.call_end),
                        label: Text(
                          _ending
                              ? 'Ending call…'
                              : _callStatus == 'ringing'
                              ? 'Cancel call'
                              : 'End call',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ));
  }
}

class _CallStatusCard extends StatelessWidget {
  const _CallStatusCard({
    required this.label,
    required this.message,
    required this.duration,
    required this.isError,
    required this.isLoading,
  });

  final String label;
  final String message;
  final String? duration;
  final bool isError;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? ClinicalTheme.criticalRed
        : duration != null
        ? ClinicalTheme.successGreen
        : ClinicalTheme.clinicalBlue;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(ClinicalTheme.radiusMedium),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else
                Icon(
                  isError ? Icons.error_outline : Icons.graphic_eq,
                  color: color,
                  size: 18,
                ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (duration != null) ...[
                const SizedBox(width: 8),
                Text(
                  duration!,
                  style: const TextStyle(
                    color: ClinicalTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ClinicalTheme.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _CallControl extends StatelessWidget {
  const _CallControl({
    required this.icon,
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      IconButton.filled(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size(64, 64),
          backgroundColor: active
              ? ClinicalTheme.criticalRed
              : ClinicalTheme.surfaceElevated,
          foregroundColor: Colors.white,
        ),
        icon: Icon(icon, size: 28),
        tooltip: label,
      ),
      const SizedBox(height: 7),
      Text(
        label,
        style: const TextStyle(
          color: ClinicalTheme.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}
