import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/remote/supabase_week_repository.dart';
import '../models/planning.dart';
import '../repositories/week_repository.dart';
import '../services/week_service.dart';
import 'auth_providers.dart';

final weekRepositoryProvider = Provider<WeekRepository>(
  (ref) => SupabaseWeekRepository(Supabase.instance.client),
);
final weekServiceProvider = FutureProvider.autoDispose
    .family<WeekService, String>(
      (ref, userId) async => WeekService(
        ref.watch(weekRepositoryProvider),
        await ref.watch(currentProfileProvider(userId).future),
      ),
    );
final remoteWeekProvider = FutureProvider.autoDispose
    .family<WeekPlan?, ({String userId, DateTime monday})>(
      (ref, selection) async =>
          (await ref.watch(weekServiceProvider(selection.userId).future))
              .find(selection.monday),
    );
