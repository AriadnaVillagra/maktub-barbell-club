import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/auth/authenticate.dart';

Handler middleware(Handler handler) => handler.use(requireUser());
