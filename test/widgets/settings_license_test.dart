import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/logging/log_sink.dart';
import 'package:ledger_app/logging/operation_logger.dart';
import 'package:ledger_app/main.dart';
import '../seed.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedMembers(db);
  });
  tearDown(() async => db.close());

  testWidgets('設定タブからライセンス画面を開ける', (tester) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      LedgerApp(
        db: db,
        clock: () => DateTime(2026, 7, 15),
        logger: OperationLogger(MemoryLogSink()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('ライセンス'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ライセンス'));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
  });
}
