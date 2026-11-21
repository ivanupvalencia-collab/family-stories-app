import '../models/question_request.dart';
import '../services/received_request_details_service.dart';

/// A-2: pure presentation rules for request metadata, shared by Home and
/// the requests list. Moved out of the widget layer.
String requestDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}

String requestSubtitle(
  QuestionRequest request,
  ReceivedRequestDetails? details, {
  bool keepTimingTogether = false,
  bool recipientOnSeparateLine = false,
}) {
  final name = details?.senderName;
  final answered = request.status == QuestionRequestStatus.answered;
  final parts = <String>[
    if (name != null)
      '${answered ? 'Para' : 'De'} $name'
    else
      answered ? 'Para quien te preguntó' : 'Una pregunta para ti',
    if (answered && request.answeredAt != null)
      requestDate(request.answeredAt!)
    else if (!answered)
      requestDate(request.createdAt),
    if (answered && details?.durationSeconds != null)
      '${details!.durationSeconds! ~/ 60}:${(details.durationSeconds! % 60).toString().padLeft(2, '0')}',
  ];
  if (keepTimingTogether &&
      answered &&
      request.answeredAt != null &&
      details?.durationSeconds != null) {
    final duration = parts.removeLast();
    parts[parts.length - 1] = '${parts.last}\u00a0·\u00a0$duration';
  }
  if (recipientOnSeparateLine && parts.length > 1) {
    return '${parts.first}\n${parts.skip(1).join(' · ')}';
  }
  return parts.join(' · ');
}
