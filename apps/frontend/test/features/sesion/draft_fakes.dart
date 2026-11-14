import 'dart:convert';

import 'package:maktub_frontend/features/sesion/domain/session_draft_store.dart';

/// Local storage held as the JSON text a browser would keep, so a new store over the same [disk] is a reload.
class MemoryDraftStore implements SessionDraftStore {
  MemoryDraftStore([DraftDisk? disk]) : disk = disk ?? DraftDisk();

  final DraftDisk disk;

  @override
  Future<DraftSnapshot> load() async => disk.text == null
      ? const DraftSnapshot()
      : DraftSnapshot.fromJson(
          (jsonDecode(disk.text!) as Map).cast<String, dynamic>(),
        );

  @override
  Future<void> save(DraftSnapshot snapshot) async =>
      disk.text = jsonEncode(snapshot.toJson());
}

class DraftDisk {
  String? text;
}

/// A device without local storage: every access fails.
class UnavailableDraftStore implements SessionDraftStore {
  @override
  Future<DraftSnapshot> load() => Future.error(StateError('no storage'));

  @override
  Future<void> save(DraftSnapshot snapshot) =>
      Future.error(StateError('no storage'));
}
