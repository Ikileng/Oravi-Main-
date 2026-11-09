import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../firebase_options.dart';
import '../ward_board_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}

class MedicalIssueAlert {
  final String patientId;
  final String loopId;

  const MedicalIssueAlert({required this.patientId, required this.loopId});
}

class MedicalIssuePushService {
  static const _channelId = 'medical_issue_alerts';
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final StreamController<MedicalIssueAlert> _openedAlerts =
      StreamController<MedicalIssueAlert>.broadcast();
  StreamSubscription<RemoteMessage>? _foregroundMessages;
  StreamSubscription<RemoteMessage>? _openedMessages;
  StreamSubscription<String>? _registrationEvents;
  bool _localNotificationsInitialized = false;
  bool _initialMessageChecked = false;

  Stream<MedicalIssueAlert> get openedAlerts => _openedAlerts.stream;

  Future<void> register({
    required String accessToken,
    required String deviceId,
    required void Function(String message) onError,
  }) async {
    final platform = _supportedPlatform;
    await _initializeFirebase();
    final messaging = FirebaseMessaging.instance;
    await _initializeLocalNotifications();
    _listenForMessages(messaging);

    final permission = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      throw StateError('Notification permission was not granted.');
    }

    final api = WardBoardService(getAccessToken: () => accessToken);
    final firstRegistration = Completer<void>();
    var registeredAtLeastOnce = false;
    await _registrationEvents?.cancel();
    _registrationEvents = messaging.onRegistered.listen(
      (fid) async {
        try {
          if (fid.isEmpty) {
            throw StateError('Firebase returned an empty installation ID.');
          }
          await api.registerFcmInstallation(
            fid: fid,
            deviceId: deviceId,
            platform: platform,
          );
          if (!registeredAtLeastOnce) {
            registeredAtLeastOnce = true;
            firstRegistration.complete();
          }
        } catch (error) {
          if (!registeredAtLeastOnce) {
            registeredAtLeastOnce = true;
            firstRegistration.completeError(error);
          } else {
            onError(
              'Device registration refresh failed (${error.runtimeType}).',
            );
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!registeredAtLeastOnce) {
          registeredAtLeastOnce = true;
          firstRegistration.completeError(error, stackTrace);
        } else {
          onError('Device registration refresh failed (${error.runtimeType}).');
        }
      },
    );
    await messaging.register();
    await firstRegistration.future.timeout(const Duration(seconds: 20));
  }

  Future<void> unregister({
    required String accessToken,
    required String deviceId,
  }) async {
    if (Firebase.apps.isEmpty) return;
    final api = WardBoardService(getAccessToken: () => accessToken);
    Object? error;
    try {
      await api.removeFcmInstallation(deviceId: deviceId);
    } catch (caught) {
      error = caught;
    }
    await _registrationEvents?.cancel();
    _registrationEvents = null;
    await _foregroundMessages?.cancel();
    _foregroundMessages = null;
    await _openedMessages?.cancel();
    _openedMessages = null;
    try {
      await FirebaseMessaging.instance.unregister();
    } catch (caught) {
      error ??= caught;
    }
    if (error != null) {
      throw StateError('Could not fully remove the device token.');
    }
  }

  Future<void> dispose() async {
    await _registrationEvents?.cancel();
    await _foregroundMessages?.cancel();
    await _openedMessages?.cancel();
    await _openedAlerts.close();
  }

  String get _supportedPlatform {
    if (kIsWeb) {
      throw StateError('Push alerts are not supported on the web deployment.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        throw StateError('Push alerts are not supported on this platform.');
    }
  }

  Future<void> _initializeFirebase() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  void _listenForMessages(FirebaseMessaging messaging) {
    _foregroundMessages ??= FirebaseMessaging.onMessage.listen((message) async {
      try {
        await _showForegroundNotification(message);
      } catch (error) {
        debugPrint(
          'Could not display a foreground Medical Issue alert '
          '(${error.runtimeType}).',
        );
      }
    });
    _openedMessages ??= FirebaseMessaging.onMessageOpenedApp.listen(
      _publishOpenedAlert,
    );
    if (!_initialMessageChecked) {
      _initialMessageChecked = true;
      unawaited(
        messaging.getInitialMessage().then(
          (message) {
            if (message != null) _publishOpenedAlert(message);
          },
          onError: (Object error) {
            debugPrint(
              'Could not read the initial FCM notification '
              '(${error.runtimeType}).',
            );
          },
        ),
      );
    }
  }

  Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsInitialized) return;
    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        _publishOpenedPayload(response.payload);
      },
    );
    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        'Medical Issue alerts',
        description: 'Alerts for patient-linked Medical Issues.',
        importance: Importance.max,
      ),
    );
    _localNotificationsInitialized = true;
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null && message.data.isEmpty) return;
    await _localNotifications.show(
      id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: notification?.title ?? 'Medical issue update',
      body:
          notification?.body ??
          'A medical issue requires your attention. Open Oravi to review.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Medical Issue alerts',
          channelDescription: 'Alerts for patient-linked Medical Issues.',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _publishOpenedAlert(RemoteMessage message) {
    _publishOpenedPayload(jsonEncode(message.data));
  }

  void _publishOpenedPayload(String? payload) {
    if (payload == null || payload.isEmpty || _openedAlerts.isClosed) return;
    try {
      final data = jsonDecode(payload);
      if (data is! Map<String, dynamic> ||
          data['type'] != 'medical_issue' ||
          data['patient_id'] is! String ||
          data['loop_id'] is! String) {
        return;
      }
      _openedAlerts.add(
        MedicalIssueAlert(
          patientId: data['patient_id'] as String,
          loopId: data['loop_id'] as String,
        ),
      );
    } on FormatException {
      return;
    }
  }
}
