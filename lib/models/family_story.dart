import 'local_id.dart';

class FamilyStory {
  const FamilyStory({
    required this.id,
    required this.familyMemberId,
    required this.question,
    required this.audioPath,
    required this.duration,
    required this.createdAt,
    this.questionRequestId,
    this.recordedBy,
  });

  factory FamilyStory.fromJson(Map<String, dynamic> json) {
    return FamilyStory(
      id: json['id'] as String,
      familyMemberId: json['familyMemberId'] as String,
      question: json['question'] as String,
      audioPath: json['audioPath'] as String,
      duration: Duration(milliseconds: json['durationMilliseconds'] as int),
      createdAt: DateTime.parse(json['createdAt'] as String),
      questionRequestId: json['questionRequestId'] as String?,
      recordedBy: json['recordedBy'] as String?,
    );
  }

  factory FamilyStory.fromSupabaseJson(Map<String, dynamic> json) {
    return FamilyStory(
      id: json['id'] as String,
      familyMemberId: json['family_member_id'] as String,
      question: json['question'] as String,
      audioPath: json['audio_path'] as String,
      duration: Duration(seconds: (json['duration_seconds'] as num).toInt()),
      createdAt: DateTime.parse(json['created_at'] as String),
      questionRequestId: json['question_request_id'] as String?,
      recordedBy: json['recorded_by'] as String?,
    );
  }

  final String id;
  final String familyMemberId;
  final String question;
  final String audioPath;
  final Duration duration;
  final DateTime createdAt;
  final String? questionRequestId;
  final String? recordedBy;

  static String createId() => generateLocalId();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'familyMemberId': familyMemberId,
      'question': question,
      'audioPath': audioPath,
      'durationMilliseconds': duration.inMilliseconds,
      'createdAt': createdAt.toIso8601String(),
      'questionRequestId': questionRequestId,
      'recordedBy': recordedBy,
    };
  }
}
