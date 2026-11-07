import 'cable.dart';
import 'json.dart';

/// Cómo puede ingresar un usuario. Un mismo usuario puede tener los dos (F1, "Identidad").
enum MetodoIngreso implements ConCable {
  google('google'),
  contrasena('contrasena');

  const MetodoIngreso(this.cable);
  @override
  final String cable;

  static MetodoIngreso deCable(Object? v) => desdeCable(values, v, 'Método de ingreso');
}

/// Forma canónica de un email: el email identifica al usuario, así que se compara siempre así.
String normalizarEmail(String email) => email.trim().toLowerCase();

/// Una persona con login propio (docs/diseno.md, "Club, usuarios y roles"). Es global: no tiene `clubId`.
///
/// Es el contrato que ve la app. Las credenciales (sub de Google, hash de la contraseña) viven solo en
/// el backend y nunca viajan; acá solo se informa con qué [metodos] puede ingresar.
class Usuario {
  Usuario({
    required this.id,
    required String email,
    required this.nombre,
    required this.emailVerificado,
    required this.clubPersonalId,
    this.metodos = const {},
    this.esAdminPlataforma = false,
  }) : email = normalizarEmail(email);

  final String id;

  /// Único y normalizado (ver [normalizarEmail]).
  final String email;
  final String nombre;
  final bool emailVerificado;

  /// Club personal creado con el usuario ("mi entrenamiento").
  final String clubPersonalId;
  final Set<MetodoIngreso> metodos;

  /// Mantiene lo de plataforma (catálogo base, biblioteca de planes). Se asigna solo por script.
  final bool esAdminPlataforma;

  factory Usuario.fromJson(Json j) => Usuario(
        id: '${j['id']}',
        email: '${j['email']}',
        nombre: '${j['nombre']}',
        emailVerificado: j['emailVerificado'] == true,
        clubPersonalId: '${j['clubPersonalId']}',
        metodos: {for (final m in (j['metodos'] as List? ?? const [])) MetodoIngreso.deCable(m)},
        esAdminPlataforma: j['esAdminPlataforma'] == true,
      );

  Json toJson() => {
        'id': id,
        'email': email,
        'nombre': nombre,
        'emailVerificado': emailVerificado,
        'clubPersonalId': clubPersonalId,
        'metodos': [for (final m in MetodoIngreso.values) if (metodos.contains(m)) m.cable],
        'esAdminPlataforma': esAdminPlataforma,
      };
}
