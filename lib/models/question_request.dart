enum QuestionRequestStatus { pending, answered }

class QuestionRequest {
  const QuestionRequest({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.familyMemberId,
    required this.questionText,
    required this.status,
    required this.createdAt,
    this.answeredAt,
  });

  factory QuestionRequest.fromJson(Map<String, dynamic> json) {
    return QuestionRequest(
      id: json['id'] as String,
      senderId: json['sender_id'] as String,
      recipientId: json['recipient_id'] as String,
      familyMemberId: json['family_member_id'] as String,
      questionText: json['question_text'] as String,
      status: switch (json['status']) {
        'pending' => QuestionRequestStatus.pending,
        'answered' => QuestionRequestStatus.answered,
        final value => throw FormatException(
          'Unknown question request status: $value',
        ),
      },
      createdAt: DateTime.parse(json['created_at'] as String),
      answeredAt: json['answered_at'] == null
          ? null
          : DateTime.parse(json['answered_at'] as String),
    );
  }

  final String id;
  final String senderId;
  final String recipientId;
  final String familyMemberId;
  final String questionText;
  final QuestionRequestStatus status;
  final DateTime createdAt;
  final DateTime? answeredAt;
}
