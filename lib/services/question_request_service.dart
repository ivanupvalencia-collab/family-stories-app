import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/question_request.dart';

abstract class QuestionRequestService {
  Future<List<QuestionRequest>> loadPendingForRecipient(String recipientId);

  Future<String> sendQuestion({
    required String familyMemberId,
    required String questionText,
  });
}

class SupabaseQuestionRequestService implements QuestionRequestService {
  SupabaseQuestionRequestService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<List<QuestionRequest>> loadPendingForRecipient(
    String recipientId,
  ) async {
    final data = await _client
        .from('question_requests')
        .select(
          'id, sender_id, recipient_id, family_member_id, question_text, status, created_at, answered_at',
        )
        .eq('recipient_id', recipientId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    return data.map(QuestionRequest.fromJson).toList();
  }

  @override
  Future<String> sendQuestion({
    required String familyMemberId,
    required String questionText,
  }) async {
    final data = await _client.rpc(
      'send_question_request',
      params: {
        'p_family_member_id': familyMemberId,
        'p_question_text': questionText,
      },
    );
    if (data is! String || data.isEmpty) {
      throw StateError('The question request RPC returned no id.');
    }
    return data;
  }
}
