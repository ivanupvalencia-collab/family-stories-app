import 'package:supabase_flutter/supabase_flutter.dart';

/// A-2: the single classification of "this row is not visible to you"
/// PostgREST denials, previously duplicated between a widget and a
/// service. Callers treat it as a valid empty result, never as an error.
bool isPostgrestDenied(Object error) =>
    error is PostgrestException &&
    (error.code == '42501' || error.code == 'PGRST301');
