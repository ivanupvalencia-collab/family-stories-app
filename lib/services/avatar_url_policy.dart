/// Where an avatar may be downloaded from.
///
/// `profiles.avatar_url` is written by the client and read back by every
/// family member through `get_visible_account_avatars`, so a malicious value
/// turns other people's devices into an SSRF proxy (S-5). The only URL this
/// app ever produces is the public object of the `avatars` bucket, so the
/// policy pins scheme, host and path to the backend the app is configured
/// with. With an exact host match, loopback, RFC1918 and link-local targets
/// cannot be reached at all: they would have to be spelled as the backend
/// host.
class AvatarUrlPolicy {
  const AvatarUrlPolicy._({
    this.allowedScheme,
    this.allowedHost,
    this.pathPrefix,
    this.permissive = false,
  });

  /// Accepts only URLs served by [backendUrl]'s origin, under the public
  /// `avatars` bucket.
  ///
  /// An unusable backend yields a policy that rejects everything rather than
  /// one that lets everything through.
  factory AvatarUrlPolicy.forBackend(String backendUrl) {
    final backend = Uri.tryParse(backendUrl);
    if (backend == null || !backend.hasAuthority || backend.host.isEmpty) {
      return const AvatarUrlPolicy._();
    }
    final basePath = backend.path.replaceAll(RegExp(r'/+$'), '');
    return AvatarUrlPolicy._(
      allowedScheme: backend.scheme,
      allowedHost: backend.host.toLowerCase(),
      pathPrefix: '$basePath/object/public/avatars/',
    );
  }

  /// Accepts any http(s) URL. Only for tests that serve avatars themselves.
  factory AvatarUrlPolicy.permissive() => const AvatarUrlPolicy._(
    permissive: true,
  );

  final String? allowedScheme;
  final String? allowedHost;
  final String? pathPrefix;
  final bool permissive;

  bool allows(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return false;
    if (uri.userInfo.isNotEmpty) return false;

    if (permissive) {
      return uri.scheme == 'https' || uri.scheme == 'http';
    }

    final scheme = allowedScheme;
    final host = allowedHost;
    final prefix = pathPrefix;
    if (scheme == null || host == null || prefix == null) return false;
    if (uri.scheme != scheme) return false;
    if (uri.hasPort && uri.port != _defaultPort(scheme)) return false;
    if (uri.host.toLowerCase() != host) return false;
    return uri.path.startsWith(prefix);
  }

  static int _defaultPort(String scheme) => scheme == 'https' ? 443 : 80;
}
