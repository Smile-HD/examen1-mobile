import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';

class PaymentScreen extends StatefulWidget {
  final int incidenteId;
  final String token;
  final double? suggestedAmount; // Monto sugerido desde las métricas

  const PaymentScreen({
    super.key,
    required this.incidenteId,
    required this.token,
    this.suggestedAmount,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  bool _isCreatingPayment = false;
  String? _errorMessage;
  Map<String, dynamic>? _paymentData;
  File? _proofImage;
  bool _isUploading = false;
  String? _uploadSuccessMessage;
  final TextEditingController _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-llenar el monto si viene sugerido desde las métricas
    if (widget.suggestedAmount != null && widget.suggestedAmount! > 0) {
      _amountController.text = widget.suggestedAmount!.toStringAsFixed(2);
    }
    // Cargar el pago existente si ya hay uno
    _loadExistingPayment();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  String _paymentsBaseUrl() {
    final baseUrl = dotenv.env['API_URL'] ?? 'http://10.0.2.2:8000/api/v1';
    // Mantener /api/v1 en la URL base para las rutas de pagos
    return baseUrl;
  }

  String _parseBackendError(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String && detail.isNotEmpty) {
          return detail;
        }
      }
    } catch (_) {
      // Respuesta no JSON.
    }
    return 'No se pudo completar la operación.';
  }

  String _absoluteUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return '';
    }

    final trimmed = raw.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    try {
      final origin = Uri.parse(_paymentsBaseUrl());
      if (trimmed.startsWith('/')) {
        return '${origin.scheme}://${origin.host}${origin.hasPort ? ':${origin.port}' : ''}$trimmed';
      }
      return '${origin.scheme}://${origin.host}${origin.hasPort ? ':${origin.port}' : ''}/$trimmed';
    } catch (_) {
      return trimmed;
    }
  }

  Future<void> _loadExistingPayment() async {
    try {
      final url = Uri.parse('${_paymentsBaseUrl()}/payments/client');

      final response = await http
          .get(
            url,
            headers: {
              'Authorization': 'Bearer ${widget.token}',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic> && data['payments'] is List) {
          final payments = data['payments'] as List;
          // Buscar el pago de este incidente
          for (final payment in payments) {
            if (payment is Map<String, dynamic> &&
                payment['incident_id'] == widget.incidenteId) {
              if (mounted) {
                setState(() {
                  _paymentData = payment;
                  // Si el pago está rechazado, permitir crear uno nuevo o reenviar comprobante
                  if (payment['status'] == 'rechazado') {
                    _errorMessage = 
                        'El pago anterior fue rechazado. Puedes reenviar el comprobante o crear un nuevo pago.';
                  }
                });
              }
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error cargando pago existente: $e');
    }
  }

  Future<void> _createPayment() async {
    if (_isCreatingPayment) {
      return;
    }

    final rawAmount = _amountController.text.trim();
    final amount = double.tryParse(rawAmount);
    if (amount == null || amount <= 0) {
      setState(() {
        _errorMessage = 'Ingresa un monto válido mayor a 0.';
      });
      return;
    }

    setState(() {
      _isCreatingPayment = true;
      _errorMessage = null;
    });

    try {
      final url = Uri.parse('${_paymentsBaseUrl()}/payments/create');

      final response = await http
          .post(
            url,
            headers: {
              'Authorization': 'Bearer ${widget.token}',
              'Content-Type': 'application/json',
            },
            body: json.encode({
              'incident_id': widget.incidenteId,
              'amount': amount,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          final responseData = json.decode(response.body);
          debugPrint('=== DEBUG CREATE PAYMENT RESPONSE ===');
          debugPrint('Response: $responseData');
          debugPrint('=====================================');
          setState(() {
            _paymentData = responseData;
            _errorMessage = null;
          });
        }
      } else {
        if (mounted) {
          final errorMsg = _parseBackendError(response.body);
          setState(() {
            _errorMessage = errorMsg;
            // Si el error indica que ya existe un pago rechazado, mostrar opción de reenvío
            if (errorMsg.contains('rechazado')) {
              _loadExistingPayment();
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error de red al crear el pago: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingPayment = false;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Seleccionar de galería'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Tomar foto'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) {
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _proofImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _uploadProof() async {
    if (_proofImage == null || _paymentData == null) {
      return;
    }

    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    try {
      final url = Uri.parse('${_paymentsBaseUrl()}/payments/upload-proof');

      final request = http.MultipartRequest('POST', url);
      request.headers['Authorization'] = 'Bearer ${widget.token}';
      request.fields['payment_id'] = _paymentData!['payment_id'].toString();
      request.files.add(
        await http.MultipartFile.fromPath('file', _proofImage!.path),
      );

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        if (mounted) {
          final payload = json.decode(response.body) as Map<String, dynamic>;
          setState(() {
            _isUploading = false;
            _uploadSuccessMessage =
                payload['message'] as String? ??
                'Comprobante enviado. Esperando verificación del taller.';
            _paymentData!['status'] = payload['status'] ?? 'verificacion';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = _parseBackendError(response.body);
            _isUploading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error de red al subir comprobante: $e';
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _downloadQrImage(String imageUrl) async {
    try {
      // Mostrar indicador de carga
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 16),
                Text('Descargando QR...'),
              ],
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Descargar la imagen
      final response = await http.get(Uri.parse(imageUrl));
      
      if (response.statusCode != 200) {
        throw Exception('Error al descargar la imagen');
      }

      // Obtener directorio de descargas
      Directory? directory;
      if (Platform.isAndroid) {
        // En Android, usar el directorio de descargas público
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else {
        // En iOS, usar el directorio de documentos de la app
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory == null) {
        throw Exception('No se pudo acceder al almacenamiento');
      }

      // Crear nombre de archivo único
      final fileName = 'qr_pago_${_paymentData!['payment_id']}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = '${directory.path}/$fileName';

      // Guardar archivo
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('QR guardado en: ${Platform.isAndroid ? 'Descargas' : 'Documentos'}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error descargando QR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al descargar: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final qrAbsoluteUrl = _absoluteUrl(
      (_paymentData?['qr_image_url_absolute'] ?? _paymentData?['qr_image_url'])
          ?.toString(),
    );

    // DEBUG: Imprimir información del QR
    if (_paymentData != null) {
      debugPrint('=== DEBUG QR ===');
      debugPrint('qr_image_url: ${_paymentData?['qr_image_url']}');
      debugPrint('qr_image_url_absolute: ${_paymentData?['qr_image_url_absolute']}');
      debugPrint('qrAbsoluteUrl construido: $qrAbsoluteUrl');
      debugPrint('================');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Realizar Pago'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_paymentData == null) ...[
              const Text(
                'Crear Pago',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Ingresa el monto a pagar para generar el pago y mostrar el QR del taller asignado.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Monto del servicio',
                  hintText: 'Ej. 150.00',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _isCreatingPayment ? null : _createPayment,
                icon: const Icon(Icons.qr_code),
                label: Text(
                  _isCreatingPayment
                      ? 'Creando pago...'
                      : 'Crear pago y mostrar QR',
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ],
            ] else ...[
              // Mostrar estado del pago existente
              if (_paymentData!['status'] == 'rechazado') ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: const Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.cancel, color: Colors.red),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Pago Rechazado',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        'El taller rechazó tu comprobante. Por favor, sube un nuevo comprobante de pago.',
                        style: TextStyle(color: Colors.black87),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
              if (_uploadSuccessMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _uploadSuccessMessage!,
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Volver al Dashboard'),
                ),
              ] else ...[
                const Text(
                  'Detalles del Pago',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Monto Total:',
                              style: TextStyle(fontSize: 16),
                            ),
                            Text(
                              'Bs. ${_paymentData!['amount']}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueAccent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Referencia: ${_paymentData!['reference'] ?? '-'}',
                        ),
                        Text('Estado: ${_paymentData!['status'] ?? '-'}'),
                        const Divider(height: 24),
                        const Text(
                          'Escanea el código QR del taller para realizar el pago desde tu aplicación bancaria.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 16),
                        if (qrAbsoluteUrl.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Image.network(
                              qrAbsoluteUrl,
                              height: 300,
                              width: 300,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Column(
                                    children: [
                                      Icon(
                                        Icons.qr_code_scanner,
                                        size: 100,
                                        color: Colors.grey,
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'Error al cargar QR',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ],
                                  ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => _downloadQrImage(qrAbsoluteUrl),
                            icon: const Icon(Icons.download),
                            label: const Text('Descargar QR'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ] else
                          const Column(
                            children: [
                              Icon(
                                Icons.qr_code_scanner,
                                size: 100,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'QR no disponible',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Confirmación de Pago',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Una vez realizado el pago, por favor sube el comprobante (captura de pantalla o recibo).',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 16),
                if (_proofImage != null)
                  Stack(
                    alignment: Alignment.topRight,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          _proofImage!,
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.red),
                        onPressed: () => setState(() => _proofImage = null),
                      ),
                    ],
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.image),
                    label: const Text('Seleccionar Comprobante'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _proofImage == null || _isUploading
                      ? null
                      : _uploadProof,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                  child: _isUploading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Enviar Comprobante',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
