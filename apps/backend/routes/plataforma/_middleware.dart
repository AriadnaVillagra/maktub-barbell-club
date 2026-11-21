import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/platform_context/platform_context.dart';
import 'package:maktub_backend/features/auth/authenticate.dart';

// The last `use` runs first: the user is authenticated before the platform admin flag is read.
Handler middleware(Handler handler) => handler.use(requirePlatform()).use(requireUser());
