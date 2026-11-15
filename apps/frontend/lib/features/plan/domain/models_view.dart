/// How the editor shows the week models, like a folder's views.
enum ModelsView {
  /// Every day in full, with its blocks and exercises.
  detailed,

  /// One row per day with a tag per block; a day opens in full when tapped.
  compact,
}

/// Where the device remembers the chosen [ModelsView].
abstract interface class ModelsViewStore {
  /// The saved view; null when there is none or it cannot be read.
  Future<ModelsView?> load();

  Future<void> save(ModelsView view);
}
