import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../models/cash_session.dart';
import 'cash_repository.dart';

class DriftCashRepository implements CashRepository {
  DriftCashRepository(this._db, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  @override
  Stream<CashSession?> watchCurrent() {
    final sessions = _db.cashSessionsTable;
    final movements = _db.cashMovementsTable;
    final query = _db.select(sessions).join([
      leftOuterJoin(movements, movements.sessionId.equalsExp(sessions.id)),
    ])
      ..where(sessions.closedAt.isNull())
      ..orderBy([OrderingTerm.asc(movements.createdAt)]);

    return query.watch().map((rows) {
      if (rows.isEmpty) return null;
      final session = rows.first.readTable(sessions);
      final list = <CashMovementsTableData>[
        for (final row in rows)
          ?row.readTableOrNull(movements),
      ];
      return _toModel(session, list);
    });
  }

  @override
  Future<CashSession> open({required int openingCents}) {
    return _db.transaction(() async {
      final alreadyOpen = await (_db.select(_db.cashSessionsTable)
            ..where((row) => row.closedAt.isNull())
            ..limit(1))
          .get();
      if (alreadyOpen.isNotEmpty) throw CashSessionAlreadyOpenException();

      final row = await _db.into(_db.cashSessionsTable).insertReturning(
            CashSessionsTableCompanion.insert(openedAt: _clock(), openingCents: openingCents),
          );
      return _toModel(row, const []);
    });
  }

  @override
  Future<void> addMovement({
    required String sessionId,
    required CashMovementType type,
    required int amountCents,
    required String note,
  }) async {
    if (type != CashMovementType.deposit && type != CashMovementType.withdrawal) {
      throw ArgumentError('Solo los ingresos y retiros manuales se registran aquí.');
    }
    await _db.transaction(() async {
      if (type == CashMovementType.withdrawal) {
        final session = await _loadSession(sessionId);
        if (amountCents > session.expectedCents) throw InsufficientCashException(session.expectedCents);
      }
      await _db.into(_db.cashMovementsTable).insert(
            CashMovementsTableCompanion.insert(
              sessionId: sessionId,
              type: type,
              amountCents: amountCents,
              note: note,
              createdAt: _clock(),
            ),
          );
    });
  }

  @override
  Future<CashSession> close({required String sessionId, required int countedCents}) {
    return _db.transaction(() async {
      final updated = await (_db.update(_db.cashSessionsTable)
            ..where((row) => row.id.equals(sessionId) & row.closedAt.isNull()))
          .write(
        CashSessionsTableCompanion(
          closedAt: Value(_clock()),
          closingCountedCents: Value(countedCents),
        ),
      );
      if (updated == 0) throw CashSessionNotOpenException();
      return _loadSession(sessionId);
    });
  }

  @override
  Stream<List<CashSession>> watchClosed({int limit = 200}) {
    final query = _db.select(_db.cashSessionsTable)
      ..where((row) => row.closedAt.isNotNull())
      ..orderBy([(row) => OrderingTerm.desc(row.closedAt)])
      ..limit(limit);
    return query.watch().asyncMap((sessions) async {
      if (sessions.isEmpty) return <CashSession>[];
      final ids = [for (final s in sessions) s.id];
      final movements = await (_db.select(_db.cashMovementsTable)
            ..where((row) => row.sessionId.isIn(ids))
            ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
          .get();
      return [
        for (final s in sessions)
          _toModel(s, [for (final m in movements) if (m.sessionId == s.id) m]),
      ];
    });
  }

  Future<CashSession> _loadSession(String sessionId) async {
    final session = await (_db.select(_db.cashSessionsTable)..where((row) => row.id.equals(sessionId)))
        .getSingle();
    final movements = await (_db.select(_db.cashMovementsTable)
          ..where((row) => row.sessionId.equals(sessionId))
          ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
        .get();
    return _toModel(session, movements);
  }

  CashSession _toModel(CashSessionsTableData session, List<CashMovementsTableData> movements) {
    return CashSession(
      id: session.id,
      openingCents: session.openingCents,
      openedAt: session.openedAt,
      closedAt: session.closedAt,
      closingCountedCents: session.closingCountedCents,
      movements: [
        for (final m in movements)
          CashMovement(
            id: m.id,
            type: m.type,
            amountCents: m.amountCents,
            note: m.note,
            time: m.createdAt,
          ),
      ],
    );
  }
}
