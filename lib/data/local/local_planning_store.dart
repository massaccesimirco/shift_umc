import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/local_planning.dart';
import '../../models/planning.dart';
import '../../models/published_planning.dart';

class LocalPlanningStore {
  LocalPlanningStore({
    Future<SharedPreferences> Function()? preferences,
    DateTime Function()? now,
  }) : _preferences = preferences ?? SharedPreferences.getInstance,
       _now = now ?? DateTime.now;
  final Future<SharedPreferences> Function() _preferences;
  final DateTime Function() _now;
  final _generations = <String, int>{};
  Future<void> _pending = Future.value();

  int generation(String userId) => _generations[userId] ?? 0;
  String _key(String userId) =>
      'shiftumc.planning.v1.${Uri.encodeComponent(userId)}';

  // Serializzo accessi e cancellazione per evitare che un vecchio salvataggio ricrei la cache dopo il logout.
  Future<T> _serial<T>(Future<T> Function() operation) {
    final next = _pending.then((_) => operation());
    _pending = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return next;
  }

  Future<List<LocalPlanning>> readAll(String userId) => _serial(() async {
    final prefs = await _preferences();
    await prefs.reload();
    return _read(prefs, userId);
  });

  Future<LocalPlanning?> read(String userId, DateTime monday) async =>
      (await readAll(userId))
          .where((item) => sameDate(item.planning.week.startDate, monday))
          .firstOrNull;

  Future<DateTime?> save(
    String userId,
    PublishedPlanning planning,
    int expectedGeneration,
  ) => _serial(() async {
    _validate(userId, planning);
    if (generation(userId) != expectedGeneration) return null;
    final prefs = await _preferences();
    await prefs.reload();
    if (generation(userId) != expectedGeneration) return null;
    final savedAt = _now();
    final entries = _read(prefs, userId)
      ..removeWhere(
        (item) =>
            sameDate(item.planning.week.startDate, planning.week.startDate),
      );
    entries.insert(0, LocalPlanning(planning: planning, savedAt: savedAt));
    entries.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    final encoded = jsonEncode({
      'version': 1,
      'user_id': userId,
      'weeks': entries.take(8).map(_encode).toList(),
    });
    if (!await prefs.setString(_key(userId), encoded)) {
      throw StateError('Salvataggio locale non riuscito.');
    }
    return savedAt;
  });

  Future<void> removeWeek(
    String userId,
    DateTime monday,
    int expectedGeneration,
  ) => _serial(() async {
    if (generation(userId) != expectedGeneration) return;
    final prefs = await _preferences();
    await prefs.reload();
    if (generation(userId) != expectedGeneration) return;
    final entries = _read(prefs, userId)
      ..removeWhere((item) => sameDate(item.planning.week.startDate, monday));
    if (!await prefs.setString(
      _key(userId),
      jsonEncode({
        'version': 1,
        'user_id': userId,
        'weeks': entries.map(_encode).toList(),
      }),
    )) {
      throw StateError('Aggiornamento locale non riuscito.');
    }
  });

  Future<void> clearUser(String userId) {
    _generations[userId] = generation(userId) + 1;
    return _serial(() async {
      final prefs = await _preferences();
      if (!await prefs.remove(_key(userId))) {
        throw StateError('Cancellazione locale non riuscita.');
      }
    });
  }

  List<LocalPlanning> _read(SharedPreferences prefs, String userId) {
    final raw = prefs.getString(_key(userId));
    if (raw == null) return [];
    try {
      final envelope = jsonDecode(raw) as Map<String, dynamic>;
      if (envelope['version'] != 1 || envelope['user_id'] != userId) return [];
      final result = <LocalPlanning>[];
      for (final value in (envelope['weeks'] as List).take(8)) {
        final cached = _decode(value as Map<String, dynamic>);
        _validate(userId, cached.planning);
        result.add(cached);
      }
      return result..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    } catch (_) {
      // Ignoro una cache corrotta o incompatibile; non la tratto come dati del server.
      return [];
    }
  }

  void _validate(String userId, PublishedPlanning planning) {
    final w = planning.week;
    final duties = planning.duties.map((d) => d.id).toSet();
    if (w.status != WeekStatus.published ||
        w.publishedAt == null ||
        w.startDate.weekday != DateTime.monday ||
        planning.assignments.any(
          (a) =>
              a.employeeId != userId ||
              a.weekPlanId != w.id ||
              !duties.contains(a.dutyId) ||
              a.date.isBefore(w.startDate) ||
              a.date.isAfter(addDays(w.startDate, 4)),
        )) {
      throw const FormatException(
        'La copia locale deve contenere soltanto la settimana pubblicata personale.',
      );
    }
  }

  Map<String, dynamic> _encode(LocalPlanning item) {
    final p = item.planning;
    final w = p.week;
    return {
      'saved_at': item.savedAt.toIso8601String(),
      'week': {
        'id': w.id,
        'start_date': w.startDate.toIso8601String(),
        'status': w.status.name,
        'created_by': w.createdBy,
        'created_at': w.createdAt.toIso8601String(),
        'published_at': w.publishedAt?.toIso8601String(),
      },
      'assignments': p.assignments
          .map(
            (a) => {
              'id': a.id,
              'week_id': a.weekPlanId,
              'employee_id': a.employeeId,
              'date': a.date.toIso8601String(),
              'period': a.period.name,
              'duty_id': a.dutyId,
              'notes': a.notes,
            },
          )
          .toList(),
      'duties': p.duties
          .map(
            (d) => {
              'id': d.id,
              'name': d.name,
              'type': d.type.name,
              'exclusive': d.exclusive,
              'active': d.active,
            },
          )
          .toList(),
    };
  }

  LocalPlanning _decode(Map<String, dynamic> value) {
    final w = value['week'] as Map<String, dynamic>;
    return LocalPlanning(
      savedAt: DateTime.parse(value['saved_at'] as String),
      planning: PublishedPlanning(
        week: WeekPlan(
          id: w['id'] as String,
          startDate: DateTime.parse(w['start_date'] as String),
          status: WeekStatus.values.byName(w['status'] as String),
          createdBy: w['created_by'] as String,
          createdAt: DateTime.parse(w['created_at'] as String),
          publishedAt: w['published_at'] == null
              ? null
              : DateTime.parse(w['published_at'] as String),
        ),
        assignments: (value['assignments'] as List)
            .map(
              (a) => Assignment(
                id: a['id'] as String,
                weekPlanId: a['week_id'] as String,
                employeeId: a['employee_id'] as String,
                date: DateTime.parse(a['date'] as String),
                period: Period.values.byName(a['period'] as String),
                dutyId: a['duty_id'] as String,
                notes: a['notes'] as String,
              ),
            )
            .toList(),
        duties: (value['duties'] as List)
            .map(
              (d) => Duty(
                id: d['id'] as String,
                name: d['name'] as String,
                type: DutyType.values.byName(d['type'] as String),
                exclusive: d['exclusive'] as bool,
                active: d['active'] as bool,
              ),
            )
            .toList(),
      ),
    );
  }
}
