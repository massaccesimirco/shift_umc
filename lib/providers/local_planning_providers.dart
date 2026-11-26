import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/local_planning_store.dart';
import '../models/local_planning.dart';

final localPlanningStoreProvider = Provider((ref) => LocalPlanningStore());
final localPlanningCopiesProvider = FutureProvider.autoDispose
    .family<List<LocalPlanning>, String>(
      (ref, userId) => ref.watch(localPlanningStoreProvider).readAll(userId),
      retry: (count, error) => null,
    );
