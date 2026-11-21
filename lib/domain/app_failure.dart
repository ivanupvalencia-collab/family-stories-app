/// A-1: the typed outcome of a domain use case. Screens map this to UI
/// (snack bar, inline status) and never inspect service exceptions.
sealed class AppFailure {
  const AppFailure();

  /// The session ended mid-operation; nothing was committed.
  const factory AppFailure.sessionEnded() = SessionEnded;

  /// Network/server error: the operation can be retried.
  const factory AppFailure.unavailable() = Unavailable;

  /// The server rejected the operation (policy or validation).
  const factory AppFailure.rejected(String message) = Rejected;
}

final class SessionEnded extends AppFailure {
  const SessionEnded();
}

final class Unavailable extends AppFailure {
  const Unavailable();
}

final class Rejected extends AppFailure {
  const Rejected(this.message);
  final String message;
}
