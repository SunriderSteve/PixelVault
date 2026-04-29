// PixelVault — Shared admin authentication utilities.
//
// Centralises the admin password, localStorage key, and password dialog
// so that any page needing admin gating can reuse the same logic.
//
// Admin state is shared app-wide via [adminNotifier]. Pages listen to
// this ValueNotifier so that logging in on any page immediately
// unlocks all other pages without requiring a second password entry.

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// localStorage key used to persist admin mode across reloads.
const String adminStorageKey = 'pv_admin_mode';

/// Client-side admin password.
///
/// This is a UI gate only — the source is visible in the shipped bundle.
/// Real authorisation must be enforced server-side on the gist endpoint.
const String adminPassword = 'PixelStudio#0301';

/// App-wide admin state. Pages should listen to this notifier so that
/// a login on any page propagates everywhere instantly.
final ValueNotifier<bool> adminNotifier = ValueNotifier<bool>(
  web.window.localStorage.getItem(adminStorageKey) == '1',
);

/// Returns `true` if admin mode is currently persisted in localStorage.
bool isAdminPersisted() =>
    web.window.localStorage.getItem(adminStorageKey) == '1';

/// Persist admin mode to localStorage and update the global notifier.
void setAdminPersisted(bool value) {
  if (value) {
    web.window.localStorage.setItem(adminStorageKey, '1');
  } else {
    web.window.localStorage.removeItem(adminStorageKey);
  }
  adminNotifier.value = value;
}

/// Shows the admin password dialog and returns `true` on success.
Future<bool> showAdminPasswordDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => const AdminPasswordDialog(),
  );
  return result == true;
}

/// Password prompt dialog for unlocking admin mode.
class AdminPasswordDialog extends StatefulWidget {
  const AdminPasswordDialog({super.key});

  @override
  State<AdminPasswordDialog> createState() => _AdminPasswordDialogState();
}

class _AdminPasswordDialogState extends State<AdminPasswordDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text == adminPassword) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _errorText = 'Incorrect Password');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey.shade900,
      title: const Text('Admin Access', style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: _controller,
        obscureText: true,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Enter Password',
          hintStyle: const TextStyle(color: Colors.white54),
          errorText: _errorText,
          errorStyle: const TextStyle(color: Colors.redAccent),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF0047BB)),
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Enter', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
