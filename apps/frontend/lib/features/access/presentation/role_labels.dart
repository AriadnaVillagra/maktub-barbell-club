import 'package:maktub_core/maktub_core.dart';

String roleLabel(Rol r) => switch (r) {
  Rol.coach => 'Coach',
  Rol.atleta => 'Atleta',
  Rol.adminClub => 'Admin del club',
};
