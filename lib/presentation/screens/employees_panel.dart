import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/access_failure.dart';
import '../../models/planning.dart';
import '../../providers/employee_providers.dart';

class EmployeesPanel extends ConsumerStatefulWidget {
  const EmployeesPanel({super.key, required this.userId});
  final String userId;
  @override
  ConsumerState<EmployeesPanel> createState() => _EmployeesPanelState();
}

class _EmployeesPanelState extends ConsumerState<EmployeesPanel> {
  bool _showInactive = false;
  bool _busy = false;
  String? _error;

  Future<void> _edit(UserProfile employee) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _EmployeeEditor(userId: widget.userId, employee: employee),
    );
    if (saved == true && mounted) {
      ref.invalidate(employeesProvider(widget.userId));
    }
  }

  Future<void> _toggle(UserProfile employee) async {
    if (employee.active) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Disattivare il dipendente?'),
          content: Text(
            '${employee.fullName} non potrà più consultare i dati dell’app. Le assegnazioni esistenti saranno conservate.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Disattiva'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = await ref.read(
        employeeServiceProvider(widget.userId).future,
      );
      await service.setActive(employee, !employee.active);
      if (mounted) ref.invalidate(employeesProvider(widget.userId));
    } catch (error) {
      if (mounted) setState(() => _error = accessErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final employees = ref.watch(employeesProvider(widget.userId));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Gestisci i dati e l’accesso dei dipendenti del tuo ufficio.',
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () {
                        setState(() => _error = null);
                        ref.invalidate(employeesProvider(widget.userId));
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('Aggiorna elenco'),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mostra anche i disattivati'),
              value: _showInactive,
              onChanged: (value) => setState(() => _showInactive = value),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            employees.when(
              skipLoadingOnRefresh: false,
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, stack) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(accessErrorMessage(error)),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(employeesProvider(widget.userId)),
                    child: const Text('Riprova'),
                  ),
                ],
              ),
              data: (all) {
                final visible = all
                    .where((employee) => _showInactive || employee.active)
                    .toList();
                if (visible.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      all.isEmpty
                          ? 'Nessun dipendente presente. Gli account amministratore non compaiono in questo elenco.'
                          : 'Nessun dipendente attivo. Attiva il filtro per visualizzare i disattivati.',
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final employee in visible)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                employee.fullName,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(employee.email),
                              if (!employee.active)
                                const Chip(label: Text('Disattivato')),
                              Wrap(
                                spacing: 12,
                                children: [
                                  TextButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _edit(employee),
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Modifica'),
                                  ),
                                  TextButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _toggle(employee),
                                    icon: Icon(
                                      employee.active
                                          ? Icons.pause_circle_outline
                                          : Icons.play_circle_outline,
                                    ),
                                    label: Text(
                                      employee.active
                                          ? 'Disattiva'
                                          : 'Riattiva',
                                    ),
                                  ),
                                ],
                              ),
                            ],
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
    );
  }
}

class _EmployeeEditor extends ConsumerStatefulWidget {
  const _EmployeeEditor({required this.userId, required this.employee});
  final String userId;
  final UserProfile employee;
  @override
  ConsumerState<_EmployeeEditor> createState() => _EmployeeEditorState();
}

class _EmployeeEditorState extends ConsumerState<_EmployeeEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _first, _last;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _first = TextEditingController(text: widget.employee.firstName);
    _last = TextEditingController(text: widget.employee.lastName);
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  String? _validate(String? value) =>
      value == null || value.trim().isEmpty || value.trim().runes.length > 120
      ? 'Inserisci da 1 a 120 caratteri.'
      : null;

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final service = await ref.read(
        employeeServiceProvider(widget.userId).future,
      );
      await service.rename(widget.employee, _first.text, _last.text);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = accessErrorMessage(error);
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Modifica dipendente'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _first,
                  enabled: !_saving,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Nome'),
                  validator: _validate,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _last,
                  enabled: !_saving,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _save(),
                  decoration: const InputDecoration(labelText: 'Cognome'),
                  validator: _validate,
                ),
                const SizedBox(height: 16),
                Text(widget.employee.email),
                const Text(
                  'Email e credenziali non vengono modificate da questa schermata.',
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
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Salva'),
        ),
      ],
    ),
  );
}
