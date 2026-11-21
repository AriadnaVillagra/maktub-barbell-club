/// Where the device remembers which block cards of the session screen are collapsed, by block index.
abstract interface class CollapsedBlocksStore {
  /// The saved indexes; empty when there are none or they cannot be read.
  Future<Set<int>> load();

  Future<void> save(Set<int> collapsed);
}
