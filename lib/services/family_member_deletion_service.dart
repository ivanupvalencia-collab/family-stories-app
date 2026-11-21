import 'package:supabase_flutter/supabase_flutter.dart';

import 'persistent_story_waveform_service.dart';

// S-8: the gate is the versioned baseline, never a verbal confirmation.
// This flag may only stay `true` while supabase/migrations/ keeps both
// deletion RPCs (revoked from public/anon, granted to authenticated):
// test/deletion_sql_gate_test.dart and tool/lint_rls.sh fail otherwise.
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
      // C-10: validate the whole plan before touching storage, so a corrupt
      // plan never applies a partial deletion.
      for (final resource in plan.resources) {
        if (!const {
              'family-member-photos',
              'story-photos',
              'story-audio',
            }.contains(resource.bucket) ||
            resource.path.isEmpty) {
          throw const FormatException('Invalid deletion resource.');
        }
      }
      // C-10: one remove per bucket instead of one per object. The storage
      // API takes up to 1000 prefixes per request; we stay at 100. The sweep
      // stays sequential with a short-circuit: a failure stops it before
      // finish runs, exactly like the per-object loop did.
      final pathsByBucket = <String, List<String>>{};
      for (final resource in plan.resources) {
        pathsByBucket.putIfAbsent(resource.bucket, () => []).add(resource.path);
      }
      for (final entry in pathsByBucket.entries) {
        final paths = entry.value;
        for (var offset = 0; offset < paths.length; offset += 100) {
          requireSession();
          try {
            await _client.storage
                .from(entry.key)
                .remove(paths.skip(offset).take(100).toList());
          } on StorageException catch (error) {
            // Missing objects are clean. Permission/network failures are not.
            if (error.statusCode != '404') rethrow;
          }
        }
      }
      requireSession();
      await _client.rpc(
        'finish_family_member_delete',
        params: {'p_family_member_id': familyMemberId},
      );
      requireSession();
      await StoryWaveforms.forClient(_client).forgetFamily(familyMemberId);
      return plan;
    } finally {
      _busy.remove(familyMemberId);
    }
  }
}
