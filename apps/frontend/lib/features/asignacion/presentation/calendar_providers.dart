import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/red/api_providers.dart';
import '../data/http_calendar_repository.dart';
import '../domain/calendar_repository.dart';

final calendarRepositoryProvider = Provider<CalendarRepository>(
  (ref) => HttpCalendarRepository(ref.watch(clienteApiProvider)),
);
