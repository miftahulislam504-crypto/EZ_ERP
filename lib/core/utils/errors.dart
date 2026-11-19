import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns backend errors into messages a business user can act on.
String friendlyError(Object e) {
  if (e is PostgrestException) {
    switch (e.code) {
      case '23505':
        return 'This record already exists. Use a different value.';
      case '23503':
        return 'This record is linked to other data, so it cannot be changed or removed.';
      case '42501':
        return 'You do not have permission to perform this action.';
      case '23514':
        return 'One of the values is not allowed. Please review the form.';
    }
    return e.message.isEmpty ? 'The request could not be completed.' : e.message;
  }
  if (e is AuthException) return e.message;
  return 'Something went wrong. Check your connection and try again.';
}
