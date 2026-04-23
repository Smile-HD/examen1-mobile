import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // Controladores para el registro del cliente
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _correoController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _telefonoController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  String? _validateInput({
    required String nombre,
    required String correo,
    required String password,
  }) {
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    final hasLetter = password.contains(RegExp(r'[A-Za-z]'));
    final hasDigit = password.contains(RegExp(r'\d'));

    if (nombre.isEmpty || correo.isEmpty || password.isEmpty) {
      return 'Por favor, llena los campos requeridos.';
    }
    if (nombre.length < 2) {
      return 'El nombre debe tener al menos 2 caracteres.';
    }
    if (!emailRegex.hasMatch(correo)) {
      return 'Ingresa un correo valido.';
    }
    if (password.length < 8 || !hasLetter || !hasDigit) {
      return 'La contraseña debe tener 8+ caracteres, letras y numeros.';
    }

    return null;
  }

  String _parseBackendError(String responseBody) {
    try {
      final decoded = json.decode(responseBody);

      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String && detail.isNotEmpty) {
          return detail;
        }
        if (detail is List && detail.isNotEmpty) {
          final messages = detail
              .map((item) {
                if (item is Map<String, dynamic>) {
                  final msg = item['msg'];
                  if (msg is String && msg.isNotEmpty) {
                    return msg;
                  }
                }
                return null;
              })
              .whereType<String>()
              .toList();

          if (messages.isNotEmpty) {
            return messages.join(' | ');
          }
        }

        final mensaje = decoded['mensaje'];
        if (mensaje is String && mensaje.isNotEmpty) {
          return mensaje;
        }
      }
    } catch (_) {
      // Si la respuesta no es JSON, devolvemos un mensaje generico.
    }

    return 'No se pudo completar el registro.';
  }

  Future<void> _register() async {
    final nombre = _nombreController.text.trim();
    final correo = _correoController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final telefono = _telefonoController.text.trim();

    final validationError = _validateInput(
      nombre: nombre,
      correo: correo,
      password: password,
    );

    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validationError),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final url = Uri.parse(
        Uri.parse("${dotenv.env['API_URL']}/usuarios/registro").toString(),
      );

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'nombre': nombre,
              'correo': correo,
              'password': password,
              'telefono': telefono.isEmpty ? null : telefono,
              'tipo_usuario': 'cliente',
            }),
          )
          .timeout(
            const Duration(seconds: 30),
          ); // Timeout para evitar carga infinita

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Registro exitoso!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      } else {
        final errorMessage = _parseBackendError(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error ${response.statusCode}: $errorMessage'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de red: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Registro de Cliente'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Crea una cuenta',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueAccent,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _nombreController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre *',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _correoController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Correo Electrónico *',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Contraseña *',
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
                  const SizedBox(height: 16),
                  TextField(
                    controller: _telefonoController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono',
                      prefixIcon: Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                          onPressed: _register,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'REGISTRARSE',
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
    _nombreController.dispose();
    _correoController.dispose();
    _passwordController.dispose();
    _telefonoController.dispose();
    super.dispose();
  }
}
