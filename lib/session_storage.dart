import 'package:shared_preferences/shared_preferences.dart';

class PersistedSession {
  final String token;
  final String nombre;
  final String correo;
  final String perfil;

  const PersistedSession({
    required this.token,
    required this.nombre,
    required this.correo,
    required this.perfil,
  });
}

class SessionStorage {
  static const String _keyToken = 'session.token';
  static const String _keyNombre = 'session.nombre';
  static const String _keyCorreo = 'session.correo';
  static const String _keyPerfil = 'session.perfil';

  static Future<void> saveSession({
    required String token,
    required String nombre,
    required String correo,
    required String perfil,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
    await prefs.setString(_keyNombre, nombre);
    await prefs.setString(_keyCorreo, correo);
    await prefs.setString(_keyPerfil, perfil);
  }

  static Future<PersistedSession?> loadSession() async {
    final prefs = await SharedPreferences.getInstance();

    final token = prefs.getString(_keyToken);
    final nombre = prefs.getString(_keyNombre);
    final correo = prefs.getString(_keyCorreo);
    final perfil = prefs.getString(_keyPerfil);

    if (token == null || nombre == null || correo == null || perfil == null) {
      return null;
    }

    if (token.trim().isEmpty) {
      return null;
    }

    return PersistedSession(
      token: token,
      nombre: nombre,
      correo: correo,
      perfil: perfil,
    );
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyNombre);
    await prefs.remove(_keyCorreo);
    await prefs.remove(_keyPerfil);
  }
}
