import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/planning.dart';
import '../../providers/planning_providers.dart';
import '../widgets/day_plan_card.dart';

class EmployeeScreen extends ConsumerStatefulWidget {
  const EmployeeScreen({super.key});
  @override
  ConsumerState<EmployeeScreen> createState() => _EmployeeScreenState();
}

class _EmployeeScreenState extends ConsumerState<EmployeeScreen> {
  int _page = 0;
  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(planningRepositoryProvider);
    final today = ref.watch(todayProvider);
    final monday = ref.watch(selectedWeekProvider);
    final service = ref.watch(planningServiceProvider);
    final week = _page == 0
        ? service.publishedWeek(today)
        : ref.watch(publishedWeekProvider);
    final assignments = _page == 0
        ? service.employeeAssignments(today)
        : ref.watch(weekAssignmentsProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 800;
        final content = ListView(
          padding: EdgeInsets.all(wide ? 32 : 16),
          children: [
            Text(
              'Benvenuto in ShiftUMC, ${repository.currentEmployee.firstName}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('DEMO · Dati di esempio, nessun account collegato'),
            const SizedBox(height: 28),
            if (_page == 1) ...[
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${monday.day}/${monday.month} – ${addDays(monday, 4).day}/${addDays(monday, 4).month}/${addDays(monday, 4).year}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  IconButton(
                    tooltip: 'Settimana precedente',
                    onPressed: () =>
                        ref.read(selectedWeekProvider.notifier).move(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        ref.read(selectedWeekProvider.notifier).reset(),
                    child: const Text('Questa settimana'),
                  ),
                  IconButton(
                    tooltip: 'Settimana successiva',
                    onPressed: () =>
                        ref.read(selectedWeekProvider.notifier).move(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (_page == 0 && today.weekday > DateTime.friday)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Oggi è il fine settimana. La pianificazione copre dal lunedì al venerdì.',
                  ),
                ),
              )
            else if (week == null)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Nessuna pianificazione pubblicata per questa settimana.',
                  ),
                ),
              )
            else ...[
              const Text('Pianificazione pubblicata'),
              const SizedBox(height: 12),
              for (final date
                  in _page == 0
                      ? [today]
                      : List.generate(5, (i) => addDays(monday, i)))
                DayPlanCard(
                  date: date,
                  assignments: assignments,
                  duties: repository.duties,
                  isToday: sameDate(date, today),
                ),
            ],
            if (_page == 0) ...[
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () {
                    ref.read(selectedWeekProvider.notifier).reset();
                    setState(() => _page = 1);
                  },
                  icon: const Icon(Icons.date_range),
                  label: const Text('La mia settimana'),
                ),
              ),
            ],
          ],
        );
        return Scaffold(
          appBar: AppBar(title: const Text('ShiftUMC')),
          body: SafeArea(
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
                        label: Text('La mia settimana'),
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
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _page,
                  onDestinationSelected: (value) =>
                      setState(() => _page = value),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.today_outlined),
                      label: 'Oggi',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.date_range_outlined),
                      label: 'La mia settimana',
                    ),
                  ],
                ),
        );
      },
    );
  }
}
