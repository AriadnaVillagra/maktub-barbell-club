import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/auth/authenticate.dart';

// The last `use` runs first: the user is authenticated before the club is checked.
Handler middleware(Handler handler) => handler.use(requireClub()).use(requireUser());
