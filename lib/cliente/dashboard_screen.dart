import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../home_screen.dart';
import 'incident_report_screen.dart';
import 'payment_screen.dart';
import '../tecnico/technician_views.dart';
import 'vehicle_registration_screen.dart';
import 'push_notifications_service.dart';
import '../session_storage.dart';

class DashboardScreen extends StatefulWidget {
  final String nombre;
  final String correo;
  final String token;
  final String perfil;

  const DashboardScreen({
    super.key,
    required this.nombre,
    required this.correo,
    required this.token,
    required this.perfil,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  int _clientRequestsRefreshSeed = 0;

  bool get _isTecnicoPrincipal =>
      widget.perfil.trim().toLowerCase() == 'tecnico';

  @override
  void initState() {
    super.initState();
    if (!_isTecnicoPrincipal) {
      unawaited(_initializePushNotifications());
    }
  }

  Future<void> _initializePushNotifications() async {
    try {
      await PushNotificationsService.instance.initForClient(
        authToken: widget.token,
        onForegroundNotification: (title, body) {
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$title\n$body'),
              backgroundColor: Colors.blueAccent,
              duration: const Duration(seconds: 4),
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('Push init error: $e');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo activar notificaciones push: $e'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _goToClientRequestsTab() {
    if (!mounted) {
      return;
    }

    setState(() {
      _clientRequestsRefreshSeed += 1;
      _currentIndex = 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> bodyViews = _isTecnicoPrincipal
        ? [
            _buildPerfilView(context),
            TechnicianIncomingRequestsView(token: widget.token),
            TechnicianHistoryView(token: widget.token),
          ]
        : [
            _buildPerfilView(context),
            IncidentReportScreen(
              token: widget.token,
              onRequestSubmitted: _goToClientRequestsTab,
            ),
            ClientRequestsStatusView(
              key: ValueKey(_clientRequestsRefreshSeed),
              token: widget.token,
            ),
          ];

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Mi Panel'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar Sesión',
            onPressed: () async {
              await SessionStorage.clearSession();
              if (!context.mounted) {
                return;
              }
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: bodyViews[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (int index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: Colors.blueAccent,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Perfil',
          ),
          BottomNavigationBarItem(
            icon: _isTecnicoPrincipal
                ? const Icon(Icons.assignment)
                : const Icon(Icons.car_crash),
            label: _isTecnicoPrincipal ? 'Solicitudes' : 'Solicitar Soporte',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.history),
            label: _isTecnicoPrincipal ? 'Historial' : 'Solicitudes',
          ),
        ],
      ),
    );
  }

  Widget _buildPerfilView(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.blueAccent,
                    child: Icon(Icons.person, size: 50, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.nombre,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.correo,
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          if (_isTecnicoPrincipal) ...[
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Perfil técnico activo. Usa Solicitudes para atender, compartir ubicación en vivo y cerrar servicios.',
                  style: TextStyle(fontSize: 15, color: Colors.black87),
                ),
              ),
            ),
          ] else ...[
            const Text(
              'Mis Vehículos',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        VehicleRegistrationScreen(token: widget.token),
                  ),
                );
              },
              icon: const Icon(Icons.directions_car),
              label: const Text('Registrar Vehículo'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ClientRequestsStatusView extends StatefulWidget {
  final String token;

  const ClientRequestsStatusView({super.key, required this.token});

  @override
  State<ClientRequestsStatusView> createState() =>
      _ClientRequestsStatusViewState();
}

class _ClientRequestsStatusViewState extends State<ClientRequestsStatusView> {
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  bool _showFullHistory = false;
  Timer? _pollTimer;
  List<Map<String, dynamic>> _allRequests = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _pendingRequests = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _loadClientRequests();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _loadClientRequests(refresh: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  bool _isPendingState(String state) {
    final normalized = state.trim().toLowerCase();
    const closedStates = <String>{
      'rechazada',
      'rechazada_tecnico',
      'otro_taller_acepto',
      'finalizada',
      'cancelada',
    };
    return !closedStates.contains(normalized);
  }

  Color _stateColor(String state) {
    switch (state.trim().toLowerCase()) {
      case 'aceptada':
      case 'en_proceso':
      case 'en_camino':
      case 'finalizada':
      case 'atendido':
        return Colors.green;
      case 'enviada':
      case 'pendiente':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  String _readableState(String state) {
    if (state.trim().isEmpty) {
      return 'Desconocido';
    }

    final value = state.trim().toLowerCase().replaceAll('_', ' ');
    return value[0].toUpperCase() + value.substring(1);
  }

  String _formatDate(String raw) {
    final date = DateTime.tryParse(raw);
    if (date == null) {
      return raw;
    }

    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  double? _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  Future<void> _openTechnicianLocationInMaps(
    dynamic latRaw,
    dynamic lngRaw,
  ) async {
    final lat = _toDouble(latRaw);
    final lng = _toDouble(lngRaw);

    if (lat == null || lng == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay coordenadas válidas del técnico todavía.'),
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

  void _openTrackingScreen(Map<String, dynamic> item) {
    final incidenteId = (item['incidente_id'] as num?)?.toInt();
    final solicitudId = (item['solicitud_id'] as num?)?.toInt();

    if (incidenteId == null || solicitudId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el seguimiento de esta solicitud.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IncidentTrackingMapScreen(
          token: widget.token,
          incidenteId: incidenteId,
          solicitudId: solicitudId,
        ),
      ),
    );
  }

  void _openPaymentScreen(int incidenteId) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PaymentScreen(incidenteId: incidenteId, token: widget.token),
      ),
    );

    if (result == true) {
      _loadClientRequests(refresh: true);
    }
  }

  String _parseError(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String && detail.isNotEmpty) {
          return detail;
        }
      }
    } catch (_) {
      // Si no es JSON, devolvemos mensaje genérico.
    }
    return 'No se pudieron cargar las solicitudes.';
  }

  List<Map<String, dynamic>> get _visibleRequests {
    return _showFullHistory ? _allRequests : _pendingRequests;
  }

  Future<void> _loadClientRequests({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _isRefreshing = true;
      });
    } else {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final baseUrl = dotenv.env['API_URL'] ?? 'http://10.0.2.2:8000/api/v1';
      final url = Uri.parse('$baseUrl/incidentes/mis-solicitudes');

      final response = await http
          .get(url, headers: {'Authorization': 'Bearer ${widget.token}'})
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);
        final List<Map<String, dynamic>> rawItems = <Map<String, dynamic>>[];
        if (data is Map<String, dynamic> && data['solicitudes'] is List) {
          for (final dynamic item in data['solicitudes']) {
            if (item is Map<String, dynamic>) {
              rawItems.add(item);
            }
          }
        }

        final pending = rawItems.where((item) {
          final hasMetric = item['metrica'] is Map;
          if (hasMetric) {
            return false;
          }
          final state = (item['estado_solicitud'] ?? '').toString();
          return _isPendingState(state);
        }).toList();

        if (mounted) {
          setState(() {
            _allRequests = rawItems;
            _pendingRequests = pending;
            _errorMessage = null;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = _parseError(response.body);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error de red: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
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
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadClientRequests,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_visibleRequests.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadClientRequests(refresh: true),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 120),
            const Icon(
              Icons.check_circle_outline,
              size: 72,
              color: Colors.green,
            ),
            const SizedBox(height: 12),
            Text(
              _showFullHistory
                  ? 'No tienes solicitudes registradas.'
                  : 'No tienes solicitudes pendientes.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _showFullHistory
                  ? 'Cuando envíes pedidos de auxilio, aparecerán en tu historial.'
                  : 'Cuando envíes un nuevo pedido de auxilio, verás su estado aquí.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            if (!_showFullHistory && _allRequests.isNotEmpty) ...[
              const SizedBox(height: 16),
              Center(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _showFullHistory = true;
                    });
                  },
                  icon: const Icon(Icons.history),
                  label: const Text('Ver historial completo'),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadClientRequests(refresh: true),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _visibleRequests.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                children: [
                  Icon(
                    _showFullHistory ? Icons.history : Icons.pending_actions,
                    color: Colors.blueAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _showFullHistory
                          ? 'Historial de solicitudes: ${_visibleRequests.length}'
                          : 'Solicitudes pendientes: ${_visibleRequests.length}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _showFullHistory = !_showFullHistory;
                      });
                    },
                    child: Text(
                      _showFullHistory ? 'Ver pendientes' : 'Ver historial',
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
            );
          }

          final item = _visibleRequests[index - 1];
          final estadoSolicitud = (item['estado_solicitud'] ?? '').toString();
          final estadoIncidente = (item['estado_incidente'] ?? '').toString();
          final metrica = item['metrica'] is Map
              ? Map<String, dynamic>.from(item['metrica'] as Map)
              : null;
          final estadoSolicitudDisplay = metrica != null
              ? 'finalizada'
              : estadoSolicitud;
          final estadoIncidenteDisplay = metrica != null
              ? 'atendido'
              : estadoIncidente;

          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Incidente #${item['incidente_id']} - ${item['tipo_problema'] ?? 'Sin tipo'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        backgroundColor: _stateColor(
                          estadoSolicitudDisplay,
                        ).withValues(alpha: 0.15),
                        label: Text(
                          'Solicitud: ${_readableState(estadoSolicitudDisplay)}',
                        ),
                      ),
                      Chip(
                        backgroundColor: Colors.blueGrey.withValues(
                          alpha: 0.12,
                        ),
                        label: Text(
                          'Incidente: ${_readableState(estadoIncidenteDisplay)}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Taller: ${item['nombre_taller'] ?? 'Sin asignar'}'),
                  Text('Prioridad: ${item['prioridad'] ?? '-'}'),
                  Text(
                    'Fecha: ${_formatDate((item['fecha_asignacion'] ?? '').toString())}',
                  ),
                  if (metrica != null) ...[
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    const Text(
                      'Métricas del servicio',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text('Costo total: ${metrica['costo_total'] ?? 0}'),
                    Text('Tiempo: ${metrica['tiempo_minutos'] ?? '-'} min'),
                    Text(
                      'Comisión plataforma: ${metrica['comision_plataforma'] ?? 0}',
                    ),
                    Text('Distancia: ${metrica['distancia_km'] ?? '-'} km'),
                    if (metrica['fecha_cierre'] != null)
                      Text(
                        'Cierre: ${_formatDate(metrica['fecha_cierre'].toString())}',
                      ),
                    if (metrica['observaciones'] != null &&
                        metrica['observaciones'].toString().trim().isNotEmpty)
                      Text('Observación: ${metrica['observaciones']}'),
                  ],
                  if (item['tecnico_latitud'] != null &&
                      item['tecnico_longitud'] != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Técnico en ruta: Lat ${item['tecnico_latitud']}, Lng ${item['tecnico_longitud']}',
                    ),
                    if (item['tecnico_ubicacion_actualizada_en'] != null)
                      Text(
                        'Actualizado: ${_formatDate(item['tecnico_ubicacion_actualizada_en'].toString())}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _openTrackingScreen(item),
                        icon: const Icon(Icons.route),
                        label: const Text('Seguimiento en tiempo real'),
                      ),
                      if (item['tecnico_latitud'] != null &&
                          item['tecnico_longitud'] != null)
                        OutlinedButton.icon(
                          onPressed: () => _openTechnicianLocationInMaps(
                            item['tecnico_latitud'],
                            item['tecnico_longitud'],
                          ),
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('Abrir en Google Maps'),
                        ),
                      if (estadoIncidente == 'atendido')
                        ElevatedButton.icon(
                          onPressed: () =>
                              _openPaymentScreen(item['incidente_id']),
                          icon: const Icon(Icons.payment),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          label: const Text('Realizar Pago'),
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

class IncidentTrackingMapScreen extends StatefulWidget {
  final String token;
  final int incidenteId;
  final int solicitudId;

  const IncidentTrackingMapScreen({
    super.key,
    required this.token,
    required this.incidenteId,
    required this.solicitudId,
  });

  @override
  State<IncidentTrackingMapScreen> createState() =>
      _IncidentTrackingMapScreenState();
}

class _IncidentTrackingMapScreenState extends State<IncidentTrackingMapScreen> {
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  Map<String, dynamic>? _detail;
  final List<LatLng> _trail = <LatLng>[];
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadIncidentDetail();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _loadIncidentDetail(refresh: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  double? _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  LatLng? _extractTechnicianPosition(Map<String, dynamic> detail) {
    final lat = _toDouble(detail['tecnico_latitud']);
    final lng = _toDouble(detail['tecnico_longitud']);
    if (lat == null || lng == null) {
      return null;
    }
    return LatLng(lat, lng);
  }

  LatLng? _extractIncidentPosition(Map<String, dynamic> detail) {
    final lat = _toDouble(detail['latitud']);
    final lng = _toDouble(detail['longitud']);
    if (lat == null || lng == null) {
      return null;
    }
    return LatLng(lat, lng);
  }

  void _appendTrail(LatLng technicianPosition) {
    if (_trail.isNotEmpty) {
      final last = _trail.last;
      if (last.latitude == technicianPosition.latitude &&
          last.longitude == technicianPosition.longitude) {
        return;
      }
    }

    _trail.add(technicianPosition);
    if (_trail.length > 120) {
      _trail.removeRange(0, _trail.length - 120);
    }
  }

  Future<void> _loadIncidentDetail({bool refresh = false}) async {
    if (refresh) {
      if (mounted) {
        setState(() {
          _isRefreshing = true;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = true;
        });
      }
    }

    try {
      final baseUrl = dotenv.env['API_URL'] ?? 'http://10.0.2.2:8000/api/v1';
      final url = Uri.parse(
        '$baseUrl/incidentes/${widget.incidenteId}/detalle',
      );

      final response = await http
          .get(url, headers: {'Authorization': 'Bearer ${widget.token}'})
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw Exception(
          'No se pudo cargar el detalle (${response.statusCode})',
        );
      }

      final data = json.decode(response.body);
      if (data is! Map<String, dynamic>) {
        throw Exception('Respuesta inválida del servidor.');
      }

      final technicianPosition = _extractTechnicianPosition(data);
      if (technicianPosition != null) {
        _appendTrail(technicianPosition);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _detail = data;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Error cargando seguimiento: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _openExternalMap() async {
    final detail = _detail;
    if (detail == null) {
      return;
    }
    final technicianPosition = _extractTechnicianPosition(detail);
    if (technicianPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El técnico aún no compartió su ubicación.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final mapsUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${technicianPosition.latitude},${technicianPosition.longitude}',
    );
    final launched = await launchUrl(
      mapsUri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir Google Maps.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatDate(dynamic rawValue) {
    final raw = (rawValue ?? '').toString();
    if (raw.trim().isEmpty) {
      return '-';
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw;
    }
    final local = parsed.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Seguimiento del Técnico'),
          backgroundColor: Colors.blueAccent,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Seguimiento del Técnico'),
          backgroundColor: Colors.blueAccent,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _loadIncidentDetail,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final detail = _detail ?? <String, dynamic>{};
    final incidentPosition = _extractIncidentPosition(detail);
    final technicianPosition = _extractTechnicianPosition(detail);
    final initialCenter =
        technicianPosition ??
        incidentPosition ??
        const LatLng(-17.3935, -66.1570);

    final markers = <Marker>[];
    if (incidentPosition != null) {
      markers.add(
        Marker(
          point: incidentPosition,
          width: 44,
          height: 44,
          child: const Icon(Icons.location_pin, color: Colors.blue, size: 40),
        ),
      );
    }
    if (technicianPosition != null) {
      markers.add(
        Marker(
          point: technicianPosition,
          width: 44,
          height: 44,
          child: const Icon(Icons.directions_car, color: Colors.red, size: 34),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Seguimiento #${widget.solicitudId}'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isRefreshing
                ? null
                : () => _loadIncidentDetail(refresh: true),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: initialCenter,
                initialZoom: 14,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.autoasistencia.mobile',
                ),
                if (_trail.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _trail,
                        color: Colors.redAccent,
                        strokeWidth: 4,
                      ),
                    ],
                  ),
                if (markers.isNotEmpty) MarkerLayer(markers: markers),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estado incidente: ${(detail['estado_incidente'] ?? 'desconocido').toString()}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  technicianPosition != null
                      ? 'Técnico: ${technicianPosition.latitude.toStringAsFixed(6)}, ${technicianPosition.longitude.toStringAsFixed(6)}'
                      : 'Técnico: aún no comparte ubicación',
                ),
                const SizedBox(height: 4),
                Text(
                  'Última actualización: ${_formatDate(detail['tecnico_ubicacion_actualizada_en'])}',
                  style: const TextStyle(color: Colors.black54),
                ),
                if (_trail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Puntos de recorrido en sesión: ${_trail.length}',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isRefreshing
                          ? null
                          : () => _loadIncidentDetail(refresh: true),
                      icon: const Icon(Icons.sync),
                      label: const Text('Actualizar ahora'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _openExternalMap,
                      icon: const Icon(Icons.map),
                      label: const Text('Abrir en Google Maps'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
