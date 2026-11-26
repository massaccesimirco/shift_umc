import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/access_failure.dart';
import '../../models/planning.dart';
import '../../providers/week_providers.dart';
import '../../providers/assignment_providers.dart';
import 'assignments_screen.dart';

class WeeksPanel extends ConsumerStatefulWidget {
  const WeeksPanel({super.key, required this.userId});
  final String userId;
  @override
  ConsumerState<WeeksPanel> createState() => _WeeksPanelState();
}

class _WeeksPanelState extends ConsumerState<WeeksPanel> {
  DateTime _monday = mondayOf(DateTime.now());
  bool _saving = false;
  String? _error;

  String _date(DateTime value) => '${value.day}/${value.month}/${value.year}';

  void _move(int weeks) => setState(() {
    _monday = addDays(_monday, weeks * 7);
    _error = null;
  });

  Future<void> _create() async {
    if (_saving) return;
    final selection = (userId: widget.userId, monday: _monday);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final service = await ref.read(weekServiceProvider(widget.userId).future);
      await service.createDraft(selection.monday);
      if (!mounted) return;
      ref.invalidate(remoteWeekProvider(selection));
    } catch (error) {
      if (mounted) setState(() => _error = accessErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _publish(WeekPlan plan) async {
    if (_saving) return;
    final selection = (userId: widget.userId, monday: _monday);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Rileggo la fotografia prima della conferma: il server la confronterà al salvataggio.
      final service = await ref.read(
        assignmentServiceProvider(widget.userId).future,
      );
      final snapshot = await service.list(plan.id);
      if (!mounted) return;
      if (snapshot.isEmpty) {
        throw const AccessFailure(
          'Assegna almeno una mansione prima di pubblicare.',
        );
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Pubblicare la settimana?'),
          content: Text(
            'Settimana dal ${_date(plan.startDate)}: ${snapshot.length} assegnazioni. '
            'I dipendenti potranno consultare le proprie mansioni. Le fasce senza assegnazioni resteranno vuote. '
            'Dopo la pubblicazione non potrai modificare la settimana.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Conferma pubblicazione'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await (await ref.read(weekServiceProvider(widget.userId).future))
          .publish(plan, snapshot);
      if (!mounted) return;
      ref.invalidate(remoteWeekProvider(selection));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Settimana pubblicata.')));
    } catch (error) {
      if (mounted) setState(() => _error = accessErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = remoteWeekProvider((
      userId: widget.userId,
      monday: _monday,
    ));
    final week = ref.watch(provider);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Settimana precedente',
                  onPressed: _saving ? null : () => _move(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '${_date(_monday)} – ${_date(addDays(_monday, 4))}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Settimana successiva',
                  onPressed: _saving ? null : () => _move(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          _monday = mondayOf(DateTime.now());
                          _error = null;
                        }),
                  child: const Text('Settimana corrente'),
                ),
                TextButton.icon(
                  onPressed: _saving || week.isLoading
                      ? null
                      : () {
                          setState(() => _error = null);
                          ref.invalidate(provider);
                        },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Aggiorna'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            week.when(
              skipLoadingOnRefresh: false,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Column(
                children: [
                  Text(accessErrorMessage(error)),
                  TextButton(
                    onPressed: () => ref.invalidate(provider),
                    child: const Text('Riprova'),
                  ),
                ],
              ),
              data: (plan) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (plan == null) ...[
                        const Text(
                          'Nessuna pianificazione per questa settimana.',
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _saving ? null : _create,
                          icon: const Icon(Icons.add),
                          label: Text(_saving ? 'Creazione…' : 'Crea bozza'),
                        ),
                      ] else ...[
                        Chip(
                          label: Text(
                            plan.status == WeekStatus.draft
                                ? 'Bozza'
                                : 'Pubblicata',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          plan.status == WeekStatus.draft
                              ? 'La settimana è salvata. La bozza è visibile solo agli amministratori.'
                              : 'La settimana è pubblicata.',
                        ),
                        if (plan.status == WeekStatus.published) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => AssignmentsScreen(
                                  userId: widget.userId,
                                  week: plan,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('Consulta assegnazioni'),
                          ),
                        ],
                        if (plan.status == WeekStatus.draft) ...[
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _saving
                                ? null
                                : () => Navigator.of(context).push<void>(
                                    MaterialPageRoute(
                                      builder: (_) => AssignmentsScreen(
                                        userId: widget.userId,
                                        week: plan,
                                      ),
                                    ),
                                  ),
                            icon: const Icon(Icons.edit_calendar),
                            label: const Text('Gestisci assegnazioni'),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _saving ? null : () => _publish(plan),
                            icon: const Icon(Icons.publish),
                            label: Text(
                              _saving
                                  ? 'Operazione in corso…'
                                  : 'Pubblica settimana',
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
