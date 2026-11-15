import '../red/cliente_api.dart';

/// One saved answer of the server and when it was saved.
class LocalCopy {
  const LocalCopy({required this.savedAt, required this.data});

  final DateTime savedAt;

  /// What [LocalCopyStore.write] got: JSON-encodable, possibly null.
  final Object? data;
}

/// The device's copy of what the day's screens read (E7.15), so they open without signal. Every access is guarded:
/// without storage nothing is kept and reads find nothing.
abstract interface class LocalCopyStore {
  /// The copy saved under [key], or null when there is none (or it cannot be read).
  Future<LocalCopy?> read(String key);

  /// Saves [data] under [key], stamped now.
  Future<void> write(String key, Object? data);

  /// Every key saved, starting with [prefix].
  Future<List<String>> keys(String prefix);

  /// Drops every copy saved before [before].
  Future<void> prune(DateTime before);
}

/// Told whether each read came from the server or from the copy, so the screen can say it shows saved data.
abstract interface class LocalCopyReporter {
  void servedFresh();
  void servedFromCopy(DateTime savedAt);
}

/// A read without signal that has nothing saved to show. It is an [ErrorDeApi] so the screens show its message.
class NoLocalCopy extends ErrorDeApi {
  const NoLocalCopy([super.mensaje = defaultMessage]);

  static const defaultMessage =
      'Sin señal y sin datos guardados para mostrar esto. Se cargan cuando vuelva la señal.';
}

/// Whether a failed read means the server could not be reached, so the copy is worth showing: no connection, the
/// server down or starting, or too busy. A refusal on purpose (any other 4xx) is the server's answer and stands.
bool isOfflineError(Object error) {
  if (error is! ErrorDeApi || error is NoLocalCopy) return false;
  final status = error.estado;
  return status == null || status >= 500 || status == 408 || status == 429;
}

/// Reads through the network and keeps a copy; without signal answers with the copy.
class LocalCopyReads {
  const LocalCopyReads(this.store, this.reporter);

  final LocalCopyStore store;
  final LocalCopyReporter reporter;

  /// Fetches with [fetch] and saves the result under [key] with [encode]. When the server cannot be reached, decodes
  /// the copy with [decode], or throws [NoLocalCopy] with [missing] when there is none.
  Future<T> read<T>(
    String key,
    Future<T> Function() fetch, {
    required Object? Function(T) encode,
    required T Function(Object?) decode,
    String missing = NoLocalCopy.defaultMessage,
  }) async {
    final T value;
    try {
      value = await fetch();
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      return _fromCopy(key, decode, missing);
    }
    reporter.servedFresh();
    await save(key, value, encode);
    return value;
  }

  Future<T> _fromCopy<T>(
    String key,
    T Function(Object?) decode,
    String missing,
  ) async {
    final copy = await store.read(key);
    if (copy == null) throw NoLocalCopy(missing);
    final T value;
    try {
      value = decode(copy.data);
    } catch (_) {
      throw NoLocalCopy(missing); // a copy from an older version that no longer reads
    }
    reporter.servedFromCopy(copy.savedAt);
    return value;
  }

  /// Saves [value] without reading anything; a value that does not encode is not kept.
  Future<void> save<T>(String key, T value, Object? Function(T) encode) async {
    final Object? data;
    try {
      data = encode(value);
    } catch (_) {
      return;
    }
    await store.write(key, data);
  }
}

/// Keys of the copy are paths of parts, each escaped so a part never splits.
String copyKey(List<Object> parts) =>
    parts.map((p) => Uri.encodeComponent('$p')).join('/');
