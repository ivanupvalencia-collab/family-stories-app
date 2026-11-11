class InvitationLink {
  InvitationLink._();

  static const _scheme = 'familystories';
  static const _host = 'invite';
  static final RegExp _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{32,256}$');

  static Uri build(String token) {
    if (!_tokenPattern.hasMatch(token)) {
      throw ArgumentError('Invalid invitation token');
    }

    return Uri(
      scheme: _scheme,
      host: _host,
      pathSegments: [token],
    );
  }

  static String? tokenFrom(Uri uri) {
    if (uri.scheme != _scheme ||
        uri.host != _host ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.length != 1) {
      return null;
    }

    final token = uri.pathSegments.single;
    return _tokenPattern.hasMatch(token) ? token : null;
  }

  /// Whether [raw] is a bare invitation token.
  static bool isValidToken(String raw) => _tokenPattern.hasMatch(raw.trim());

  /// Extracts the token from whatever the user pasted.
  ///
  /// The custom `familystories://` scheme is not linkified by most messengers,
  /// so the invitee usually copies the whole URI into the code field instead
  /// of tapping it. Accept both forms so a paste of the full link works.
  static String? tokenFromInput(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (_tokenPattern.hasMatch(trimmed)) return trimmed;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    return tokenFrom(uri);
  }
}
