import 'package:supabase_flutter/supabase_flutter.dart';

class ReceivedRequestDetails {
  const ReceivedRequestDetails({this.senderName, this.durationSeconds});
  final String? senderName;
  final int? durationSeconds;
}

abstract class ReceivedRequestDetailsService {
  Future<Map<String, ReceivedRequestDetails>> load(List<String> requestIds);
}

class SupabaseReceivedRequestDetailsService
    implements ReceivedRequestDetailsService {
  SupabaseReceivedRequestDetailsService({SupabaseClient? client})
    : _override = client;
  final SupabaseClient? _override;

  @override
  Future<Map<String, ReceivedRequestDetails>> load(
    List<String> requestIds,
  ) async {
    if (requestIds.isEmpty) return {};
    final client = _override ?? Supabase.instance.client;
    final owner = client.auth.currentUser?.id;
    if (owner == null) throw StateError('Recipient session required.');
    final ids = requestIds.toSet().toList();
    // C-10: the chunks fly in parallel instead of one round trip after
    // another. The input comes from the C-6 capped lists (<=500 ids each),
    // so at most ~10 chunks are in flight.
    final chunks = <List<String>>[
      for (var offset = 0; offset < ids.length; offset += 100)
        ids.skip(offset).take(100).toList(),
    ];
    final responses = await Future.wait([
      for (final chunk in chunks)
        client.rpc(
          'get_received_request_details',
          params: {'p_request_ids': chunk},
        ),
    ]);
    if (client.auth.currentUser?.id != owner) {
      throw StateError('Session changed.');
    }
    final results = <String, ReceivedRequestDetails>{};
    for (final data in responses) {
      for (final row in data as List) {
        final name = (row['sender_name'] as String?)?.trim();
        results[row['request_id'] as String] = ReceivedRequestDetails(
          senderName: name == null || name.isEmpty ? null : name,
          durationSeconds: (row['duration_seconds'] as num?)?.toInt(),
        );
      }
    }
    return results;
  }
}
