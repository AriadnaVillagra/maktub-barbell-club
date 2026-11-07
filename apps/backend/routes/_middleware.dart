import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Handler middleware(Handler handler) => handler.use(manejarErrores()).use(cors()).use(requestLogger());
