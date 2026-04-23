// Importamos convert para serializar/deserializar JSON.
import 'dart:convert';
import 'dart:io';

// Importamos Material para widgets de interfaz móvil.
import 'package:flutter/material.dart';

// Importamos geolocator para obtener ubicación del dispositivo en tiempo real.
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

// Importamos http para consumir el endpoint de FastAPI.
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'vehicle_registration_screen.dart';
import 'workshop_selection_screen.dart';

// Pantalla principal para reportar emergencias.
class IncidentReportScreen extends StatefulWidget {
  // Token JWT del usuario autenticado.
  final String token;
  final VoidCallback? onRequestSubmitted;

  const IncidentReportScreen({
    super.key,
    required this.token,
    this.onRequestSubmitted,
  });

  @override
  State<IncidentReportScreen> createState() => _IncidentReportScreenState();
}

// Estado interno de la pantalla de reporte de emergencia.
class _IncidentReportScreenState extends State<IncidentReportScreen> {
  // === VARIABLES PARA VEHÍCULOS ===
  // Lista real de vehículos devuelta por el backend del cliente autenticado.
  List<Map<String, dynamic>> _vehiculosRegistrados = <Map<String, dynamic>>[];

  // Placa seleccionada para asociar el incidente al vehículo correcto.
  String? _placaSeleccionada;

  // Bandera para mostrar carga mientras se obtiene la lista de vehículos.
  bool _isLoadingVehicles = false;

  // === VARIABLES DE UBICACIÓN ===
  bool _isLocating = false;
  double? _latitud;
  double? _longitud;
  String? _direccionObtenida;

  // === EVIDENCIAS ===
  // Campo para referencia textual de ubicación (calle, zona, etc.).
  final TextEditingController _ubicacionTextoController =
      TextEditingController();
  // Campo para texto adicional opcional.
  final TextEditingController _textoEvidenciaController =
      TextEditingController();

  // URLs reales de evidencias subidas al backend.
  String? _imagenUrl;
  String? _audioUrl;
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecordingAudio = false;
  bool _isUploadingAudio = false;

  bool _isSubmitting = false;
  int? _currentIncidenteId; // ID del incidente si estamos en fase de reintento

  @override
  void initState() {
    super.initState();
    // Cargamos vehículos al entrar para poblar el selector del reporte.
    _cargarMisVehiculos();
  }

  // Convierte errores del backend en texto legible para mostrar en UI.
  String _parseBackendError(String responseBody) {
    try {
      final dynamic decoded = json.decode(responseBody);
      if (decoded is Map<String, dynamic>) {
        final dynamic detail = decoded['detail'];
        if (detail is String && detail.isNotEmpty) {
          return detail;
        }

        if (detail is List && detail.isNotEmpty) {
          final List<String> messages = detail
              .map((dynamic item) {
                if (item is Map<String, dynamic>) {
                  final dynamic msg = item['msg'];
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
      }
    } catch (_) {
      // Si la respuesta no viene en JSON, usamos mensaje genérico.
    }

    return 'No se pudo completar la operación.';
  }

  // Carga lista de vehículos del cliente desde backend.
  Future<void> _cargarMisVehiculos() async {
    setState(() {
      _isLoadingVehicles = true;
    });

    try {
      final baseUrl = dotenv.env['API_URL'] ?? 'http://10.0.2.2:8000/api/v1';
      final Uri url = Uri.parse('$baseUrl/vehiculos/mis-vehiculos');

      final http.Response response = await http
          .get(
            url,
            headers: <String, String>{
              'Authorization': 'Bearer ${widget.token}',
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final dynamic decoded = json.decode(response.body);
        final List<Map<String, dynamic>> vehicles = <Map<String, dynamic>>[];

        if (decoded is List) {
          for (final dynamic item in decoded) {
            if (item is Map<String, dynamic>) {
              vehicles.add(item);
            }
          }
        }

        if (mounted) {
          setState(() {
            _vehiculosRegistrados = vehicles;
            if (_placaSeleccionada != null) {
              final bool stillExists = _vehiculosRegistrados.any(
                (Map<String, dynamic> v) => v['placa'] == _placaSeleccionada,
              );
              if (!stillExists) {
                _placaSeleccionada = null;
              }
            }
          });
        }
      } else {
        final String error = _parseBackendError(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No se pudieron cargar vehículos: $error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando vehículos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingVehicles = false;
        });
      }
    }
  }

  // Obtiene ubicación GPS con permisos en tiempo de ejecución.
  Future<void> _obtenerUbicacion() async {
    setState(() {
      _isLocating = true;
    });

    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Activa la ubicación del dispositivo para continuar.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw Exception('Permiso de ubicación denegado.');
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          'Permiso denegado permanentemente. Habilítalo en ajustes.',
        );
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      String direccionText = 'Dirección desconocida';
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          direccionText = '${place.street}, ${place.locality}';
        }
      } catch (e) {
        // Si la libreria geocoding falla, mantendremos direccion desconocida y no detenemos la ejecucion.
      }

      if (mounted) {
        setState(() {
          _latitud = position.latitude;
          _longitud = position.longitude;
          _direccionObtenida = direccionText;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ubicación en tiempo real obtenida.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo obtener ubicación: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  Future<String?> _uploadEvidenceFile({
    required String filePath,
    required String tipo,
  }) async {
    final baseUrl = dotenv.env['API_URL'] ?? 'http://10.0.2.2:8000/api/v1';
    final Uri url = Uri.parse('$baseUrl/incidentes/evidencias/upload');

    final request = http.MultipartRequest('POST', url)
      ..headers['Authorization'] = 'Bearer ${widget.token}'
      ..fields['tipo'] = tipo
      ..files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 25),
    );
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 201 || response.statusCode == 200) {
      final dynamic decoded = json.decode(response.body);
      final dynamic uploadedUrl = decoded is Map<String, dynamic>
          ? decoded['url']
          : null;

      if (uploadedUrl is String && uploadedUrl.isNotEmpty) {
        return uploadedUrl;
      }

      throw Exception('El servidor no devolvió una URL de evidencia válida.');
    }

    throw Exception(
      'No se pudo subir la evidencia (${response.statusCode}): ${_parseBackendError(response.body)}',
    );
  }

  // Métodos para capturar Foto y Audio desde el celular
  Future<void> _tomarFoto() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? photo = await picker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        final String? uploadedUrl = await _uploadEvidenceFile(
          filePath: photo.path,
          tipo: 'imagen',
        );

        if (uploadedUrl == null) {
          return;
        }

        setState(() {
          _imagenUrl = uploadedUrl;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Foto subida correctamente.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al abrir la cámara: $e')));
      }
    }
  }

  Future<void> _seleccionarGaleria() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? photo = await picker.pickImage(source: ImageSource.gallery);
      if (photo != null) {
        final String? uploadedUrl = await _uploadEvidenceFile(
          filePath: photo.path,
          tipo: 'imagen',
        );

        if (uploadedUrl == null) {
          return;
        }

        setState(() {
          _imagenUrl = uploadedUrl;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Foto de galería subida correctamente.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al abrir la galería: $e')),
        );
      }
    }
  }

  void _opcionesFoto() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Tomar Foto'),
                onTap: () {
                  Navigator.pop(context);
                  _tomarFoto();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Seleccionar de Galería'),
                onTap: () {
                  Navigator.pop(context);
                  _seleccionarGaleria();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _grabarAudio() async {
    if (_isUploadingAudio) {
      return;
    }

    if (_isRecordingAudio) {
      await _detenerYSubirAudio();
      return;
    }

    try {
      final bool hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        throw Exception('Permiso de micrófono denegado.');
      }

      final tempDir = await getTemporaryDirectory();
      final filePath =
          '${tempDir.path}/reporte_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isRecordingAudio = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Grabando audio... pulsa de nuevo para detener.'),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo iniciar la grabación: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _detenerYSubirAudio() async {
    setState(() {
      _isUploadingAudio = true;
    });

    try {
      final String? path = await _audioRecorder.stop();
      if (path == null || path.isEmpty) {
        throw Exception('No se pudo recuperar la grabación de audio.');
      }

      final audioFile = File(path);
      if (!await audioFile.exists()) {
        throw Exception('No se encontró el archivo de audio grabado.');
      }

      final String? uploadedUrl = await _uploadEvidenceFile(
        filePath: path,
        tipo: 'audio',
      );

      if (uploadedUrl == null) {
        return;
      }

      setState(() {
        _audioUrl = uploadedUrl;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio grabado y subido correctamente.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo cargar el audio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRecordingAudio = false;
          _isUploadingAudio = false;
        });
      }
    }
  }

  // Envía la solicitud de emergencia al backend.
  Future<void> _reportarEmergencia() async {
    if (_isSubmitting) {
      return;
    }

    if (_placaSeleccionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona un vehículo.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_latitud == null || _longitud == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Obtén tu ubicación actual primero.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final baseUrl = dotenv.env['API_URL'] ?? 'http://10.0.2.2:8000/api/v1';
      final Uri url = _currentIncidenteId == null
          ? Uri.parse('$baseUrl/incidentes/reportar')
          : Uri.parse(
              '$baseUrl/incidentes/$_currentIncidenteId/reenviar-evidencia',
            );

      final http.Response response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${widget.token}',
            },
            body: json.encode({
              if (_currentIncidenteId == null)
                'vehiculo_placa': _placaSeleccionada,
              if (_currentIncidenteId == null)
                'ubicacion': _ubicacionTextoController.text.trim().isEmpty
                    ? _direccionObtenida
                    : _ubicacionTextoController.text.trim(),
              if (_currentIncidenteId == null) 'latitud': _latitud,
              if (_currentIncidenteId == null) 'longitud': _longitud,
              'imagen_url': _imagenUrl,
              'audio_url': _audioUrl,
              'texto_usuario': _textoEvidenciaController.text.trim().isEmpty
                  ? null
                  : _textoEvidenciaController.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 201 || response.statusCode == 200) {
        final dynamic data = json.decode(response.body);
        debugPrint('[IA] tipo_deducido_ia: ${data['"'"'tipo_deducido_ia'"'"']}');
        debugPrint('[IA] audio_transcripcion_ia: ${data['"'"'audio_transcripcion_ia'"'"']}');
        debugPrint('[IA] resumen_imagen_ia: ${data['"'"'resumen_imagen_ia'"'"']}');
        final bool isSuficiente = data['informacion_suficiente'] ?? true;
        final String detalleInfo =
            data['detalle_solicitud_info'] ??
            'Falta información, por favor completa tu reporte.';
        final int incidenteId = data['incidente_id'];

        if (mounted) {
          if (!isSuficiente) {
            _currentIncidenteId =
                incidenteId; // Guardamos ID para reenviar la evidencia en el próximo intento.

            // El backend dice que no es suficiente, reportamos error para que reescriba.
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Información insuficiente: $detalleInfo'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
              ),
            );
          } else {
            // Información completa, pasamos a la fase de seleccion de talleres
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Emergencia analizada. Buscando talleres...'),
                backgroundColor: Colors.green,
              ),
            );

            final bool? sentToWorkshops = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (context) => WorkshopSelectionScreen(
                  incidenteId: incidenteId,
                  token: widget.token,
                ),
              ),
            );

            if (sentToWorkshops == true) {
              _textoEvidenciaController.clear();
              _ubicacionTextoController.clear();

              setState(() {
                _imagenUrl = null;
                _audioUrl = null;
                _currentIncidenteId = null;
              });

              widget.onRequestSubmitted?.call();
            }
          }
        }
      } else {
        final String error = _parseBackendError(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error ${response.statusCode}: $error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo enviar la solicitud: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mientras carga lista de vehículos mostramos indicador para evitar pantalla vacía.
    if (_isLoadingVehicles) {
      return const Center(child: CircularProgressIndicator());
    }

    // Si no hay vehículos registrados, guiamos al usuario a registrarlos primero.
    if (_vehiculosRegistrados.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.car_crash_outlined,
                size: 80,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              const Text(
                'No tienes vehículos registrados',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Para solicitar soporte necesitas registrar al menos un vehículo en tu perfil.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          VehicleRegistrationScreen(token: widget.token),
                    ),
                  );
                  await _cargarMisVehiculos();
                },
                icon: const Icon(Icons.add),
                label: const Text('Registrar Vehículo Ahora'),
              ),
            ],
          ),
        ),
      );
    }

    // Interfaz regular de creación de incidente
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Solicitar Asistencia Inmediata',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.redAccent,
                ),
              ),
              const SizedBox(height: 24),

              // === 1. SELECCIÓN DE VEHÍCULO ===
              DropdownButtonFormField<String>(
                initialValue: _placaSeleccionada,
                hint: const Text('Selecciona tu vehículo'),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.directions_car),
                  border: OutlineInputBorder(),
                ),
                items: _vehiculosRegistrados.map((
                  Map<String, dynamic> vehiculo,
                ) {
                  final String placa = (vehiculo['placa'] ?? '').toString();
                  final String marca = (vehiculo['marca'] ?? '').toString();
                  final String modelo = (vehiculo['modelo'] ?? '').toString();
                  final String label = '$placa - $marca $modelo';

                  // Soluciona el error overflow by 4.4px
                  return DropdownMenuItem(
                    value: placa,
                    child: Tooltip(
                      message: label,
                      child: Text(label, overflow: TextOverflow.ellipsis),
                    ),
                  );
                }).toList(),
                isExpanded:
                    true, // Esto obliga al texto a no salirse de la caja
                onChanged: (value) {
                  setState(() {
                    _placaSeleccionada = value;
                  });
                },
              ),
              const SizedBox(height: 24),

              // === 2. UBICACIÓN EN TIEMPO REAL ===
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Ubicación del Incidente',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _latitud != null && _longitud != null
                          ? 'Dirección: ${_direccionObtenida ?? ''}'
                          : 'Ubicación no obtenida',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _latitud == null ? Colors.red : Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_latitud != null && _longitud != null)
                      TextButton.icon(
                        icon: const Icon(Icons.map),
                        label: const Text('Ver en Google Maps'),
                        onPressed: () async {
                          final url = Uri.parse(
                            'https://www.google.com/maps/search/?api=1&query=$_latitud,$_longitud',
                          );
                          try {
                            await launchUrl(
                              url,
                              mode: LaunchMode.externalApplication,
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('No se pudo abrir Google Maps.'),
                              ),
                            );
                          }
                        },
                      ),
                    const SizedBox(height: 12),
                    _isLocating
                        ? const CircularProgressIndicator()
                        : ElevatedButton.icon(
                            onPressed: _obtenerUbicacion,
                            icon: const Icon(Icons.my_location),
                            label: const Text('Obtener Ubicación Actual'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Campo para agregar referencias del lugar
              TextField(
                controller: _ubicacionTextoController,
                decoration: const InputDecoration(
                  labelText: 'Referencia opcional (ej: cerca del puente)',
                  prefixIcon: Icon(Icons.map),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),

              // === 3. EVIDENCIAS PARA LA IA ===
              const Text(
                'Evidencias del Problema',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Text(
                'Foto, audio y texto son opcionales. Puedes enviar con lo que tengas.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Botón Cámara/Galería para adjuntar imagen
                  Column(
                    children: [
                      IconButton(
                        onPressed: _opcionesFoto,
                        icon: Icon(
                          Icons.camera_alt,
                          size: 40,
                          color: _imagenUrl != null
                              ? Colors.green
                              : Colors.grey,
                        ),
                      ),
                      const Text('Foto', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                  // Botón Micrófono para grabar
                  Column(
                    children: [
                      IconButton(
                        onPressed: _isUploadingAudio ? null : _grabarAudio,
                        icon: Icon(
                          _isRecordingAudio ? Icons.stop_circle : Icons.mic,
                          size: 40,
                          color: _isRecordingAudio
                              ? Colors.red
                              : (_audioUrl != null ? Colors.green : Colors.grey),
                        ),
                      ),
                      Text(
                        _isUploadingAudio
                            ? 'Subiendo...'
                            : (_isRecordingAudio
                                  ? 'Detener'
                                  : (_audioUrl != null ? 'Audio listo' : 'Grabar')),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _textoEvidenciaController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Texto adicional (Opcional)',
                  prefixIcon: Icon(Icons.notes),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 32),

              // === 4. BOTÓN DE ENVÍO ===
              _isSubmitting
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                      onPressed: _reportarEmergencia,
                      icon: const Icon(Icons.send),
                      label: const Text('ENVIAR REPORTE'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (_isRecordingAudio) {
      _audioRecorder.stop();
    }
    _audioRecorder.dispose();
    _ubicacionTextoController.dispose();
    _textoEvidenciaController.dispose();
    super.dispose();
  }
}
