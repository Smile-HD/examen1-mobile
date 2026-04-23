import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';

class TechnicianIncomingRequestsView extends StatefulWidget {
  final String token;
  const TechnicianIncomingRequestsView({super.key, required this.token});

  @override
  State<TechnicianIncomingRequestsView> createState() => _TechnicianIncomingRequestsViewState();
}

class _TechnicianIncomingRequestsViewState extends State<TechnicianIncomingRequestsView> {
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isSendingLocation = false;
  bool _isPerformingAction = false;
  bool _isAutoTracking = false;
  String? _errorMessage;
  String? _trackingStatus;
  int? _trackedSolicitudId;
  List<Map<String, dynamic>> _incomingRequests = <Map<String, dynamic>>[];
  Timer? _pollTimer;
  Timer? _trackingTimer;

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  Future<void> _openClientLocationInMaps(dynamic latRaw, dynamic lngRaw) async {
    final lat = _toDouble(latRaw);
    final lng = _toDouble(lngRaw);
    if (lat == null || lng == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La solicitud no tiene coordenadas válidas del cliente.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final mapsUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    final launched = await launchUrl(
      mapsUri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir Google Maps en este dispositivo.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openRouteToClient(dynamic latRaw, dynamic lngRaw) async {
    final destinationLat = _toDouble(latRaw);
    final destinationLng = _toDouble(lngRaw);
    if (destinationLat == null || destinationLng == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay coordenadas del cliente para trazar la ruta.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      await _ensureLocationPermission();
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      final mapsUri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&origin=${current.latitude},${current.longitude}&destination=$destinationLat,$destinationLng&travelmode=driving',
      );

      final launched = await launchUrl(
        mapsUri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir Google Maps en este dispositivo.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo abrir la ruta al cliente: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadIncomingRequests();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _loadIncomingRequests(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _trackingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadIncomingRequests({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
      });
    } else {
      setState(() {
        _isRefreshing = true;
      });
    }

    try {
      final baseUrl = dotenv.env['API_URL'] ?? 'http://10.0.2.2:8000/api/v1';
      final response = await http
          .get(
            Uri.parse('$baseUrl/incidentes/tecnico/solicitudes'),
            headers: {'Authorization': 'Bearer ${widget.token}'},
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw Exception('No se pudo cargar las solicitudes (${response.statusCode})');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final solicitudesRaw = (data['solicitudes'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();

      if (!mounted) return;
      setState(() {
        _incomingRequests = solicitudesRaw;
        _errorMessage = null;
      });

      final stillTracked = _trackedSolicitudId != null &&
          _incomingRequests.any((item) => item['solicitud_id'] == _trackedSolicitudId);
      if (!stillTracked && _isAutoTracking) {
        _stopAutoTracking(showMessage: false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error cargando solicitudes: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  Future<void> _ensureLocationPermission() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Activa tu GPS para compartir ubicación.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw Exception('No hay permisos de ubicación.');
    }
  }

  Future<void> _sendLocation({required int solicitudId, bool showToast = true}) async {
    if (_isSendingLocation) {
      return;
    }

    setState(() {
      _isSendingLocation = true;
    });

    try {
      await _ensureLocationPermission();
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      final baseUrl = dotenv.env['API_URL'] ?? 'http://10.0.2.2:8000/api/v1';
      final response = await http.post(
        Uri.parse('$baseUrl/incidentes/tecnico/ubicacion'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: json.encode({
          'latitud': position.latitude,
          'longitud': position.longitude,
          'solicitud_id': solicitudId,
          'precision_metros': position.accuracy,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('No se pudo enviar ubicación (${response.statusCode})');
      }

      if (showToast && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ubicación enviada correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted && showToast) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error enviando ubicación: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      rethrow;
    } finally {
      if (mounted) {
        setState(() {
          _isSendingLocation = false;
        });
      }
    }
  }

  Future<void> _startAutoTracking(int solicitudId) async {
    _trackingTimer?.cancel();
    setState(() {
      _isAutoTracking = true;
      _trackedSolicitudId = solicitudId;
      _trackingStatus = 'Seguimiento en vivo activo para solicitud #$solicitudId';
    });

    try {
      await _sendLocation(solicitudId: solicitudId, showToast: false);
    } catch (_) {
      _stopAutoTracking();
      return;
    }

    _trackingTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final activeSolicitud = _trackedSolicitudId;
      if (!_isAutoTracking || activeSolicitud == null) {
        return;
      }
      try {
        await _sendLocation(solicitudId: activeSolicitud, showToast: false);
      } catch (_) {
        if (mounted) {
          setState(() {
            _trackingStatus = 'Seguimiento pausado por error de ubicación.';
          });
        }
      }
    });
  }

  void _stopAutoTracking({bool showMessage = true}) {
    _trackingTimer?.cancel();
    setState(() {
      _isAutoTracking = false;
      _trackedSolicitudId = null;
      _trackingStatus = showMessage ? 'Seguimiento en vivo detenido.' : null;
    });
  }

  Future<void> _finalizeRequest(int solicitudId) async {
    final commentController = TextEditingController();
    final timeController = TextEditingController(text: '30');
    final costController = TextEditingController(text: '0');
    final distanceController = TextEditingController(text: '0');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Finalizar solicitud'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: commentController,
                decoration: const InputDecoration(labelText: 'Comentario de cierre'),
              ),
              TextField(
                controller: timeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Tiempo (minutos)'),
              ),
              TextField(
                controller: costController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Costo total'),
              ),
              TextField(
                controller: distanceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Distancia (km)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isPerformingAction = true;
    });

    try {
      final baseUrl = dotenv.env['API_URL'] ?? 'http://10.0.2.2:8000/api/v1';
      final payload = {
        'comentario_cierre': commentController.text.trim().isEmpty ? null : commentController.text.trim(),
        'tiempo_minutos': int.tryParse(timeController.text.trim()) ?? 30,
        'costo_total': double.tryParse(costController.text.trim()) ?? 0,
        'distancia_km': double.tryParse(distanceController.text.trim()) ?? 0,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/incidentes/tecnico/solicitudes/$solicitudId/finalizar'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: json.encode(payload),
      );

      if (response.statusCode != 200) {
        throw Exception('No se pudo finalizar (${response.statusCode})');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solicitud finalizada y recursos liberados.'),
            backgroundColor: Colors.green,
          ),
        );
      }

      if (_trackedSolicitudId == solicitudId) {
        _stopAutoTracking(showMessage: false);
      }

      await _loadIncomingRequests(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al finalizar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPerformingAction = false;
        });
      }
    }
  }

  Future<void> _rejectRequest(int solicitudId) async {
    final commentController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rechazar solicitud'),
        content: TextField(
          controller: commentController,
          decoration: const InputDecoration(
            labelText: 'Motivo (opcional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isPerformingAction = true;
    });

    try {
      final baseUrl = dotenv.env['API_URL'] ?? 'http://10.0.2.2:8000/api/v1';
      final response = await http.post(
        Uri.parse('$baseUrl/incidentes/tecnico/solicitudes/$solicitudId/rechazar'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: json.encode({
          'comentario': commentController.text.trim().isEmpty ? null : commentController.text.trim(),
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('No se pudo rechazar (${response.statusCode})');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solicitud rechazada y recursos liberados.'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      if (_trackedSolicitudId == solicitudId) {
        _stopAutoTracking(showMessage: false);
      }

      await _loadIncomingRequests(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al rechazar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPerformingAction = false;
        });
      }
    }
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) {
      return '-';
    }
    final dt = DateTime.tryParse(raw);
    if (dt == null) {
      return raw;
    }
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadIncomingRequests,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_incomingRequests.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadIncomingRequests(silent: true),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 100),
            const Icon(Icons.assignment_turned_in_outlined, size: 72, color: Colors.green),
            const SizedBox(height: 12),
            const Text(
              'No tienes solicitudes activas.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cuando un taller te asigne una solicitud, aparecerá aquí automáticamente.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadIncomingRequests(silent: true),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _incomingRequests.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.assignment, color: Colors.blueAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Solicitudes activas: ${_incomingRequests.length}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (_isRefreshing)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  if (_trackingStatus != null) ...[
                    const SizedBox(height: 8),
                    Text(_trackingStatus!, style: const TextStyle(color: Colors.blueGrey)),
                  ],
                ],
              ),
            );
          }

          final item = _incomingRequests[index - 1];
          final solicitudId = item['solicitud_id'] as int?;
          final isTrackingThis = _isAutoTracking && solicitudId != null && _trackedSolicitudId == solicitudId;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Incidente #${item['incidente_id']} - ${item['tipo_problema'] ?? 'Sin tipo'}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text('Vehículo: ${item['vehiculo_placa'] ?? '-'}'),
                  Text('Ubicación cliente: ${item['ubicacion'] ?? 'Sin referencia'}'),
                  if (_toDouble(item['latitud']) != null && _toDouble(item['longitud']) != null)
                    Text(
                      'Coordenadas cliente: ${_toDouble(item['latitud'])!.toStringAsFixed(6)}, ${_toDouble(item['longitud'])!.toStringAsFixed(6)}',
                    ),
                  Text('Estado solicitud: ${item['estado_solicitud'] ?? '-'}'),
                  Text('Fecha: ${_formatDate((item['fecha_asignacion'] ?? '').toString())}'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: (solicitudId == null || _isPerformingAction)
                            ? null
                            : () => _openClientLocationInMaps(item['latitud'], item['longitud']),
                        icon: const Icon(Icons.location_on_outlined),
                        label: const Text('Ver ubicación cliente'),
                      ),
                      OutlinedButton.icon(
                        onPressed: (solicitudId == null || _isPerformingAction)
                            ? null
                            : () => _openRouteToClient(item['latitud'], item['longitud']),
                        icon: const Icon(Icons.alt_route),
                        label: const Text('Navegar al cliente'),
                      ),
                      OutlinedButton.icon(
                        onPressed: (solicitudId == null || _isSendingLocation || _isPerformingAction)
                            ? null
                            : () => _sendLocation(solicitudId: solicitudId),
                        icon: const Icon(Icons.share_location),
                        label: Text(_isSendingLocation ? 'Enviando...' : 'Enviar ubicación'),
                      ),
                      ElevatedButton.icon(
                        onPressed: (solicitudId == null || _isPerformingAction)
                            ? null
                            : () {
                                if (isTrackingThis) {
                                  _stopAutoTracking();
                                } else {
                                  _startAutoTracking(solicitudId);
                                }
                              },
                        icon: Icon(isTrackingThis ? Icons.pause_circle : Icons.play_circle),
                        label: Text(isTrackingThis ? 'Detener seguimiento' : 'Seguimiento automático'),
                      ),
                      ElevatedButton(
                        onPressed: (solicitudId == null || _isPerformingAction)
                            ? null
                            : () => _finalizeRequest(solicitudId),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        child: const Text('Finalizar'),
                      ),
                      ElevatedButton(
                        onPressed: (solicitudId == null || _isPerformingAction)
                            ? null
                            : () => _rejectRequest(solicitudId),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        child: const Text('Rechazar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class TechnicianHistoryView extends StatefulWidget {
  final String token;
  const TechnicianHistoryView({super.key, required this.token});

  @override
  State<TechnicianHistoryView> createState() => _TechnicianHistoryViewState();
}

class _TechnicianHistoryViewState extends State<TechnicianHistoryView> {
  bool _isLoading = true;
  List<dynamic> _historial = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final baseUrl = dotenv.env['API_URL'] ?? 'http://10.0.2.2:8000/api/v1';
      final response = await http.get(
        Uri.parse('$baseUrl/incidentes/tecnico/mi-historial'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _historial = data['incidentes'] ?? [];
          });
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_historial.isEmpty) return const Center(child: Text('No hay incidentes en tu registro.'));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _historial.length,
      itemBuilder: (context, index) {
        final item = _historial[index];

        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Vehículo: ${item['vehiculo_placa']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text('Problema: ${item['tipo_problema']}'),
                Text('Estado: ${item['estado_incidente']}'),
                if (item['metrica'] != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Cobrado: ${item['metrica']['costo_total']} - Tiempo: ${item['metrica']['tiempo_minutos']} min',
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                ]
              ],
            ),
          )
        );
      },
    );
  }
}