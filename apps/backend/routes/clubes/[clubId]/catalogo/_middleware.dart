import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_core/maktub_core.dart';

Handler middleware(Handler handler) => handler.use(requireAction(Accion.verCatalogoYPlanes));
