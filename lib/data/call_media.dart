import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

/// Media readiness is separate from accepting an invitation on the backend.
abstract class CallMedia extends ChangeNotifier {
  bool get ready;
  bool get reconnecting;
  String? get error;
  Future<void> connect(String url, String token, String otherIdentity);
  Future<void> setMuted(bool muted);
  Future<void> close();
}

class LiveKitCallMedia extends CallMedia {
  final Room _room = Room(
    roomOptions: const RoomOptions(adaptiveStream: false, dynacast: false),
  );
  late final EventsListener<RoomEvent> _events;
  String _otherIdentity = '';
  bool _microphoneReady = false;
  bool _closed = false;
  bool _reconnecting = false;
  String? _error;

  LiveKitCallMedia() {
    _room.addListener(_changed);
    _events = _room.createListener()
      ..on<RoomReconnectingEvent>((_) {
        _reconnecting = true;
        _changed();
      })
      ..on<RoomReconnectedEvent>((_) {
        _reconnecting = false;
        _changed();
      })
      ..on<RoomDisconnectedEvent>((_) {
        if (_closed) return;
        _error = 'Audio disconnected. End this call and try again.';
        _changed();
      });
  }

  @override
  bool get ready => !_closed && _error == null && !_reconnecting &&
      _microphoneReady && _room.connectionState == ConnectionState.connected &&
      _room.remoteParticipants.values.any((p) => p.identity == _otherIdentity);
  @override
  bool get reconnecting => _reconnecting;
  @override
  String? get error => _error;

  void _changed() { if (!_closed) notifyListeners(); }

  @override
  Future<void> connect(String url, String token, String otherIdentity) async {
    _otherIdentity = otherIdentity;
    await _room.connect(url, token);
    if (_closed) { await _room.disconnect(); return; }
    await _room.localParticipant!.setMicrophoneEnabled(true);
    _microphoneReady = true;
    _changed();
  }

  @override
  Future<void> setMuted(bool muted) async {
    await _room.localParticipant!.setMicrophoneEnabled(!muted);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _room.removeListener(_changed);
    await _events.dispose();
    try { await _room.disconnect(); } finally { await _room.dispose(); }
    super.dispose();
  }
}
