import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/cliente_api.dart';
import '../data/seguimiento_remote_data_source.dart';
import '../data/seguimiento_repository_impl.dart';
import '../domain/repositories/seguimiento_repository.dart';
import '../domain/usecases/construir_sesion.dart';
import '../domain/usecases/guardar_sesion.dart';
import '../domain/usecases/obtener_seguimiento.dart';

// Inyección de dependencias del feature. En tests se reemplaza
// `seguimientoRepositoryProvider` con `overrideWithValue`.

final seguimientoRepositoryProvider = Provider<SeguimientoRepository>(
  (ref) => SeguimientoRepositoryImpl(SeguimientoRemoteDataSource(ref.watch(clienteApiProvider))),
);

final obtenerSeguimientoProvider = Provider((ref) => ObtenerSeguimiento(ref.watch(seguimientoRepositoryProvider)));

final guardarSesionProvider = Provider((ref) => GuardarSesion(ref.watch(seguimientoRepositoryProvider)));

final construirSesionProvider = Provider((_) => const ConstruirSesion());

/// Barra y discos disponibles. Pendiente: que salga de la base de datos.
final equipoProvider = Provider<Equipo>((_) => Equipo.estandar);

/// Reloj inyectable para poder fijar "hoy" en tests.
final hoyProvider = Provider<DateTime Function()>((_) => hoy);
