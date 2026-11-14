import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/offline/local_copy_providers.dart';
import '../../../core/red/api_providers.dart';
import '../data/cached_calendar_repository.dart';
import '../data/http_calendar_repository.dart';
import '../domain/calendar_repository.dart';

/// The calendar straight from the server. Tests replace it to keep the device's copy in between.
final remoteCalendarRepositoryProvider = Provider<CalendarRepository>(
  (ref) => HttpCalendarRepository(ref.watch(clienteApiProvider)),
);

/// The calendar with the device's copy as fallback without signal (E7.15).
final calendarRepositoryProvider = Provider<CalendarRepository>(
  (ref) => CachedCalendarRepository(
    ref.watch(remoteCalendarRepositoryProvider),
    ref.watch(localCopyReadsProvider),
  ),
);
