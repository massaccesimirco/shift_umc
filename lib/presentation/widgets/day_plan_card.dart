import 'package:material_ui/material_ui.dart';

import '../../models/planning.dart';

String italianDate(DateTime date) {
  const days = [
    'Lunedì',
    'Martedì',
    'Mercoledì',
    'Giovedì',
    'Venerdì',
    'Sabato',
    'Domenica',
  ];
  const months = [
    'gennaio',
    'febbraio',
    'marzo',
    'aprile',
    'maggio',
    'giugno',
    'luglio',
    'agosto',
    'settembre',
    'ottobre',
    'novembre',
    'dicembre',
  ];
  return '${days[date.weekday - 1]} ${date.day} ${months[date.month - 1]}';
}

class DayPlanCard extends StatelessWidget {
  const DayPlanCard({
    super.key,
    required this.date,
    required this.assignments,
    required this.duties,
    this.isToday = false,
  });
  final DateTime date;
  final List<Assignment> assignments;
  final List<Duty> duties;
  final bool isToday;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${italianDate(date)}${isToday ? ' · Oggi' : ''}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            for (final period in Period.values) ...[
              Text(
                period == Period.morning ? 'MATTINA' : 'POMERIGGIO',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              if (!assignments.any(
                (a) => sameDate(a.date, date) && a.period == period,
              ))
                const Text('Nessuna mansione assegnata'),
              for (final assignment in assignments.where(
                (a) => sameDate(a.date, date) && a.period == period,
              ))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        duties
                                .where((d) => d.id == assignment.dutyId)
                                .firstOrNull
                                ?.name ??
                            'Mansione non disponibile',
                        style: theme.textTheme.bodyLarge,
                      ),
                      if (assignment.notes.isNotEmpty)
                        Text(
                          assignment.notes,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              if (period == Period.morning) const Divider(height: 28),
            ],
          ],
        ),
      ),
    );
  }
}
