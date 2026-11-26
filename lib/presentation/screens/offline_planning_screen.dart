import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/access_failure.dart';
import '../../models/planning.dart';
import '../../models/local_planning.dart';
import '../../providers/auth_providers.dart';
import '../../providers/local_planning_providers.dart';
import '../widgets/day_plan_card.dart';
import '../widgets/planning_cache_notice.dart';

class OfflinePlanningScreen extends ConsumerStatefulWidget {
  const OfflinePlanningScreen({
    super.key,
    required this.userId,
    required this.retry,
  });
  final String userId;
  final VoidCallback retry;
  @override
  ConsumerState<OfflinePlanningScreen> createState() =>
      _OfflinePlanningScreenState();
}

class _OfflinePlanningScreenState extends ConsumerState<OfflinePlanningScreen> {
  String? _weekId;
  @override
  Widget build(BuildContext context) {
    final copies = ref.watch(localPlanningCopiesProvider(widget.userId));
    final action = ref.watch(authActionProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pianificazione locale'),
        actions: [
          TextButton.icon(
            onPressed: action.isLoading
                ? null
                : () => ref.read(authActionProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Esci'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Connessione non disponibile. Puoi consultare soltanto le settimane già salvate su questo dispositivo.',
                ),
                TextButton.icon(
                  onPressed: widget.retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Riprova collegamento'),
                ),
                if (action.hasError) Text(accessErrorMessage(action.error!)),
                copies.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, stack) => const Text(
                    'Non è possibile leggere la copia locale sul dispositivo.',
                  ),
                  data: (items) => _content(items),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(List<LocalPlanning> items) {
    if (items.isEmpty) {
      return const Text(
        'Nessuna pianificazione salvata per questo account. Collegati a Internet e consulta prima una settimana pubblicata.',
      );
    }
    final selected =
        items.where((i) => i.planning.week.id == _weekId).firstOrNull ??
        items.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        PlanningCacheNotice(savedAt: selected.savedAt, offline: true),
        DropdownButtonFormField<String>(
          key: ValueKey(selected.planning.week.id),
          initialValue: selected.planning.week.id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Settimana salvata'),
          items: items
              .map(
                (i) => DropdownMenuItem(
                  value: i.planning.week.id,
                  child: Text(
                    'Dal ${italianDate(i.planning.week.startDate)} ${i.planning.week.startDate.year}',
                  ),
                ),
              )
              .toList(),
          onChanged: (id) => setState(() => _weekId = id),
        ),
        const SizedBox(height: 16),
        for (var day = 0; day < 5; day++)
          DayPlanCard(
            date: addDays(selected.planning.week.startDate, day),
            assignments: selected.planning.assignments,
            duties: selected.planning.duties,
          ),
      ],
    );
  }
}
