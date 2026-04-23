import 'dart:convert';
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

class PushRegistrationException implements Exception {
  final String message;

  PushRegistrationException(this.message);

  @override
  String toString() => message;
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // No-op: Android/iOS mostrará la notificación si viene en el bloque notification.
  if (Firebase.apps.isEmpty) {
    try {
      await Firebase.initializeApp();
    } catch (_) {
      return;
    }
  }
}

class PushNotificationsService {
  PushNotificationsService._();

  static final PushNotificationsService instance = PushNotificationsService._();
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _foregroundChannel =
      AndroidNotificationChannel(
        'emergencias_push_foreground',
        'Notificaciones de Emergencia',
        description: 'Notificaciones push en primer plano',
        importance: Importance.high,
      );

  bool _initialized = false;
  String? _lastAuthToken;

  static Future<void> setupFirebaseForPush() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _localNotifications.initialize(initSettings);

      final androidImplementation = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidImplementation?.requestNotificationsPermission();
      await androidImplementation?.createNotificationChannel(
        _foregroundChannel,
      );

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('Push setupFirebaseForPush error: $e');
      // Si Firebase no está configurado (google-services/json), la app sigue sin push.
    }
  }

  Future<void> initForClient({
    required String authToken,
    required void Function(String title, String body)? onForegroundNotification,
  }) async {
    _lastAuthToken = authToken;

    if (Firebase.apps.isEmpty) {
      throw PushRegistrationException(
        'Firebase no está inicializado en la app mobile.',
      );
    }

    final messaging = FirebaseMessaging.instance;

    final permission = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    final denied =
        permission.authorizationStatus == AuthorizationStatus.denied ||
        permission.authorizationStatus == AuthorizationStatus.notDetermined;
    if (denied) {
      throw PushRegistrationException(
        'Permiso de notificaciones no concedido en el dispositivo.',
      );
    }

    await messaging.setAutoInitEnabled(true);

    final token = await _getTokenWithRetry(messaging);
    if (token == null || token.trim().isEmpty) {
      throw PushRegistrationException(
        'No se pudo obtener token FCM del dispositivo.',
      );
    }

    await _registerToken(token: token.trim(), authToken: authToken);
    debugPrint('Push token registrado OK. tokenLen=${token.trim().length}');

    FirebaseMessaging.instance.onTokenRefresh.listen((freshToken) {
      final normalized = freshToken.trim();
      final auth = _lastAuthToken;
      if (normalized.isEmpty || auth == null || auth.isEmpty) {
        return;
      }

      unawaited(
        _registerToken(token: normalized, authToken: auth).catchError((e) {
          debugPrint('Push onTokenRefresh register error: $e');
        }),
      );
    });

    if (_initialized) {
      return;
    }

    FirebaseMessaging.onMessage.listen((message) {
      final title = message.notification?.title?.trim();
      final body = message.notification?.body?.trim();
      final safeTitle = (title == null || title.isEmpty)
          ? 'Actualización de solicitud'
          : title;
      final safeBody = (body == null || body.isEmpty)
          ? 'Tu solicitud tiene una novedad.'
          : body;

      unawaited(_showForegroundLocalNotification(safeTitle, safeBody));
      onForegroundNotification?.call(safeTitle, safeBody);
    });

    _initialized = true;
  }

  Future<void> _registerToken({
    required String token,
    required String authToken,
  }) async {
    final rawBaseUrl = dotenv.env['API_URL'] ?? 'http://10.0.2.2:8000/api/v1';
    final baseUrl = rawBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$baseUrl/notificaciones/push-token');

    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
            body: json.encode({'token': token, 'plataforma': 'flutter_mobile'}),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw PushRegistrationException(
          'Backend rechazó registro push (${response.statusCode}): ${response.body}',
        );
      }

      final payload = json.decode(response.body);
      final isRegistered = payload is Map<String, dynamic>
          ? (payload['token_registrado'] == true)
          : false;

      if (!isRegistered) {
        throw PushRegistrationException(
          'Backend respondió sin confirmar token_registrado=true.',
        );
      }
    } on TimeoutException {
      throw PushRegistrationException(
        'Timeout registrando token push en backend.',
      );
    } catch (e) {
      if (e is PushRegistrationException) {
        rethrow;
      }
      throw PushRegistrationException('Error registrando token push: $e');
    }
  }

  Future<String?> _getTokenWithRetry(FirebaseMessaging messaging) async {
    Object? lastError;

    for (var attempt = 1; attempt <= 6; attempt++) {
      try {
        final token = await messaging.getToken();
        if (token != null && token.trim().isNotEmpty) {
          return token;
        }
        debugPrint('Push getToken intento=$attempt sin token.');
      } catch (e) {
        lastError = e;
        final normalized = e.toString().toUpperCase();
        final isServiceUnavailable =
            normalized.contains('SERVICE_NOT_AVAILABLE') ||
            normalized.contains('UNAVAILABLE');

        debugPrint('Push getToken intento=$attempt error=$e');

        if (!isServiceUnavailable) {
          rethrow;
        }
      }

      if (attempt < 6) {
        await Future<void>.delayed(Duration(milliseconds: 700 * attempt));
      }
    }

    if (lastError != null) {
      throw PushRegistrationException(
        'Firebase respondió SERVICE_NOT_AVAILABLE al obtener token. '
        'Verifica conexión a Internet y Google Play Services actualizados.',
      );
    }

    return null;
  }

  Future<void> _showForegroundLocalNotification(
    String title,
    String body,
  ) async {
    const androidDetails = AndroidNotificationDetails(
      'emergencias_push_foreground',
      'Notificaciones de Emergencia',
      channelDescription: 'Notificaciones push en primer plano',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );

    const details = NotificationDetails(android: androidDetails);
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
    );
  }
}
