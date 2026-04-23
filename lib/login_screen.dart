import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import 'cliente/dashboard_screen.dart';
import 'cliente/push_notifications_service.dart';
import 'session_storage.dart';

// Un StatefulWidget permite que la pantalla cambie su estado (ej. mostrar un loader)
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Controladores para capturar el texto que el usuario escribe en los campos
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Variable para controlar si mostrar el círculo de carga
  bool _isLoading = false;
  // Variable para controlar la visibilidad de la contraseña
  bool _obscurePassword = true;

  // Función asíncrona que maneja el inicio de sesión
  String _resolvePerfilPrincipal(Map<String, dynamic> data) {
    final perfilRaw = data['perfil_principal'];
    if (perfilRaw is String && perfilRaw.trim().isNotEmpty) {
      return perfilRaw.trim().toLowerCase();
    }

    final rolesRaw = data['roles'];
    if (rolesRaw is List) {
      final normalized = rolesRaw
          .whereType<String>()
          .map((role) => role.trim().toLowerCase())
          .toSet();
      if (normalized.contains('cliente')) {
        return 'cliente';
      }
      if (normalized.contains('tecnico')) {
        return 'tecnico';
      }
      if (normalized.contains('taller')) {
        return 'taller';
      }
    }

    return 'cliente';
  }

  Future<void> _login() async {
    // 1. Mostrar estado de carga
    setState(() {
      _isLoading = true;
    });

    try {
      // 2. Definir la URL de tu backend FastAPI desde flutter_dotenv
      final baseUrl = dotenv.env['API_URL'] ?? 'http://10.0.2.2:8000/api/v1';
      final url = Uri.parse('$baseUrl/auth/login');

      // 3. Hacer la petición POST al backend enviando JSON
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'correo': _emailController.text,
              'password': _passwordController.text,
              'canal':
                  'mobile', // El backend distingue si el login viene de web o movil
            }),
          )
          .timeout(
            const Duration(seconds: 30),
          ); // Agregamos un timeout aquí también

      // 4. Evaluar la respuesta del servidor
      if (response.statusCode == 200) {
        // Inicio de sesión exitoso
        final data = json.decode(response.body);
        final String token = data['access_token'];
        final String nombreUsuario = data['nombre'];
        final String correoUsuario = data['correo'];
        final String perfil = _resolvePerfilPrincipal(data);

        await SessionStorage.saveSession(
          token: token,
          nombre: nombreUsuario,
          correo: correoUsuario,
          perfil: perfil,
        );

        // Registra token push lo antes posible para no perder eventos tempranos.
        try {
          await PushNotificationsService.instance.initForClient(
            authToken: token,
            onForegroundNotification: null,
          );
        } catch (_) {
          // No bloqueamos el login si push falla; Dashboard reintentará inicializar.
        }

        // Mostrar mensaje de éxito
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Inicio de sesión exitoso!'),
              backgroundColor: Colors.green,
            ),
          );

          // Navegar al Panel Principal (Dashboard) pasando los datos
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => DashboardScreen(
                nombre: nombreUsuario,
                correo: correoUsuario,
                token: token,
                perfil: perfil,
              ),
            ),
            (route) =>
                false, // Borra el historial (No se puede hacer "atrás" y regresar al login)
          );
        }
      } else {
        // Credenciales incorrectas u otro error del backend
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Credenciales incorrectas o error en el servidor'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      // Error de red (el backend no está corriendo, etc.)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de conexión: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // 5. Ocultar el estado de carga sin importar qué pasó
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold proporciona la estructura básica visual de una app (Appbar, body, etc)
    return Scaffold(
      backgroundColor: Colors.grey[100], // Fondo claro similar a la web
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            // Contenedor que imita una tarjeta de login de un frontend web
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize:
                    MainAxisSize.min, // Ocupar solo el espacio necesario
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Bienvenido',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueAccent,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Campo de Correo / Username
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Correo Electrónico',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Campo de Contraseña
                  TextField(
                    controller: _passwordController,
                    obscureText:
                        _obscurePassword, // Ocultar o mostrar el texto ingresado basado en la variable
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Botón de Inicio de Sesión o Animación de carga
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                          onPressed: _login,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'INICIAR SESIÓN',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Liberar los controladores de memoria cuando la pantalla se destruya
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
