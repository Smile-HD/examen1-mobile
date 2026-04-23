import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';

class VehicleRegistrationScreen extends StatefulWidget {
  // Necesitamos el token JWT del dueño para vincular el vehículo
  final String token;

  const VehicleRegistrationScreen({super.key, required this.token});

  @override
  State<VehicleRegistrationScreen> createState() => _VehicleRegistrationScreenState();
}

class _VehicleRegistrationScreenState extends State<VehicleRegistrationScreen> {
  // Controladores de texto para los campos del vehículo
  final TextEditingController _placaController = TextEditingController();
  final TextEditingController _marcaController = TextEditingController();
  final TextEditingController _modeloController = TextEditingController();
  final TextEditingController _anioController = TextEditingController();
  final TextEditingController _tipoController = TextEditingController();

  bool _isLoading = false;

  Future<void> _registerVehicle() async {
    // Validar que los campos requiridos tengan datos
    if (_placaController.text.isEmpty ||
        _marcaController.text.isEmpty ||
        _modeloController.text.isEmpty ||
        _anioController.text.isEmpty ||
        _tipoController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Llena todos los campos requeridos.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final baseUrl = dotenv.env['API_URL'] ?? 'http://10.0.2.2:8000/api/v1';
      final url = Uri.parse('$baseUrl/vehiculos/registro');

      // Petición al backend backend
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          // Envío del token JWT en formato Bearer (Requerido por FastAPI: AuthenticatedUser)
          'Authorization': 'Bearer ${widget.token}',
        },
        body: json.encode({
          // El regex backend pide placa en formato [A-Z0-9-], ejemplo: 2548HGT
          'placa': _placaController.text.toUpperCase().replaceAll(' ', ''), 
          'marca': _marcaController.text,
          'modelo': _modeloController.text,
          'anio': int.tryParse(_anioController.text) ?? 2020, // Parsear string a entero
          'tipo': _tipoController.text, // ej: "Sedan", "Vagoneta", "Moto"
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Vehículo registrado correctamente!'),
              backgroundColor: Colors.green,
            ),
          );
          // Retornar al dashboard tras éxito
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Falló el registro: ${response.body}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de conexión o Timeout: $e'),
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
        title: const Text('Añadir Vehículo'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Ingresa los datos',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _placaController,
                    // Convierte lo que el usuario pisa a Mayúsculas por estándar
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Placa (Ej: 2345ABC)',
                      prefixIcon: Icon(Icons.pin),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _marcaController,
                    decoration: const InputDecoration(
                      labelText: 'Marca (Ej: Toyota)',
                      prefixIcon: Icon(Icons.car_rental),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _modeloController,
                    decoration: const InputDecoration(
                      labelText: 'Modelo (Ej: Corolla)',
                      prefixIcon: Icon(Icons.abc),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _anioController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Año (Ej: 2018)',
                      prefixIcon: Icon(Icons.date_range),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _tipoController,
                    decoration: const InputDecoration(
                      labelText: 'Tipo (Ej: Sedán, Vagoneta)',
                      prefixIcon: Icon(Icons.category),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                          onPressed: _registerVehicle,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('GUARDAR VEHÍCULO', style: TextStyle(fontSize: 16)),
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
    _placaController.dispose();
    _marcaController.dispose();
    _modeloController.dispose();
    _anioController.dispose();
    _tipoController.dispose();
    super.dispose();
  }
}
