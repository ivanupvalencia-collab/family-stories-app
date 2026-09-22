import 'local_id.dart';

class FamilyStory {
  const FamilyStory({
    required this.id,
    required this.familyMemberId,
    required this.question,
    required this.audioPath,
    required this.duration,
    required this.createdAt,
  });

  factory FamilyStory.fromJson(Map<String, dynamic> json) {
    return FamilyStory(
      id: json['id'] as String,
      familyMemberId: json['familyMemberId'] as String,
      question: json['question'] as String,
      audioPath: json['audioPath'] as String,
      duration: Duration(milliseconds: json['durationMilliseconds'] as int),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  final String id;
  final String familyMemberId;
  final String question;
  final String audioPath;
  final Duration duration;
  final DateTime createdAt;

  static String createId() => generateLocalId();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'familyMemberId': familyMemberId,
      'question': question,
      'audioPath': audioPath,
      'durationMilliseconds': duration.inMilliseconds,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
