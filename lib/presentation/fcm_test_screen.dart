import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../Services/firebase_options.dart';
import 'providers/auth_providers.dart';

/// Android debug tool; no staff login or backend is required.
class FcmTestScreen extends ConsumerStatefulWidget {
  const FcmTestScreen({super.key});

  @override
  ConsumerState<FcmTestScreen> createState() => _FcmTestScreenState();
}

class _FcmTestScreenState extends ConsumerState<FcmTestScreen> {
  String? _token;
  String? _error;
  bool _loading = false;

  Future<void> _generateToken() async {
    setState(() {
      _loading = true;
      _error = null;
      _token = null;
    });
    try {
      final token = await ref
          .read(medicalIssuePushServiceProvider)
          .getConsoleTestToken();
      if (mounted) setState(() => _token = token);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('FCM messaging test')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Firebase project: ${DefaultFirebaseOptions.android.projectId}'),
        const SizedBox(height: 16),
        const Text(
          'Generate a token and allow notifications. In Firebase Console, open '
          'Messaging, create a notification, choose Send test message, and paste '
          'this FCM registration token. No staff sign-in is required.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _loading ? null : _generateToken,
          icon: const Icon(Icons.notifications_active_outlined),
          label: Text(
            _loading ? 'Generating token…' : 'Generate / refresh token',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          SelectableText(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_token != null) ...[
          const SizedBox(height: 16),
          const Text('FCM registration token'),
          const SizedBox(height: 8),
          SelectableText(_token!),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _token!));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('FCM token copied')),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy token'),
          ),
        ],
        const SizedBox(height: 24),
        const Text(
          'Test once with Oravi open, once after pressing Home, and once with '
          'the phone locked. Foreground messages use a local notification; '
          'Android displays background notification messages. Tap the '
          'notification to reopen Oravi. A Console message without custom data '
          'opens the app without selecting a patient thread.\n\n'
          'Use an Android device or emulator with Google Play services and '
          'internet access. Do not Force stop the app during testing. '
          'Generate the token again after reinstalling or signing out.',
        ),
      ],
    ),
  );
}
