import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/access_failure.dart';
import '../../models/password_rules.dart';
import '../../providers/auth_providers.dart';

class PasswordDialog extends ConsumerStatefulWidget {
  const PasswordDialog({super.key, required this.userId});
  final String userId;
  @override
  ConsumerState<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends ConsumerState<PasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _saving = false;
  bool _obscure = true;
  String? _error;
  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          .updatePassword(widget.userId, _password.text);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = accessErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Cambia password'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _password,
                  enabled: !_saving,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: 'Nuova password',
                    helperText: 'Almeno 8 caratteri.',
                    suffixIcon: IconButton(
                      tooltip: _obscure
                          ? 'Mostra password'
                          : 'Nascondi password',
                      onPressed: _saving
                          ? null
                          : () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                    ),
                  ),
                  validator: passwordError,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmation,
                  enabled: !_saving,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Conferma password',
                  ),
                  validator: (value) => value == _password.text
                      ? null
                      : 'Le password non coincidono.',
                  onFieldSubmitted: (_) => _save(),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_saving) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Salva password'),
        ),
      ],
    ),
  );
}
