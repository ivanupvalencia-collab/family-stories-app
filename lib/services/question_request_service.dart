import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/question_request.dart';

abstract class QuestionRequestService {
  Future<List<QuestionRequest>> loadPendingForRecipient(String recipientId);

  Stream<void> watchChangesForRecipient(String recipientId);

  Future<String> sendQuestion({
    required String familyMemberId,
    required String questionText,
  });

  Future<void> uploadAnswerAudio({
    required String localAudioPath,
    required String objectPath,
  });

  Future<String> completeQuestionRequest({
    required String questionRequestId,
    required String audioPath,
    required int durationSeconds,
  });

  Future<void> deleteAnswerAudio(String objectPath);
}

String createQuestionAnswerObjectPath(
  String questionRequestId, {
  Random? random,
}) {
  final secureRandom = random ?? Random.secure();
  final filename = List.generate(
    16,
    (_) => secureRandom.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return '$questionRequestId/$filename.m4a';
}

class SupabaseQuestionRequestService implements QuestionRequestService {
  SupabaseQuestionRequestService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const audioBucketName = 'story-audio';

  @override
  Stream<void> watchChangesForRecipient(String recipientId) {
    late final StreamController<void> controller;
    late final RealtimeChannel channel;
    var cancelled = false;

    controller = StreamController<void>(
      onListen: () {
        final channelName =
            'question_requests:$recipientId:'
            '${DateTime.now().microsecondsSinceEpoch}';
        channel = _client
            .channel(channelName)
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'question_requests',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'recipient_id',
                value: recipientId,
              ),
              callback: (_) {
                if (!cancelled && !controller.isClosed) {
                  controller.add(null);
                }
              },
            )
            .subscribe();
      },
      onCancel: () async {
        cancelled = true;
        await _client.removeChannel(channel);
        await controller.close();
      },
    );
    return controller.stream;
  }

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

  @override
  Future<void> uploadAnswerAudio({
    required String localAudioPath,
    required String objectPath,
  }) async {
    await _client.storage
        .from(audioBucketName)
        .upload(
          objectPath,
          File(localAudioPath),
          fileOptions: const FileOptions(
            contentType: 'audio/mp4',
            upsert: false,
          ),
        );
  }

  @override
  Future<String> completeQuestionRequest({
    required String questionRequestId,
    required String audioPath,
    required int durationSeconds,
  }) async {
    final data = await _client.rpc(
      'complete_question_request',
      params: {
        'p_question_request_id': questionRequestId,
        'p_audio_path': audioPath,
        'p_duration_seconds': durationSeconds,
      },
    );
    if (data is! String || data.isEmpty) {
      throw StateError('The complete question request RPC returned no id.');
    }
    return data;
  }

  @override
  Future<void> deleteAnswerAudio(String objectPath) async {
    await _client.storage.from(audioBucketName).remove([objectPath]);
  }
}
