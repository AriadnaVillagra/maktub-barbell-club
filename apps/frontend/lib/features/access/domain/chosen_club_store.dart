import 'package:maktub_core/maktub_core.dart';

/// The club a user picked to work in, kept on the device ([Me.chosenClub]).
abstract interface class ChosenClubStore {
  /// The club [userId] picked on this device, or null when they never picked one (or it cannot be read).
  Future<Club?> read(String userId);

  /// Keeps [club] as the one [userId] works in; null goes back to the default.
  Future<void> write(String userId, Club? club);
}
