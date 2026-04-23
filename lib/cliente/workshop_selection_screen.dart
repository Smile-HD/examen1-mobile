import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class WorkshopSelectionScreen extends StatefulWidget {
  final int incidenteId;
  final String token;

  const WorkshopSelectionScreen({
    super.key,
    required this.incidenteId,
    required this.token,
  });

  @override
  State<WorkshopSelectionScreen> createState() =>
      _WorkshopSelectionScreenState();
}

class _WorkshopSelectionScreenState extends State<WorkshopSelectionScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _candidatos = [];
  final Set<int> _talleresSeleccionados = {};
  bool _isSubmitting = false;
  bool _requestSent = false;
  bool _mostrarNoRecomendadas = false;

  @override
  void initState() {
    super.initState();
    _cargarCandidatos();
  }

  Future<void> _cargarCandidatos() async {
    try {
      final baseUrl = dotenv.env['API_URL'] ?? 'http://10.0.2.2:8000/api/v1';
      final url = Uri.parse(
        '$baseUrl/incidentes/${widget.incidenteId}/candidatos',
      );

      final response = await http
          .get(url, headers: {'Authorization': 'Bearer ${widget.token}'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final rawCandidates = data['candidatos'] as List<dynamic>? ?? const [];
        if (mounted) {
          setState(() {
            _candidatos = rawCandidates
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
            _isLoading = false;
          });
        }
      } else if (response.statusCode == 404) {
        // No hay talleres disponibles
        if (mounted) {
          setState(() {
            _candidatos = [];
            _isLoading = false;
          });
        }
      } else {
        _mostrarError('Error al obtener los talleres: ${response.body}');
      }
    } catch (e) {
      _mostrarError('Error de red: $e');
    }
  }

  void _mostrarError(String mensaje) {
    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensaje), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _confirmarSeleccion() async {
    if (_isSubmitting || _requestSent) {
      return;
    }

    if (_talleresSeleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, selecciona al menos un taller candidato.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final baseUrl = dotenv.env['API_URL'] ?? 'http://10.0.2.2:8000/api/v1';
      final url = Uri.parse(
        '$baseUrl/incidentes/${widget.incidenteId}/seleccionar-talleres',
      );

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${widget.token}',
            },
            body: json.encode({
              'talleres_ids': _talleresSeleccionados.toList(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _requestSent = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '¡Solicitud de auxilio enviada exitosamente a los talleres!',
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(true);
        }
      } else {
        _mostrarError('Error al confirmar: ${response.body}');
      }
    } catch (e) {
      _mostrarError('Error de red: $e');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  bool _esRecomendado(Map<String, dynamic> candidato) {
    final recomendado = candidato['recomendado'];
    if (recomendado is bool) {
      return recomendado;
    }

    final categoria = (candidato['categoria_recomendacion'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (categoria == 'opciones_no_recomendadas') {
      return false;
    }

    // Fallback para compatibilidad con payloads antiguos.
    return true;
  }

  String _distanciaLabel(Map<String, dynamic> candidato) {
    final metros = (candidato['distancia_metros'] as num?)?.toDouble();
    if (metros != null) {
      if (metros >= 1000) {
        return '${(metros / 1000).toStringAsFixed(2)} km (${metros.toStringAsFixed(0)} m)';
      }
      return '${metros.toStringAsFixed(0)} m';
    }

    final km = (candidato['distancia_km'] as num?)?.toDouble();
    if (km != null) {
      return '${km.toStringAsFixed(2)} km';
    }

    return 'Ubicacion desconocida';
  }

  Widget _criterioChip({
    required String label,
    required bool ok,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: ok ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: ok ? Colors.green.shade200 : Colors.red.shade200,
        ),
      ),
      child: Text(
        '${ok ? 'OK' : 'NO'} $label',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: ok ? Colors.green.shade800 : Colors.red.shade800,
        ),
      ),
    );
  }

  Widget _candidatoCard(Map<String, dynamic> candidato) {
    final tallerId = (candidato['taller_id'] as num?)?.toInt();
    final nombre = (candidato['nombre_taller'] ?? 'Desconocido').toString();
    final puntuacion = (candidato['puntuacion'] as num?)?.toDouble() ?? 0;
    final razon = (candidato['razon'] ?? 'Sin detalle').toString();
    final recomendado = _esRecomendado(candidato);

    final activo = candidato['taller_activo'] == true ||
        (candidato['disponibilidad'] ?? '').toString().toLowerCase() == 'activo';
    final cumpleServicio =
        candidato['cumple_servicio'] == true || candidato['cumple_tipo_problema'] == true;
    final capacidad = candidato['capacidad_disponible'] == true;

    final tecnicosDisponibles = (candidato['tecnicos_disponibles'] as num?)?.toInt();
    final transportesDisponibles = (candidato['transportes_disponibles'] as num?)?.toInt();

    final isSelected = tallerId != null && _talleresSeleccionados.contains(tallerId);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? Colors.blueAccent
              : (recomendado ? Colors.transparent : Colors.orange.shade200),
          width: isSelected || !recomendado ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: tallerId == null
            ? null
            : () {
                setState(() {
                  if (isSelected) {
                    _talleresSeleccionados.remove(tallerId);
                  } else {
                    _talleresSeleccionados.add(tallerId);
                  }
                });
              },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: isSelected
                        ? Colors.blueAccent
                        : (recomendado ? Colors.green.shade100 : Colors.orange.shade100),
                    child: Icon(
                      isSelected ? Icons.check : (recomendado ? Icons.verified : Icons.warning_amber),
                      color: isSelected
                          ? Colors.white
                          : (recomendado ? Colors.green.shade800 : Colors.orange.shade800),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      nombre,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: recomendado ? Colors.green.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      recomendado ? 'Recomendado' : 'No recomendado',
                      style: TextStyle(
                        color: recomendado ? Colors.green.shade800 : Colors.orange.shade800,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text('⭐ Puntuacion: ${puntuacion.toStringAsFixed(2)}  •  📍 ${_distanciaLabel(candidato)}'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _criterioChip(label: 'Servicio', ok: cumpleServicio),
                  _criterioChip(label: 'Activo', ok: activo),
                  _criterioChip(label: 'Capacidad', ok: capacidad),
                ],
              ),
              if (tecnicosDisponibles != null || transportesDisponibles != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Recursos: tecnicos ${tecnicosDisponibles ?? 0} • transportes ${transportesDisponibles ?? 0}',
                  style: TextStyle(color: Colors.grey[700], fontSize: 12),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Motivo: $razon',
                style: TextStyle(color: Colors.blue[800], fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recomendados = _candidatos.where(_esRecomendado).toList();
    final noRecomendados = _candidatos.where((c) => !_esRecomendado(c)).toList();

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Seleccion de Talleres'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _candidatos.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  'No se encontraron talleres candidatos cerca para tu problema. Intenta más tarde.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (recomendados.isNotEmpty) ...[
                  Text(
                    'Talleres recomendados',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...recomendados.map(_candidatoCard),
                ] else ...[
                  Card(
                    color: Colors.orange.shade50,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'No hay talleres que cumplan todos los criterios. Revisa las opciones no recomendadas.',
                      ),
                    ),
                  ),
                ],
                if (noRecomendados.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _mostrarNoRecomendadas = !_mostrarNoRecomendadas;
                      });
                    },
                    icon: Icon(
                      _mostrarNoRecomendadas
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                    ),
                    label: Text(
                      _mostrarNoRecomendadas
                          ? 'Ocultar Opciones no recomendadas (${noRecomendados.length})'
                          : 'Ver Opciones no recomendadas (${noRecomendados.length})',
                    ),
                  ),
                  if (_mostrarNoRecomendadas) ...[
                    const SizedBox(height: 8),
                    ...noRecomendados.map(_candidatoCard),
                  ],
                ],
              ],
            ),
      bottomNavigationBar: _candidatos.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.all(16.0),
              child: _isSubmitting
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                      onPressed: _requestSent ? null : _confirmarSeleccion,
                      icon: const Icon(Icons.send),
                      label: Text(
                        _requestSent
                            ? 'SOLICITUD ENVIADA'
                            : 'SOLICITAR AUXILIO A ${_talleresSeleccionados.length} SELECCIONADOS',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _talleresSeleccionados.isNotEmpty && !_requestSent
                            ? Colors.blueAccent
                            : Colors.grey,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
            )
          : null,
    );
  }
}
