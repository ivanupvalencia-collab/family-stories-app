import 'package:family_stories_app/domain/postgrest_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('isPostgrestDenied classifies visibility denials only (A-2)', () {
    // The two codes the backend uses when a row is not visible to the
    // caller: RLS rejection and the PostgREST alias.
    expect(
      isPostgrestDenied(
        PostgrestException(message: 'denied', code: '42501'),
      ),
      isTrue,
    );
    expect(
      isPostgrestDenied(
        PostgrestException(message: 'denied', code: 'PGRST301'),
      ),
      isTrue,
    );
    // Anything else — a missing column, a plain error — is not a denial.
    expect(
      isPostgrestDenied(PostgrestException(message: 'x', code: '42703')),
      isFalse,
    );
    expect(isPostgrestDenied(StateError('x')), isFalse);
  });
}
