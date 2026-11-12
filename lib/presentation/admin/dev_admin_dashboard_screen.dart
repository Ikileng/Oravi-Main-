import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/staff_profile.dart';
import '../providers/auth_providers.dart';
import 'ward_configuration_screen.dart';

const _roles = {
  'ward_nurse': 'Nurse',
  'doctor_on_call': 'Doctor',
  'charge_nurse': 'Charge Nurse',
};

final adminStaffDirectoryProvider = FutureProvider<List<StaffProfile>>((ref) {
  final token = ref.watch(authAccessTokenProvider);
  final staff = ref.watch(authenticatedStaffProvider);
  if (token == null || staff?.role != 'dev_admin') return [];
  return ref.watch(staffAuthServiceProvider).getProvisionedStaff(token);
});

/// Account administration only. Clinical data and allocation controls are not
/// loaded by this screen; the backend separately denies clinical access.
class DevAdminDashboardScreen extends ConsumerStatefulWidget {
  const DevAdminDashboardScreen({super.key});

  @override
  ConsumerState<DevAdminDashboardScreen> createState() =>
      _DevAdminDashboardScreenState();
}

class _DevAdminDashboardScreenState
    extends ConsumerState<DevAdminDashboardScreen> {
  String _search = '';
  String _role = 'all';
  String _status = 'all';
  bool _busy = false;

  Future<void> _createUser() async {
    final form = GlobalKey<FormState>();
    final name = TextEditingController();
    final staffId = TextEditingController();
    final pin = TextEditingController();
    String role = 'ward_nurse';
    String? error;
    bool saving = false;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, update) => AlertDialog(
            title: const Text('Create new user'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Form(
                  key: form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: name,
                        maxLength: 120,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter the staff member’s name.'
                            : null,
                      ),
                      TextFormField(
                        controller: staffId,
                        maxLength: 80,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Staff ID',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter a unique staff ID.'
                            : null,
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: role,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: _roles.entries
                            .map(
                              (entry) => DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.value),
                              ),
                            )
                            .toList(),
                        onChanged: saving
                            ? null
                            : (value) => update(() => role = value!),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: pin,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(8),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Initial PIN',
                          helperText:
                              '4–8 digits. Share privately with the user.',
                        ),
                        validator: (value) =>
                            value == null ||
                                !RegExp(r'^[0-9]{4,8}$').hasMatch(value)
                            ? 'Enter a PIN containing 4–8 digits.'
                            : null,
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!form.currentState!.validate()) return;
                        update(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          final token = ref.read(authAccessTokenProvider);
                          if (token == null) {
                            throw StateError('Sign in again to create users.');
                          }
                          await ref
                              .read(staffAuthServiceProvider)
                              .createClinicalStaff(
                                token: token,
                                staffId: staffId.text.trim(),
                                name: name.text.trim(),
                                role: role,
                                pin: pin.text,
                              );
                          if (!mounted || !dialogContext.mounted) return;
                          ref.invalidate(adminStaffDirectoryProvider);
                          Navigator.pop(dialogContext);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Staff account created and activated.',
                              ),
                            ),
                          );
                        } catch (failure) {
                          if (dialogContext.mounted) {
                            update(() {
                              saving = false;
                              error = failure.toString();
                            });
                          }
                        }
                      },
                child: Text(saving ? 'Creating…' : 'Create user'),
              ),
            ],
          ),
        ),
      );
    } finally {
      // The dialog route finishes its exit animation before controllers go away.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      name.dispose();
      staffId.dispose();
      pin.dispose();
    }
  }

  Future<void> _manageUser(StaffProfile user, String action) async {
    final deleting = action == 'delete';
    final activating = action == 'activate';
    final label = deleting
        ? 'Delete permanently'
        : activating
        ? 'Reactivate'
        : 'Deactivate';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$label ${user.staffId}?'),
        content: Text(
          deleting
              ? 'This permanently removes ${user.name}’s account and revokes access. It cannot be undone, and this staff ID cannot be reused. Historical clinical records are retained.'
              : activating
              ? '${user.name} will be able to sign in again with their existing PIN.'
              : '${user.name} will be unable to sign in. Existing sessions are revoked. You can reactivate this account later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(label),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final token = ref.read(authAccessTokenProvider);
      if (token == null) throw StateError('Sign in again to manage users.');
      final api = ref.read(staffAuthServiceProvider);
      if (deleting) {
        await api.deleteStaff(token: token, staffId: user.staffId);
      } else {
        await api.setStaffActive(
          token: token,
          staffId: user.staffId,
          active: activating,
        );
      }
      if (!mounted) return;
      ref.invalidate(adminStaffDirectoryProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${user.staffId}: ${deleting
                ? 'account deleted'
                : activating
                ? 'account reactivated'
                : 'account deactivated'}.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Account update failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = ref.watch(authenticatedStaffProvider);
    if (admin?.role != 'dev_admin') {
      return const Scaffold(
        body: Center(child: Text('Dev Admin sign-in required.')),
      );
    }
    final directory = ref.watch(adminStaffDirectoryProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Staff administration'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () {
              ref.read(authControllerProvider.notifier).logout();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(adminStaffDirectoryProvider);
                await ref.read(adminStaffDirectoryProvider.future);
              },
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    'Oravi Hospital',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text('Signed in as ${admin!.name} · Dev Admin'),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _createUser,
                      icon: const Icon(Icons.person_add_outlined),
                      label: const Text('Create new user'),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const WardConfigurationScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Configure wards'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Staff directory',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Search by name or staff ID',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) =>
                        setState(() => _search = value.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 20,
                    runSpacing: 8,
                    children: [
                      DropdownButton<String>(
                        value: _role,
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Text('All roles'),
                          ),
                          ..._roles.entries.map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          ),
                        ],
                        onChanged: (value) => setState(() => _role = value!),
                      ),
                      DropdownButton<String>(
                        value: _status,
                        items: const [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('All statuses'),
                          ),
                          DropdownMenuItem(
                            value: 'active',
                            child: Text('Active'),
                          ),
                          DropdownMenuItem(
                            value: 'inactive',
                            child: Text('Inactive'),
                          ),
                        ],
                        onChanged: (value) => setState(() => _status = value!),
                      ),
                      IconButton(
                        tooltip: 'Refresh directory',
                        onPressed: () =>
                            ref.invalidate(adminStaffDirectoryProvider),
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  directory.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => Column(
                      children: [
                        Text('Could not load the staff directory: $error'),
                        TextButton(
                          onPressed: () =>
                              ref.invalidate(adminStaffDirectoryProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                    data: (users) {
                      final filtered = users
                          .where(
                            (user) =>
                                _roles.containsKey(user.role) &&
                                (_role == 'all' || user.role == _role) &&
                                (_status == 'all' ||
                                    user.isActive == (_status == 'active')) &&
                                (_search.isEmpty ||
                                    user.name.toLowerCase().contains(_search) ||
                                    user.staffId.toLowerCase().contains(
                                      _search,
                                    )),
                          )
                          .toList();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('${filtered.length} staff shown'),
                          const SizedBox(height: 8),
                          if (filtered.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'No staff match these filters. Create a user or change the filters.',
                              ),
                            ),
                          for (final user in filtered)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    child: Text(user.initials),
                                  ),
                                  title: Text(user.name),
                                  subtitle: Text(
                                    '${user.staffId}\n${_roles[user.role]} · ${user.isActive ? 'Active' : 'Inactive'}',
                                  ),
                                  isThreeLine: true,
                                  trailing: PopupMenuButton<String>(
                                    enabled: !_busy,
                                    tooltip: 'Manage ${user.staffId}',
                                    onSelected: (action) =>
                                        _manageUser(user, action),
                                    itemBuilder: (_) => [
                                      PopupMenuItem(
                                        value: user.isActive
                                            ? 'deactivate'
                                            : 'activate',
                                        child: Text(
                                          user.isActive
                                              ? 'Deactivate'
                                              : 'Reactivate',
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Delete permanently'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
