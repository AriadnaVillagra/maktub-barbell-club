import 'package:maktub_backend/infraestructura/http.dart';

/// A plan shared read-only with the caller: they see it, but only its creator and the club admins change it
/// (`PlanAccess.edit`). Saving and publishing answer it.
const readOnlyPlan = ErrorDeSolicitud(
  'Este plan es de otro coach y está compartido solo para ver. Copialo como plan nuevo para cambiarlo.',
  estado: 403,
);
