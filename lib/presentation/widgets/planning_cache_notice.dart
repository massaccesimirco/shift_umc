import 'package:material_ui/material_ui.dart';

String localPlanningTimestamp(DateTime value) {
  final d = value.toLocal();
  return '${d.day}/${d.month}/${d.year} alle ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class PlanningCacheNotice extends StatelessWidget {
  const PlanningCacheNotice({
    super.key,
    this.savedAt,
    this.offline = false,
    this.failed = false,
  });
  final DateTime? savedAt;
  final bool offline, failed;

  @override
  Widget build(BuildContext context) {
    final text = failed
        ? 'Pianificazione online. Non è stato possibile aggiornare la copia sul dispositivo.'
        : offline
        ? 'Copia locale salvata il ${localPlanningTimestamp(savedAt!)}. I dati potrebbero non essere aggiornati e il profilo non è verificabile offline.'
        : 'Copia salvata sul dispositivo il ${localPlanningTimestamp(savedAt!)}.';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        liveRegion: true,
        child: Text(
          text,
          style: TextStyle(
            color: offline || failed
                ? Theme.of(context).colorScheme.error
                : null,
          ),
        ),
      ),
    );
  }
}
