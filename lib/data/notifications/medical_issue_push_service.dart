import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../Services/firebase_options.dart';
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

class CallAlert {
  final String callId;

  const CallAlert({required this.callId});
}

class MedicalIssuePushService {
  static const _channelId = 'medical_issue_alerts';
  static const _callCredentialKey = 'oravi_call_credential';
  static const _callCredentialStorage = FlutterSecureStorage();
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final StreamController<MedicalIssueAlert> _openedAlerts =
      StreamController<MedicalIssueAlert>.broadcast();
  final StreamController<CallAlert> _openedCalls =
      StreamController<CallAlert>.broadcast();
  StreamSubscription<RemoteMessage>? _foregroundMessages;
  StreamSubscription<RemoteMessage>? _openedMessages;
  StreamSubscription<String>? _tokenRefreshSubscription;
  bool _localNotificationsInitialized = false;
  bool _initialMessageChecked = false;
  Future<void>? _initialization;
  Future<void> _pendingTokenRegistration = Future<void>.value();

  Stream<MedicalIssueAlert> get openedAlerts => _openedAlerts.stream;
  Stream<CallAlert> get openedCalls => _openedCalls.stream;
  final StreamController<void> _openedInbox =
      StreamController<void>.broadcast();
  Stream<void> get openedInbox => _openedInbox.stream;

  /// Set up delivery independently of staff authentication.
  Future<void> initialize() async {
    await (_initialization ??= _initialize().catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _initialization = null;
      Error.throwWithStackTrace(error, stackTrace);
    }));
    _listenForMessages(FirebaseMessaging.instance);
  }

  Future<void> _initialize() async {
    _supportedPlatform;
    await _initializeFirebase();
    await _initializeLocalNotifications();
  }

  /// Use registration tokens consistently for Console and backend delivery.
  /// Android's installation ID mode must remain disabled in the manifest.
  Future<String> getConsoleTestToken() async {
    await initialize();
    final messaging = FirebaseMessaging.instance;
    await _requestNotificationPermission(messaging);
    final token = await _getRegistrationToken(messaging);
    if (kDebugMode) {
      debugPrint('ORAVI_FCM_TOKEN: $token', wrapWidth: 1024);
    }
    return token;
  }

  Future<void> _requestNotificationPermission(
    FirebaseMessaging messaging,
  ) async {
    final permission = await messaging.requestPermission();
    if (permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      throw StateError(
        'Allow Oravi notifications in Android app settings, then retry.',
      );
    }
  }

  Future<String> _getRegistrationToken(FirebaseMessaging messaging) async {
    // FlutterFire 17 deprecates this in favor of FID registration. We retain
    // token mode for Firebase Console and the backend's Message(token: ...).
    // ignore: deprecated_member_use
    final token = await messaging.getToken().timeout(
      const Duration(seconds: 30),
    );
    if (token == null || token.isEmpty) {
      throw StateError('Firebase did not return an FCM registration token.');
    }
    return token;
  }

  Future<void> register({
    required String accessToken,
    required String deviceId,
    required void Function(String message) onError,
  }) async {
    final platform = _supportedPlatform;
    await initialize();
    final messaging = FirebaseMessaging.instance;

    await _requestNotificationPermission(messaging);

    final api = WardBoardService(getAccessToken: () => accessToken);
    Future<void> registerToken(String token) {
      final operation = _pendingTokenRegistration.then((_) async {
        final callCredential = await api.registerFcmInstallation(
          token: token,
          deviceId: deviceId,
          platform: platform,
        );
        await _callCredentialStorage.write(
          key: _callCredentialKey,
          value: callCredential,
        );
      });
      // Keep later refreshes usable even if one backend request fails.
      _pendingTokenRegistration = operation.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {},
      );
      return operation;
    }

    await _tokenRefreshSubscription?.cancel();
    // ignore: deprecated_member_use
    _tokenRefreshSubscription = messaging.onTokenRefresh.listen(
      (token) async {
        try {
          await registerToken(token);
        } catch (error) {
          onError('Device token refresh failed (${error.runtimeType}).');
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        onError('Device token refresh failed (${error.runtimeType}).');
      },
    );

    // getToken can return a cached token without emitting a refresh event.
    // Always register it explicitly when a staff member signs in.
    final token = await _getRegistrationToken(messaging);
    await registerToken(token);
  }

  Future<void> unregister({
    required String accessToken,
    required String deviceId,
  }) async {
    if (Firebase.apps.isEmpty) return;
    // Stop refresh registration before removing the signed-in installation.
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    // A refresh callback already in progress must finish before deletion.
    await _pendingTokenRegistration;
    final api = WardBoardService(getAccessToken: () => accessToken);
    Object? error;
    try {
      await api.removeFcmInstallation(deviceId: deviceId);
    } catch (caught) {
      error = caught;
    }
    await _foregroundMessages?.cancel();
    _foregroundMessages = null;
    await _openedMessages?.cancel();
    _openedMessages = null;
    try {
      // ignore: deprecated_member_use
      await FirebaseMessaging.instance.deleteToken();
    } catch (caught) {
      error ??= caught;
    }
    await _callCredentialStorage.delete(key: _callCredentialKey);
    if (error != null) {
      throw StateError('Could not fully remove the device token.');
    }
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _foregroundMessages?.cancel();
    await _openedMessages?.cancel();
    await _openedAlerts.close();
    await _openedCalls.close();
    await _openedInbox.close();
  }

  Future<String?> readCallCredential() {
    return _callCredentialStorage.read(key: _callCredentialKey);
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
        android: AndroidInitializationSettings('ic_notification'),
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
    final launch = await _localNotifications.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      _publishOpenedPayload(launch?.notificationResponse?.payload);
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null && message.data.isEmpty) return;
    await _localNotifications.show(
      id:
          (message.messageId?.hashCode ??
              DateTime.now().millisecondsSinceEpoch) &
          0x7fffffff,
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
      if (data is! Map<String, dynamic>) {
        return;
      }
      if (data['type'] == 'staff_message') {
        _openedInbox.add(null);
        return;
      }
      if (data['type'] == 'oravi_call' && data['call_id'] is String) {
        if (!_openedCalls.isClosed) {
          _openedCalls.add(CallAlert(callId: data['call_id'] as String));
        }
        return;
      }
      if (data['type'] != 'medical_issue' ||
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
