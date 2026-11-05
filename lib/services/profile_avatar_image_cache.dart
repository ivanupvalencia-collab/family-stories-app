import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';
import 'remote_family_photo_disk_cache.dart';

abstract interface class ProfileAvatarImageSource {
  ProfileAvatarImageCache get avatarImages;
}

/// Own and visible-account avatars share Flutter's decoded cache and the
/// existing private photo store for bytes and authorized metadata.
class ProfileAvatarImageCache extends ChangeNotifier {
  ProfileAvatarImageCache({
    SupabaseClient? client,
    RemoteFamilyPhotoDiskCache? diskCache,
    String? backend,
    String? owner,
  }) : _client = client,
       _disk =
           diskCache ??
           (client == null
               ? null
               : RemoteFamilyPhotoDiskCache(
                   directoryName: 'remote_account_avatars_v1',
                 )),
       _backend = backend ?? client?.storage.url ?? '',
       _owner = owner ?? client?.auth.currentUser?.id {
    _subscription = client?.auth.onAuthStateChange.listen((event) {
      syncSession();
      if (event.event == AuthChangeEvent.signedOut) clear();
      notifyListeners();
    });
  }
  static final _shared = Expando<ProfileAvatarImageCache>();
  static ProfileAvatarImageCache forClient(SupabaseClient client) =>
      _shared[client] ??= ProfileAvatarImageCache(client: client);

  final SupabaseClient? _client;
  final RemoteFamilyPhotoDiskCache? _disk;
  final String _backend;
  String? _owner;
  StreamSubscription<AuthState>? _subscription;
  Object _scope = Object();
  final _profiles = <String, UserProfile>{};
  final _images = <String, _ScopedAvatarImage>{};
  final _cancelPreloads = <String, VoidCallback>{};
  final _pendingBytes = <String, Future<Uint8List>>{};
  final _bytes = <String, Uint8List>{};
  int _byteCount = 0;

  void syncSession() {
    final client = _client;
    if (client == null || _owner == client.auth.currentUser?.id) return;
    final previous = _owner;
    clear();
    _owner = client.auth.currentUser?.id;
    if (previous != null) unawaited(_disk?.clearOwner(_backend, previous));
  }

  bool _valid(Object scope, String? owner) {
    syncSession();
    return identical(scope, _scope) && owner == _owner;
  }

  UserProfile? cachedProfile(String id) {
    syncSession();
    return _profiles[id];
  }

  Future<UserProfile?> readProfile(String id) async {
    syncSession();
    if (_profiles.containsKey(id)) return _profiles[id];
    final scope = _scope;
    final owner = _owner;
    if (owner == null || _disk == null) return null;
    try {
      final data = await _disk.readEntry(
        _backend,
        owner,
        'profile:$id',
        image: false,
      );
      if (data == null || !_valid(scope, owner)) return null;
      final profile = UserProfile.fromJson(jsonDecode(utf8.decode(data)));
      if (profile.id != id) return null;
      if (_profiles[id] case final current?) return current;
      _profiles[id] = profile;
      preload(profile);
      return profile;
    } catch (_) {
      return null;
    }
  }

  Future<void> remember(UserProfile profile) async {
    syncSession();
    final scope = _scope;
    final owner = _owner;
    final old = _profiles[profile.id];
    _profiles[profile.id] = profile;
    preload(profile);
    if (owner != null && _disk != null) {
      await _disk.writeEntry(
        _backend,
        owner,
        'profile:${profile.id}',
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'id': profile.id,
              'name': profile.name,
              'avatar_key': profile.avatarKey,
              'avatar_url': profile.avatarUrl,
              'created_at': profile.createdAt?.toIso8601String(),
            }),
          ),
        ),
        stillValid: () =>
            _valid(scope, owner) && identical(_profiles[profile.id], profile),
      );
    }
    if (_valid(scope, owner) &&
        (old?.name != profile.name ||
            old?.avatarKey != profile.avatarKey ||
            old?.avatarUrl != profile.avatarUrl)) {
      notifyListeners();
    }
  }

  Future<void> forgetProfile(String id) async {
    syncSession();
    final owner = _owner;
    _profiles.remove(id);
    _forget(id);
    if (owner != null) await _disk?.removeEntry(_backend, owner, 'profile:$id');
    notifyListeners();
  }

  ImageProvider? imageFor(UserProfile profile) {
    syncSession();
    final url = profile.avatarUrl?.trim();
    final previous = _images[profile.id];
    if (previous?.url == url && url != null && url.isNotEmpty) return previous;
    _forget(profile.id);
    if (url == null || url.isEmpty) return null;
    final scope = _scope;
    final owner = _owner;
    return _images[profile.id] = _ScopedAvatarImage(
      scope,
      profile.id,
      url,
      () => _loadBytes(profile.id, url, scope, owner),
    );
  }

  String _key(String id, String url) => 'avatar:$id:$url';
  Future<Uint8List> _loadBytes(
    String id,
    String url,
    Object scope,
    String? owner,
  ) {
    final key = _key(id, url);
    if (!_valid(scope, owner)) {
      return Future.error(StateError('Avatar session changed'));
    }
    if (_bytes[key] case final bytes?) return Future.value(bytes);
    return _pendingBytes[key] ??= () async {
      try {
        bool valid() => _valid(scope, owner) && _images[id]?.url == url;
        Uint8List? bytes;
        if (owner != null) bytes = await _disk?.readEntry(_backend, owner, key);
        if (!valid()) throw StateError('Avatar was invalidated');
        if (bytes == null) {
          final http = HttpClient();
          try {
            final response = await (await http.getUrl(Uri.parse(url))).close();
            if (response.statusCode != 200) {
              throw NetworkImageLoadException(
                statusCode: response.statusCode,
                uri: Uri.parse(url),
              );
            }
            final builder = BytesBuilder(copy: false);
            await for (final chunk in response) {
              builder.add(chunk);
              if (builder.length > 10 * 1024 * 1024) {
                throw const FormatException('Avatar too large');
              }
            }
            bytes = builder.takeBytes();
          } finally {
            http.close(force: true);
          }
          await RemoteFamilyPhotoDiskCache.validate(bytes);
          if (!valid()) throw StateError('Avatar was invalidated');
          if (owner != null) {
            await _disk?.writeEntry(
              _backend,
              owner,
              key,
              bytes,
              stillValid: valid,
            );
          }
        }
        if (!valid()) throw StateError('Avatar was invalidated');
        _bytes[key] = bytes;
        _byteCount += bytes.length;
        while (_byteCount > 24 * 1024 * 1024 && _bytes.isNotEmpty) {
          _byteCount -= _bytes.remove(_bytes.keys.first)!.length;
        }
        return bytes;
      } finally {
        if (identical(scope, _scope)) _pendingBytes.remove(key);
      }
    }();
  }

  void preload(UserProfile profile) {
    if (!_hasBinding) return;
    final image = imageFor(profile);
    if (image == null || _cancelPreloads.containsKey(profile.id)) return;
    try {
      final stream = image.resolve(ImageConfiguration.empty);
      late ImageStreamListener listener;
      void cancel() {
        stream.removeListener(listener);
        _cancelPreloads.remove(profile.id);
      }

      listener = ImageStreamListener(
        (info, synchronous) {
          cancel();
          info.dispose();
        },
        onError: (Object error, StackTrace? stack) {
          cancel();
          PaintingBinding.instance.imageCache.evict(image);
        },
      );
      _cancelPreloads[profile.id] = cancel;
      stream.addListener(listener);
    } catch (_) {
      _cancelPreloads.remove(profile.id)?.call();
    }
  }

  void _forget(String id) {
    _cancelPreloads.remove(id)?.call();
    final image = _images.remove(id);
    if (image == null) return;
    if (_hasBinding) PaintingBinding.instance.imageCache.evict(image);
    final key = _key(id, image.url);
    _byteCount -= _bytes.remove(key)?.length ?? 0;
    final owner = _owner;
    if (owner != null) unawaited(_disk?.removeEntry(_backend, owner, key));
  }

  /// Route disposal keeps disk; changing account purges its private namespace.
  void clear() {
    for (final cancel in _cancelPreloads.values.toList()) {
      cancel();
    }
    for (final image in _images.values) {
      if (_hasBinding) PaintingBinding.instance.imageCache.evict(image);
    }
    _images.clear();
    _profiles.clear();
    _pendingBytes.clear();
    _bytes.clear();
    _byteCount = 0;
    _scope = Object();
  }

  bool get _hasBinding {
    try {
      PaintingBinding.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    clear();
    super.dispose();
  }
}

class _ScopedAvatarImage extends ImageProvider<_ScopedAvatarImage> {
  _ScopedAvatarImage(this.scope, this.userId, this.url, this.bytes);
  final Object scope;
  final String userId, url;
  final Future<Uint8List> Function() bytes;
  @override
  Future<_ScopedAvatarImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
    _ScopedAvatarImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: () async {
      try {
        return await decode(
          await ui.ImmutableBuffer.fromUint8List(await bytes()),
        );
      } catch (_) {
        scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
        rethrow;
      }
    }(),
    scale: 1,
  );
  @override
  bool operator ==(Object other) =>
      other is _ScopedAvatarImage &&
      other.scope == scope &&
      other.userId == userId &&
      other.url == url;
  @override
  int get hashCode => Object.hash(scope, userId, url);
}
