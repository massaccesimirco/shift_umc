import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/access_failure.dart';
import '../../models/planning.dart';
import '../../providers/duty_providers.dart';

class DutiesPanel extends ConsumerStatefulWidget {
  const DutiesPanel({super.key, required this.userId});
  final String userId;
  @override
  ConsumerState<DutiesPanel> createState() => _DutiesPanelState();
}

class _DutiesPanelState extends ConsumerState<DutiesPanel> {
  bool _showInactive = false;
  bool _busy = false;
  String? _error;

  Future<void> _edit([Duty? duty]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DutyEditor(userId: widget.userId, duty: duty),
    );
    if (saved == true && mounted) {
      ref.invalidate(dutiesProvider(widget.userId));
    }
  }

  Future<void> _toggle(Duty duty) async {
    if (duty.active) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Disattivare la mansione?'),
          content: Text(
            '“${duty.name}” resterà nelle assegnazioni esistenti. Potrai riattivarla in seguito.',
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
      final service = await ref.read(dutyServiceProvider(widget.userId).future);
      await service.setActive(duty.id, !duty.active);
      if (mounted) ref.invalidate(dutiesProvider(widget.userId));
    } catch (error) {
      if (mounted) setState(() => _error = accessErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final duties = ref.watch(dutiesProvider(widget.userId));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : () => _edit(),
                  icon: const Icon(Icons.add),
                  label: const Text('Nuova mansione'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => ref.invalidate(dutiesProvider(widget.userId)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Aggiorna elenco'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Le attività possono essere combinate nella stessa fascia. Uno stato esclusivo, come Ferie, occupa da solo la fascia.',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mostra anche le disattivate'),
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
            duties.when(
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
                        ref.invalidate(dutiesProvider(widget.userId)),
                    child: const Text('Riprova'),
                  ),
                ],
              ),
              data: (all) {
                final visible = all
                    .where((duty) => _showInactive || duty.active)
                    .toList();
                if (visible.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Nessuna mansione da mostrare.'),
                  );
                }
                return Column(
                  children: [
                    for (final duty in visible)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                duty.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Chip(
                                    label: Text(
                                      duty.type == DutyType.activity
                                          ? 'Attività'
                                          : 'Stato',
                                    ),
                                  ),
                                  if (duty.exclusive)
                                    const Chip(label: Text('Esclusivo')),
                                  if (!duty.active)
                                    const Chip(label: Text('Disattivata')),
                                ],
                              ),
                              Wrap(
                                spacing: 12,
                                children: [
                                  TextButton.icon(
                                    onPressed: _busy ? null : () => _edit(duty),
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Modifica'),
                                  ),
                                  TextButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _toggle(duty),
                                    icon: Icon(
                                      duty.active
                                          ? Icons.pause_circle_outline
                                          : Icons.play_circle_outline,
                                    ),
                                    label: Text(
                                      duty.active ? 'Disattiva' : 'Riattiva',
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

class _DutyEditor extends ConsumerStatefulWidget {
  const _DutyEditor({required this.userId, this.duty});
  final String userId;
  final Duty? duty;
  @override
  ConsumerState<_DutyEditor> createState() => _DutyEditorState();
}

class _DutyEditorState extends ConsumerState<_DutyEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late DutyType _type;
  late bool _exclusive;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.duty?.name ?? '');
    _type = widget.duty?.type ?? DutyType.activity;
    _exclusive = widget.duty?.exclusive ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final service = await ref.read(dutyServiceProvider(widget.userId).future);
      await service.save(
        id: widget.duty?.id,
        name: _name.text,
        type: _type,
        exclusive: _exclusive,
      );
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
      title: Text(widget.duty == null ? 'Nuova mansione' : 'Modifica mansione'),
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
                  controller: _name,
                  enabled: !_saving,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nome'),
                  validator: (value) =>
                      value == null ||
                          value.trim().isEmpty ||
                          value.trim().runes.length > 120
                      ? 'Inserisci un nome da 1 a 120 caratteri.'
                      : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<DutyType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: const [
                    DropdownMenuItem(
                      value: DutyType.activity,
                      child: Text('Attività'),
                    ),
                    DropdownMenuItem(
                      value: DutyType.status,
                      child: Text('Stato'),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _type = value!;
                          if (_type == DutyType.activity) _exclusive = false;
                        }),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Esclusivo'),
                  subtitle: const Text(
                    'Non ammette altre mansioni nella stessa fascia.',
                  ),
                  value: _exclusive,
                  onChanged: _saving || _type == DutyType.activity
                      ? null
                      : (value) => setState(() => _exclusive = value),
                ),
                if (widget.duty != null)
                  const Text(
                    'Se già assegnata, tipo ed esclusività non possono cambiare. Il nome aggiornato comparirà anche nelle settimane passate.',
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
