class InvitationLink {
  InvitationLink._();

  static const _scheme = 'https';
  static const _host = 'familystories.app';
  static final RegExp _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{32,256}$');

  static Uri build(String token) {
    if (!_tokenPattern.hasMatch(token)) {
      throw ArgumentError('Invalid invitation token');
    }

    return Uri(
      scheme: _scheme,
      host: _host,
      pathSegments: const ['invite'] + [token],
    );
  }

  static String? tokenFrom(Uri uri) {
    if (uri.scheme != _scheme ||
        uri.host != _host ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.length != 2 ||
        uri.pathSegments.first != 'invite') {
      return null;
    }

    final token = uri.pathSegments.last;
    return _tokenPattern.hasMatch(token) ? token : null;
  }
}
