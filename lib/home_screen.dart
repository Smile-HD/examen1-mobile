import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50], // Fondo general
      appBar: AppBar(
        title: const Text('Sistema de Talleres', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        actions: [
          // Botón de Registrarse en el AppBar
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RegisterScreen()),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Registrarse', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          // Botón de Iniciar Sesión en el AppBar
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.blueAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Iniciar Sesión'),
          ),
          const SizedBox(width: 16), // Margen a la derecha
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.car_repair, size: 100, color: Colors.blueAccent),
              const SizedBox(height: 24),
              const Text(
                '¡Bienvenido a la Plataforma!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.blueAccent),
              ),
              const SizedBox(height: 16),
              const Text(
                'Simplifica el manejo de tu taller con herramientas pensadas para ti. Aún no tienes cuenta? Empieza hoy mismo.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black87),
              ),
              const SizedBox(height: 48),
              // Botón central principal para la acción más importante (registro)
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const RegisterScreen()),
                  );
                },
                icon: const Icon(Icons.person_add),
                label: const Text('Comienza ahora, es gratis', style: TextStyle(fontSize: 18)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
