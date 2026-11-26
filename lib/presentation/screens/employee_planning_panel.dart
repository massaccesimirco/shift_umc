import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/access_failure.dart';
import '../../models/planning.dart';
import '../../providers/employee_planning_providers.dart';
import '../widgets/day_plan_card.dart';
import '../widgets/planning_cache_notice.dart';

class EmployeePlanningPanel extends ConsumerStatefulWidget {
  const EmployeePlanningPanel({super.key, required this.userId});
  final String userId;
  @override
  ConsumerState<EmployeePlanningPanel> createState() =>
      _EmployeePlanningPanelState();
}

class _EmployeePlanningPanelState extends ConsumerState<EmployeePlanningPanel> {
  int _page = 0;
  DateTime? _selectedMonday;

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(remoteTodayProvider);
    final monday = _page == 0
        ? mondayOf(today)
        : _selectedMonday ?? mondayOf(today);
    final selection = (userId: widget.userId, monday: monday);
    final planning = ref.watch(employeePlanningProvider(selection));
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 800;
        final content = ListView(
          padding: EdgeInsets.all(wide ? 32 : 16),
          children: [
            Text(
              _page == 0 ? 'Le mansioni di oggi' : 'La mia settimana',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            if (_page == 1)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${monday.day}/${monday.month}/${monday.year} – ${addDays(monday, 4).day}/${addDays(monday, 4).month}/${addDays(monday, 4).year}',
                  ),
                  IconButton(
                    tooltip: 'Settimana precedente',
                    onPressed: () =>
                        setState(() => _selectedMonday = addDays(monday, -7)),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _selectedMonday = null),
                    child: const Text('Questa settimana'),
                  ),
                  IconButton(
                    tooltip: 'Settimana successiva',
                    onPressed: () =>
                        setState(() => _selectedMonday = addDays(monday, 7)),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  ref.invalidate(remoteTodayProvider);
                  ref.invalidate(employeePlanningProvider(selection));
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Aggiorna pianificazione'),
              ),
            ),
            const SizedBox(height: 12),
            planning.when(
              skipLoadingOnRefresh: false,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Column(
                children: [
                  Text(accessErrorMessage(error)),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(employeePlanningProvider(selection)),
                    child: const Text('Riprova'),
                  ),
                ],
              ),
              data: (view) {
                final data = view.planning;
                final notice = view.savedAt != null || view.cacheWriteFailed
                    ? PlanningCacheNotice(
                        savedAt: view.savedAt,
                        offline: view.fromCache,
                        failed: view.cacheWriteFailed,
                      )
                    : const SizedBox.shrink();
                if (_page == 0 && today.weekday > DateTime.friday) {
                  return Column(
                    children: [
                      notice,
                      const Text(
                        'Oggi è il fine settimana. La pianificazione copre dal lunedì al venerdì.',
                      ),
                    ],
                  );
                }
                if (data == null) {
                  return Column(
                    children: [
                      notice,
                      const Text(
                        'Nessuna pianificazione pubblicata per questa settimana.',
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    notice,
                    const Text('Pianificazione pubblicata'),
                    const SizedBox(height: 12),
                    for (final day
                        in _page == 0
                            ? [today]
                            : List.generate(5, (i) => addDays(monday, i)))
                      DayPlanCard(
                        date: day,
                        assignments: data.assignments,
                        duties: data.duties,
                        isToday: sameDate(day, today),
                      ),
                  ],
                );
              },
            ),
          ],
        );
        final destinations = const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            label: 'Oggi',
          ),
          NavigationDestination(
            icon: Icon(Icons.date_range_outlined),
            label: 'Settimana',
          ),
        ];
        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  if (wide) ...[
                    NavigationRail(
                      selectedIndex: _page,
                      labelType: NavigationRailLabelType.all,
                      onDestinationSelected: (value) =>
                          setState(() => _page = value),
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.today_outlined),
                          label: Text('Oggi'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.date_range_outlined),
                          label: Text('Settimana'),
                        ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                  ],
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1000),
                        child: content,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!wide)
              NavigationBar(
                selectedIndex: _page,
                onDestinationSelected: (value) => setState(() => _page = value),
                destinations: destinations,
              ),
          ],
        );
      },
    );
  }
}
