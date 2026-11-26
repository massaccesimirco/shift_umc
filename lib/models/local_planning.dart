import 'published_planning.dart';

class LocalPlanning {
  const LocalPlanning({required this.planning, required this.savedAt});
  final PublishedPlanning planning;
  final DateTime savedAt;
}

class PlanningView {
  const PlanningView({
    required this.planning,
    this.savedAt,
    this.fromCache = false,
    this.cacheWriteFailed = false,
  });
  final PublishedPlanning? planning;
  final DateTime? savedAt;
  final bool fromCache;
  final bool cacheWriteFailed;
}
