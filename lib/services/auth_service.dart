import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _googleWebClientId =
    '922531861898-dv4srvf7daasfmiheuk2e5b2fdcse2pt.apps.googleusercontent.com';

class AuthUser {
  const AuthUser({required this.id, required this.email});

  final String id;
  final String email;
}

abstract class AuthService {
  AuthUser? get currentUser;

  Stream<AuthUser?> get authStateChanges;

  Future<AuthUser> signInWithGoogle();

  Future<void> signOut();
}

class GoogleSignInCancelledException implements Exception {
  const GoogleSignInCancelledException();
}

class SupabaseGoogleAuthService implements AuthService {
  SupabaseGoogleAuthService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static final Future<void> _googleInitialization = GoogleSignIn.instance
      .initialize(serverClientId: _googleWebClientId);

  @override
  AuthUser? get currentUser => _toAuthUser(_client.auth.currentUser);

  @override
  Stream<AuthUser?> get authStateChanges => _client.auth.onAuthStateChange.map(
    (state) => _toAuthUser(state.session?.user),
  );

  @override
  Future<AuthUser> signInWithGoogle() async {
    late final GoogleSignInAccount googleAccount;
    try {
      await _googleInitialization;
      googleAccount = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted) {
        throw const GoogleSignInCancelledException();
      }
      rethrow;
    }

    final idToken = googleAccount.authentication.idToken;
    if (idToken == null) {
      throw const AuthException(
        'Google no ha proporcionado un token de identidad.',
      );
    }

    final response = await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
    final user = response.user;
    if (user == null) {
      throw const AuthException('No se ha podido recuperar el usuario.');
    }

    return _toAuthUser(user)!;
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();

    try {
      await _googleInitialization;
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // The Supabase session is already closed. Google sign-out is best effort.
    }
  }

  static AuthUser? _toAuthUser(User? user) {
    if (user == null) {
      return null;
    }

    return AuthUser(id: user.id, email: user.email ?? '');
  }
}
