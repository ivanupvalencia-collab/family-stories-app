import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../models/user_profile.dart';

/// Optional capability, so existing ProfileService implementations remain valid.
abstract interface class ProfileAvatarImageSource {
  ProfileAvatarImageCache get avatarImages;
}

/// Uses Flutter's decoded-image cache; no second downloader or disk cache.
/// Each service/backend and session has its own keys, including URL revisions.
class ProfileAvatarImageCache {
  Object _scope = Object();
  final _images = <String, _ScopedAvatarImage>{};
  final _cancelPreloads = <String, VoidCallback>{};

  ImageProvider? imageFor(UserProfile profile) {
    final url = profile.avatarUrl?.trim();
    final previous = _images[profile.id];
    if (previous?.url == url && url != null && url.isNotEmpty) return previous;
    _forget(profile.id);
    if (url == null || url.isEmpty) return null;
    return _images[profile.id] = _ScopedAvatarImage(_scope, profile.id, url);
  }

  void preload(UserProfile profile) {
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
      // Image loading must never turn a successful profile load into an error.
      _cancelPreloads.remove(profile.id)?.call();
    }
  }

  void _forget(String userId) {
    _cancelPreloads.remove(userId)?.call();
    final image = _images.remove(userId);
    if (image != null) PaintingBinding.instance.imageCache.evict(image);
  }

  void clear() {
    for (final id in _images.keys.toList()) {
      _forget(id);
    }
    // Even a late completion of an old stream cannot satisfy a new session.
    _scope = Object();
  }
}

class _ScopedAvatarImage extends ImageProvider<_ScopedAvatarImage> {
  _ScopedAvatarImage(this.scope, this.userId, this.url);

  final Object scope;
  final String userId;
  final String url;

  @override
  Future<_ScopedAvatarImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _ScopedAvatarImage key,
    ImageDecoderCallback decode,
  ) {
    final network = NetworkImage(url);
    return network.loadImage(network, decode);
  }

  @override
  bool operator ==(Object other) =>
      other is _ScopedAvatarImage &&
      other.scope == scope &&
      other.userId == userId &&
      other.url == url;

  @override
  int get hashCode => Object.hash(scope, userId, url);
}
