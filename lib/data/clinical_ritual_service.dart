import '../domain/models/clinical_ritual.dart';
import 'ward_board_service.dart';

class ClinicalRitualService {
  final WardBoardService api;

  const ClinicalRitualService(this.api);

  Future<ClinicalRitual> create({
    required String ritualType,
    required String title,
    String? patientId,
    String? scheduledFor,
  }) async {
    final payload = <String, dynamic>{
      'ritual_type': ritualType,
      'title': title,
    };
    if (patientId != null) payload['patient_id'] = patientId;
    if (scheduledFor != null) payload['scheduled_for'] = scheduledFor;
    final response = await api.communicationRequest(
      'POST',
      '/rituals',
      payload: payload,
    );
    return ClinicalRitual.fromMap(_map(response));
  }

  Future<ClinicalRitual> get(String ritualId) async {
    final response = await api.communicationRequest(
      'GET',
      '/rituals/$ritualId',
    );
    return ClinicalRitual.fromMap(_map(response));
  }

  Future<List<ClinicalRitual>> list() async {
    final response = await api.communicationRequest('GET', '/rituals');
    if (response is! List) {
      throw const FormatException('The ritual service returned an invalid list.');
    }
    return response
        .map((item) => ClinicalRitual.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  Future<ClinicalRitualRoomSession> getRoomSession(String ritualId) async {
    final response = await api.communicationRequest(
      'POST',
      '/rituals/$ritualId/room-token',
    );
    return ClinicalRitualRoomSession.fromMap(_map(response));
  }

  Future<ClinicalRitual> startRecording(String ritualId) async {
    final response = await api.communicationRequest(
      'POST',
      '/rituals/$ritualId/recording/start',
    );
    return ClinicalRitual.fromMap(_map(response));
  }

  Future<ClinicalRitual> stopRecording(String ritualId) async {
    final response = await api.communicationRequest(
      'POST',
      '/rituals/$ritualId/recording/stop',
    );
    return ClinicalRitual.fromMap(_map(response));
  }

  Future<ClinicalRitual> saveTranscript(
    String ritualId,
    String transcript,
  ) async {
    final response = await api.communicationRequest(
      'POST',
      '/rituals/$ritualId/transcript',
      payload: {'transcript': transcript},
    );
    return ClinicalRitual.fromMap(_map(response));
  }

  Future<ClinicalRitual> generateDraft(String ritualId) async {
    final response = await api.communicationRequest(
      'POST',
      '/rituals/$ritualId/draft',
    );
    return ClinicalRitual.fromMap(_map(response));
  }

  Future<ClinicalRitual> editDraft(
    String ritualId,
    Map<String, dynamic> summary,
  ) async {
    final response = await api.communicationRequest(
      'PUT',
      '/rituals/$ritualId/draft',
      payload: {'summary': summary},
    );
    return ClinicalRitual.fromMap(_map(response));
  }

  Future<ClinicalRitual> approve(
    String ritualId,
    Map<String, dynamic> summary,
  ) async {
    final response = await api.communicationRequest(
      'POST',
      '/rituals/$ritualId/approve',
      payload: {'summary': summary},
    );
    return ClinicalRitual.fromMap(_map(response));
  }

  static Map<String, dynamic> _map(Object? response) {
    if (response is! Map<String, dynamic>) {
      throw const FormatException('The ritual service returned invalid data.');
    }
    return response;
  }
}
