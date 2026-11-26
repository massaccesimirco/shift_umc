import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/remote/supabase_assignment_repository.dart';
import '../models/planning.dart';
import '../repositories/assignment_repository.dart';
import '../services/assignment_service.dart';
import 'auth_providers.dart';

final assignmentRepositoryProvider = Provider<AssignmentRepository>(
  (ref) => SupabaseAssignmentRepository(Supabase.instance.client),
);
final assignmentServiceProvider = FutureProvider.autoDispose
    .family<AssignmentService, String>(
      (ref, userId) async => AssignmentService(
        ref.watch(assignmentRepositoryProvider),
        await ref.watch(currentProfileProvider(userId).future),
      ),
    );
// Separo le letture per account e settimana; le RLS rimangono la protezione autorevole.
final assignmentsProvider = FutureProvider.autoDispose
    .family<List<Assignment>, ({String userId, String weekId})>(
      (ref, selection) async =>
          (await ref.watch(assignmentServiceProvider(selection.userId).future))
              .list(selection.weekId),
      retry: (count, error) => null,
    );
