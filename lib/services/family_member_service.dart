import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/family_member.dart';
import 'remote_family_member_cache.dart';

abstract class FamilyMemberService {
  Future<List<FamilyMember>> loadForOwner(String ownerId);

  Future<FamilyMember?> loadMemberForOwner({
    required String ownerId,
    required String familyMemberId,
  });

  Future<FamilyMember> create({
    required String ownerId,
    required String name,
    required String relationship,
  });

  Future<FamilyMember> updatePhoto({
    required String ownerId,
    required String familyMemberId,
    required String? photoPath,
    required String? expectedPhotoPath,
  });
}

class SupabaseFamilyMemberService
    implements FamilyMemberService, CachedFamilyMemberService {
  SupabaseFamilyMemberService({
    SupabaseClient? client,
    RemoteFamilyMemberCache? cache,
  }) : _client = client ?? Supabase.instance.client {
    _cache = cache ?? (_caches[_client] ??= RemoteFamilyMemberCache());
    _account = _client.auth.currentUser?.id;
    _client.auth.onAuthStateChange.listen((state) {
      final next = state.session?.user.id;
      if (next != _account || state.event == AuthChangeEvent.signedOut) {
        _generation++;
        _account = next;
      }
    });
  }

  final SupabaseClient _client;
  static final _caches = Expando<RemoteFamilyMemberCache>();
  late final RemoteFamilyMemberCache _cache;
  String? _account;
  int _generation = 0;
  int _loadSequence = 0;
  String get _backend => _client.storage.url;

  void _requireOwner(String ownerId, int generation) {
    if (_client.auth.currentUser?.id != ownerId || generation != _generation) {
      throw StateError('The owner session changed.');
    }
  }

  @override
  Future<List<FamilyMember>?> loadCachedForOwner(String ownerId) async {
    final generation = _generation;
    _requireOwner(ownerId, generation);
    final members = await _cache.read(_backend, ownerId);
    _requireOwner(ownerId, generation);
    return members;
  }

  @override
  Future<List<FamilyMember>> loadForOwner(String ownerId) async {
    final generation = _generation;
    _requireOwner(ownerId, generation);
    final sequence = ++_loadSequence;
    final revision = _cache.revision;
    final data = await _client
        .from('family_members')
        .select('id, name, relationship, linked_account_id, photo_path')
        .eq('owner_id', ownerId)
        .order('created_at');

    _requireOwner(ownerId, generation);
    final members = data.map(FamilyMember.fromSupabaseJson).toList();
    if (sequence == _loadSequence && revision == _cache.revision) {
      final writing = _cache.replace(_backend, ownerId, members);
      final writtenRevision = _cache.revision;
      await writing;
      _requireOwner(ownerId, generation);
      if (_cache.revision == writtenRevision) return members;
    }
    // A photo mutation or newer load completed while this response/write was
    // in flight. Do not hand its older references back to Home either.
    final latest = await _cache.read(_backend, ownerId);
    _requireOwner(ownerId, generation);
    return latest ?? members;
  }

  @override
  Future<FamilyMember?> loadMemberForOwner({
    required String ownerId,
    required String familyMemberId,
  }) async {
    final generation = _generation;
    _requireOwner(ownerId, generation);
    final data = await _client
        .from('family_members')
        .select('id, name, relationship, linked_account_id, photo_path')
        .eq('owner_id', ownerId)
        .eq('id', familyMemberId)
        .maybeSingle();

    _requireOwner(ownerId, generation);
    final member = data == null ? null : FamilyMember.fromSupabaseJson(data);
    if (member == null) {
      await _cache.remove(_backend, ownerId, familyMemberId);
    } else {
      await _cache.upsert(_backend, ownerId, member);
    }
    _requireOwner(ownerId, generation);
    return member;
  }

  @override
  Future<FamilyMember> create({
    required String ownerId,
    required String name,
    required String relationship,
  }) async {
    final generation = _generation;
    _requireOwner(ownerId, generation);
    final familyMember = FamilyMember.create(
      name: name,
      relationship: relationship,
    );
    final data = await _client
        .from('family_members')
        .insert(familyMember.toSupabaseInsert(ownerId: ownerId))
        .select('id, name, relationship, linked_account_id, photo_path')
        .single();

    _requireOwner(ownerId, generation);
    final member = FamilyMember.fromSupabaseJson(data);
    await _cache.upsert(_backend, ownerId, member);
    _requireOwner(ownerId, generation);
    return member;
  }

  @override
  Future<FamilyMember> updatePhoto({
    required String ownerId,
    required String familyMemberId,
    required String? photoPath,
    required String? expectedPhotoPath,
  }) async {
    final generation = _generation;
    if (_client.auth.currentUser?.id != ownerId) {
      throw StateError('The owner session is required.');
    }
    // Install supabase/manual/02_family_member_photo_rpc.sql manually first.
    // The RPC updates only photo_path and checks ownership and the old value.
    final data = await _client.rpc(
      'set_family_member_photo',
      params: {
        'p_family_member_id': familyMemberId,
        'p_photo_path': photoPath,
        'p_expected_photo_path': expectedPhotoPath,
      },
    );
    _requireOwner(ownerId, generation);
    final member = FamilyMember.fromSupabaseJson(
      Map<String, dynamic>.from(data as Map),
    );
    await _cache.upsert(_backend, ownerId, member);
    _requireOwner(ownerId, generation);
    return member;
  }
}
