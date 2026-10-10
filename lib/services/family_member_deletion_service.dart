import 'package:supabase_flutter/supabase_flutter.dart';

// Manual installation of SQL 07 has been confirmed by the owner.
const familyMemberRemoteDeletionEnabled = true;

class FamilyMemberDeletionPlan {
  FamilyMemberDeletionPlan.fromJson(Map<String, dynamic> json)
    : resources = (json['resources'] as List)
          .map(
            (v) => (bucket: v['bucket'] as String, path: v['path'] as String),
          )
          .toList(),
      storyIds = List<String>.from(json['story_ids'] as List);

  final List<({String bucket, String path})> resources;
  final List<String> storyIds;
}

abstract interface class FamilyMemberDeletionService {
  bool get enabled;
  Future<FamilyMemberDeletionPlan> delete({
    required String ownerId,
    required String familyMemberId,
  });
}

class SupabaseFamilyMemberDeletionService
    implements FamilyMemberDeletionService {
  SupabaseFamilyMemberDeletionService({
    SupabaseClient? client,
    this.enabled = familyMemberRemoteDeletionEnabled,
  }) : _override = client;

  final SupabaseClient? _override;
  SupabaseClient get _client => _override ?? Supabase.instance.client;
  @override
  final bool enabled;
  final Set<String> _busy = {};

  @override
  Future<FamilyMemberDeletionPlan> delete({
    required String ownerId,
    required String familyMemberId,
  }) async {
    if (!enabled) throw StateError('Manual SQL 07 is not confirmed.');
    if (!_busy.add(familyMemberId)) throw StateError('Deletion in progress.');
    // Identity checks here protect account changes; ownership is verified by
    // both RPCs against the database, never inferred from client IDs/paths.
    final session = _client.auth.currentSession;
    void requireSession() {
      if (session == null ||
          session.user.id != ownerId ||
          !identical(_client.auth.currentSession, session)) {
        throw StateError('The owner session changed.');
      }
    }

    try {
      requireSession();
      final data = await _client.rpc(
        'prepare_family_member_delete',
        params: {'p_family_member_id': familyMemberId},
      );
      requireSession();
      final plan = FamilyMemberDeletionPlan.fromJson(
        Map<String, dynamic>.from(data as Map),
      );
      for (final resource in plan.resources) {
        requireSession();
        if (!const {
              'family-member-photos',
              'story-photos',
              'story-audio',
            }.contains(resource.bucket) ||
            resource.path.isEmpty) {
          throw const FormatException('Invalid deletion resource.');
        }
        try {
          await _client.storage.from(resource.bucket).remove([resource.path]);
        } on StorageException catch (error) {
          // Missing objects are clean. Permission/network failures are not.
          if (error.statusCode != '404') rethrow;
        }
        requireSession();
      }
      await _client.rpc(
        'finish_family_member_delete',
        params: {'p_family_member_id': familyMemberId},
      );
      requireSession();
      return plan;
    } finally {
      _busy.remove(familyMemberId);
    }
  }
}
