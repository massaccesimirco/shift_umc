import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/access_failure.dart';
import '../../models/planning.dart';
import '../../providers/assignment_providers.dart';
import '../../providers/duty_providers.dart';
import '../../providers/employee_providers.dart';
import '../widgets/day_plan_card.dart' show italianDate;

class AssignmentsScreen extends ConsumerStatefulWidget {
  const AssignmentsScreen({
    super.key,
    required this.userId,
    required this.week,
  });
  final String userId;
  final WeekPlan week;

  @override
  ConsumerState<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends ConsumerState<AssignmentsScreen> {
  String? _employeeId;
  ({String userId, String weekId}) get _selection =>
      (userId: widget.userId, weekId: widget.week.id);

  void _refresh() {
    ref.invalidate(assignmentsProvider(_selection));
    ref.invalidate(employeesProvider(widget.userId));
    ref.invalidate(dutiesProvider(widget.userId));
  }

  @override
  Widget build(BuildContext context) {
    final employees = ref.watch(employeesProvider(widget.userId));
    final duties = ref.watch(dutiesProvider(widget.userId));
    final assignments = ref.watch(assignmentsProvider(_selection));
    final error = employees.error ?? duties.error ?? assignments.error;
    final loading =
        employees.isLoading || duties.isLoading || assignments.isLoading;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.week.status == WeekStatus.draft
              ? 'Assegnazioni della bozza'
              : 'Assegnazioni pubblicate',
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: error != null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(accessErrorMessage(error)),
                      ),
                      TextButton(
                        onPressed: _refresh,
                        child: const Text('Riprova'),
                      ),
                    ],
                  )
                : loading
                ? const Center(child: CircularProgressIndicator())
                : _content(
                    employees.requireValue,
                    duties.requireValue,
                    assignments.requireValue,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _content(
    List<UserProfile> employees,
    List<Duty> duties,
    List<Assignment> assignments,
  ) {
    final options = employees
        .where((e) => e.role == UserRole.employee)
        .toList();
    final selected =
        options.where((e) => e.id == _employeeId).firstOrNull ??
        options.firstOrNull;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Settimana dal ${italianDate(widget.week.startDate)}'),
        const SizedBox(height: 12),
        Text(
          widget.week.status == WeekStatus.draft
              ? 'Salva ogni fascia separatamente. La bozza resta visibile solo agli amministratori.'
              : 'Settimana pubblicata: le assegnazioni sono in sola lettura.',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Aggiorna assegnazioni'),
          ),
        ),
        if (selected == null)
          const Text('Nessun dipendente presente. Crea prima un dipendente.')
        else ...[
          DropdownButtonFormField<String>(
            key: ValueKey(selected.id),
            initialValue: selected.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Dipendente'),
            items: options
                .map(
                  (e) => DropdownMenuItem(
                    value: e.id,
                    child: Text(
                      '${e.fullName}${e.active ? '' : ' (disattivato)'}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _employeeId = value),
          ),
          if (!selected.active)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Dipendente disattivato: puoi soltanto svuotare le fasce.',
              ),
            ),
          const SizedBox(height: 16),
          for (var day = 0; day < 5; day++)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      italianDate(addDays(widget.week.startDate, day)),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    for (final period in Period.values)
                      _slot(
                        selected,
                        addDays(widget.week.startDate, day),
                        period,
                        duties,
                        assignments,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _slot(
    UserProfile employee,
    DateTime date,
    Period period,
    List<Duty> duties,
    List<Assignment> assignments,
  ) {
    final slot = assignments
        .where(
          (a) =>
              a.employeeId == employee.id &&
              sameDate(a.date, date) &&
              a.period == period,
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(period == Period.morning ? 'Mattina' : 'Pomeriggio'),
          if (slot.isEmpty) const Text('Nessuna mansione assegnata'),
          for (final a in slot) ...[
            Text(
              duties.where((d) => d.id == a.dutyId).firstOrNull?.name ??
                  'Mansione non disponibile',
            ),
            if (a.notes.isNotEmpty)
              Text(a.notes, style: Theme.of(context).textTheme.bodySmall),
          ],
          TextButton.icon(
            onPressed: widget.week.status != WeekStatus.draft
                ? null
                : () async {
                    final saved = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => _SlotEditor(
                        userId: widget.userId,
                        week: widget.week,
                        employee: employee,
                        date: date,
                        period: period,
                        duties: duties,
                        initial: slot,
                      ),
                    );
                    if (saved == true && mounted) {
                      ref.invalidate(assignmentsProvider(_selection));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Fascia salvata.')),
                      );
                    }
                  },
            icon: const Icon(Icons.edit_outlined),
            label: Text(
              'Modifica ${period == Period.morning ? 'mattina' : 'pomeriggio'}',
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotEditor extends ConsumerStatefulWidget {
  const _SlotEditor({
    required this.userId,
    required this.week,
    required this.employee,
    required this.date,
    required this.period,
    required this.duties,
    required this.initial,
  });
  final String userId;
  final WeekPlan week;
  final UserProfile employee;
  final DateTime date;
  final Period period;
  final List<Duty> duties;
  final List<Assignment> initial;

  @override
  ConsumerState<_SlotEditor> createState() => _SlotEditorState();
}

class _SlotEditorState extends ConsumerState<_SlotEditor> {
  late final Set<String> _selected;
  late final TextEditingController _notes;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Conservo la fotografia iniziale per riconoscere modifiche concorrenti sul server.
    _selected = widget.initial.map((a) => a.dutyId).toSet();
    _notes = TextEditingController(
      text: widget.initial.firstOrNull?.notes ?? '',
    );
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_selected.any((id) => !widget.duties.any((d) => d.id == id))) {
        throw const AccessFailure(
          'Una mansione non è disponibile. Chiudi e aggiorna le assegnazioni.',
        );
      }
      final service = await ref.read(
        assignmentServiceProvider(widget.userId).future,
      );
      await service.saveSlot(
        week: widget.week,
        employee: widget.employee,
        date: widget.date,
        period: widget.period,
        duties: widget.duties.where((d) => _selected.contains(d.id)).toList(),
        notes: _notes.text,
        expected: widget.initial,
      );
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
      title: Text(
        '${italianDate(widget.date)} · ${widget.period == Period.morning ? 'Mattina' : 'Pomeriggio'}',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.employee.fullName),
              const SizedBox(height: 12),
              const Text(
                'Seleziona le mansioni. Uno stato esclusivo deve restare da solo. Senza selezioni svuoti la fascia.',
              ),
              for (final duty in widget.duties.where(
                (d) => d.active || _selected.contains(d.id),
              ))
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(duty.name),
                  subtitle: duty.exclusive || !duty.active
                      ? Text(
                          !duty.active
                              ? 'Disattivata: rimuovila prima di salvare'
                              : 'Stato esclusivo',
                        )
                      : null,
                  value: _selected.contains(duty.id),
                  onChanged:
                      _saving ||
                          (!widget.employee.active &&
                              !_selected.contains(duty.id))
                      ? null
                      : (checked) => setState(() {
                          if (checked == true) {
                            _selected.add(duty.id);
                          } else {
                            _selected.remove(duty.id);
                          }
                        }),
                ),
              if (widget.duties.where((d) => d.active).isEmpty)
                const Text('Nessuna mansione attiva disponibile.'),
              TextField(
                controller: _notes,
                enabled: !_saving,
                maxLines: 3,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Note della fascia',
                  helperText:
                      'Le note valgono per tutte le mansioni selezionate.',
                ),
              ),
              if (_error != null)
                Semantics(
                  liveRegion: true,
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
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        TextButton(
          onPressed: _saving
              ? null
              : () => setState(() {
                  _selected.clear();
                  _notes.clear();
                }),
          child: const Text('Svuota selezione'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Salvataggio…' : 'Salva fascia'),
        ),
      ],
    ),
  );
}
