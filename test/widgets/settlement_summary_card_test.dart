import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/logging/log_sink.dart';
import 'package:ledger_app/logging/operation_logger.dart';
import 'package:ledger_app/main.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/screens/split_screen.dart';
import 'package:ledger_app/theme/ledger_theme.dart';
import 'package:ledger_app/theme/ledger_tokens.dart';
import 'package:ledger_app/widgets/chart_palette.dart';
import 'package:ledger_app/widgets/settlement_summary_card.dart';

void main() {
  late AppDatabase db;
  final fixedNow = DateTime(2026, 7, 15);
  final card = find.byType(SettlementSummaryCard);

  setUpAll(() async {
    // 横並びの可否を実際の字幅で判断するため、同梱フォントを明示的に読む。
    for (final (family, path) in [
      ('ZenMaruGothic', 'assets/fonts/ZenMaruGothic-Regular.ttf'),
      ('ZenKakuGothicNew', 'assets/fonts/ZenKakuGothicNew-Bold.ttf'),
      ('Outfit', 'assets/fonts/Outfit-SemiBold.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(path))).load();
    }
  });

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  void setPhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pay(int memberId, double amount, {int month = 7}) async {
    await db.insertTransaction(
      TransactionInput(
        memberId: memberId,
        categoryId: (await db.getCategories()).first.id,
        amount: amount,
        spentAt: DateTime(2026, month, 5),
      ),
    );
  }

  Future<void> pumpApp(WidgetTester tester, {OperationLogger? logger}) async {
    setPhoneSize(tester);
    await tester.pumpWidget(
      LedgerApp(db: db, clock: () => fixedNow, logger: logger),
    );
    await tester.pumpAndSettle();
  }

  Finder inCard(String text) =>
      find.descendant(of: card, matching: find.text(text, findRichText: true));

  testWidgets('月の合計直下に送金元・送金先・桁区切りの金額を表示する', (tester) async {
    await db.insertMember('みく');
    await pay((await db.getMembers()).first.id, 124980);
    await pumpApp(tester);

    expect(inCard('みく → 自分 に\n¥62,490'), findsOneWidget);
    expect(inCard('精算する'), findsOneWidget);
    final avatars = find.descendant(
      of: card,
      matching: find.byType(CircleAvatar),
    );
    expect(avatars, findsNWidgets(2));
    final members = await db.getMembers();
    expect(
      tester.widget<CircleAvatar>(avatars.first).backgroundColor,
      memberColor(members.last.id),
    );
    expect(
      tester.widget<CircleAvatar>(avatars.last).backgroundColor,
      memberColor(members.first.id),
    );
    expect(
      find.descendant(of: avatars.first, matching: find.text('み')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: avatars.last, matching: find.text('自')),
      findsOneWidget,
    );
    // 頭文字は塗り色から選ぶ。固定の明色だと淡いメンバー色に溶ける。
    for (final (avatar, initial, member) in [
      (avatars.first, 'み', members.last),
      (avatars.last, '自', members.first),
    ]) {
      expect(
        tester
            .widget<Text>(
              find.descendant(of: avatar, matching: find.text(initial)),
            )
            .style
            ?.color,
        labelColorOn(memberColor(member.id)),
      );
    }
    final leftAvatar = tester.getRect(avatars.first);
    final rightAvatar = tester.getRect(avatars.last);
    expect(leftAvatar.overlaps(rightAvatar), isTrue);
    expect(leftAvatar.left, lessThan(rightAvatar.left));
    final button = find.descendant(
      of: card,
      matching: find.byType(FilledButton),
    );
    final payment = tester.getRect(inCard('みく → 自分 に\n¥62,490'));
    expect(rightAvatar.right, lessThan(payment.left));
    expect(payment.right, lessThanOrEqualTo(tester.getRect(button).left));
    expect(tester.getCenter(button).dy, closeTo(tester.getCenter(card).dy, 1));
    final material = tester.widget<Material>(
      find.descendant(of: card, matching: find.byType(Material)).first,
    );
    expect(material.color, LedgerTokens.settlementSurface);
    final buttonMaterial = tester.widget<Material>(
      find.descendant(of: button, matching: find.byType(Material)).first,
    );
    expect(buttonMaterial.color, ledgerTheme.colorScheme.primary);
    expect(buttonMaterial.shape, isA<StadiumBorder>());
    expect(
      tester.getBottomLeft(find.text('¥124,980').first).dy,
      lessThan(tester.getTopLeft(card).dy),
    );
    expect(
      tester.getBottomLeft(card).dy,
      lessThan(tester.getTopLeft(find.text('カテゴリ別')).dy),
    );
    // ピル型ボタン自身からも、本文と同じ割り勘タブへ移れる。
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(SplitScreen), findsOneWidget);
  });

  testWidgets('割り切れない差額も formatYen と同じ整数円表示にする', (tester) async {
    await db.insertMember('みく');
    await pay((await db.getMembers()).first.id, 2469);
    await pumpApp(tester);

    expect(inCard('みく → 自分 に\n¥1,235'), findsOneWidget);
  });

  testWidgets('月送りで金額が変わり、カードから同じ月の割り勘へ移る', (tester) async {
    await db.insertMember('みく');
    final members = await db.getMembers();
    await pay(members.first.id, 124980);
    // 前月は金額だけでなく送金方向も反転させ、古い表示の残留を検出する。
    await pay(members.last.id, 4000, month: 6);
    final sink = MemoryLogSink();
    final logger = OperationLogger(sink, clock: () => fixedNow);
    await pumpApp(tester, logger: logger);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(inCard('自分 → みく に\n¥2,000'), findsOneWidget);
    expect(inCard('みく → 自分 に\n¥62,490'), findsNothing);

    ScaffoldMessenger.of(tester.element(card)).showSnackBar(
      const SnackBar(content: Text('前のタブの案内'), duration: Duration(minutes: 1)),
    );
    await tester.pumpAndSettle();
    expect(find.text('前のタブの案内'), findsOneWidget);
    // ボタン文言だけでなく、要点の本文もタップ領域に含まれる。
    await tester.tap(inCard('自分 → みく に\n¥2,000'));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(find.byType(SplitScreen), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    expect(find.text('2026年6月'), findsOneWidget);
    expect(find.text('自分 → みく に 2000 円支払う'), findsOneWidget);
    expect(find.text('前のタブの案内'), findsNothing);
    final changes =
        sink.lines
            .map((line) => jsonDecode(line) as Map<String, dynamic>)
            .where((entry) => entry['op'] == 'tab.change')
            .toList();
    expect(changes, hasLength(1));
    expect(changes.single['detail'], {'from': 'summary', 'to': 'split'});
  });

  testWidgets('年・全期間では非表示で、月に戻ると同じ要点が出る', (tester) async {
    await db.insertMember('みく');
    await pay((await db.getMembers()).first.id, 4000);
    await pumpApp(tester);
    expect(inCard('みく → 自分 に\n¥2,000'), findsOneWidget);

    for (final period in ['年', '全期間']) {
      await tester.tap(find.text(period));
      await tester.pumpAndSettle();
      expect(card, findsNothing);
    }
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    expect(inCard('みく → 自分 に\n¥2,000'), findsOneWidget);
  });

  for (final (count, hasPayments, message) in [
    (0, false, 'メンバーを登録すると精算できます'),
    (1, true, '精算には2人以上のメンバーが必要です'),
    (2, false, '精算不要'),
    (2, true, '精算不要'),
    (3, true, '精算不要'),
  ]) {
    testWidgets('$count 人・支払い $hasPayments の案内を表示する', (tester) async {
      final initial = (await db.getMembers()).single;
      if (count == 0) await db.deleteMember(initial.id);
      for (var i = 1; i < count; i++) {
        await db.insertMember('メンバー$i');
      }
      if (hasPayments) {
        for (final member in await db.getMembers()) {
          await pay(member.id, 1000);
        }
      }
      await pumpApp(tester);

      expect(inCard(message), findsOneWidget);
      expect(inCard('精算する'), findsNothing);
      expect(inCard('割り勘を見る'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('端数だけの差額は精算不要にし、¥0 の支払い行を出さない', (tester) async {
    // 3人で 1000 円を等分すると各自の差額は ±0.33 で、0 ではないが ¥0 に丸まる。
    await db.insertMember('みく');
    await db.insertMember('たいち');
    final members = await db.getMembers();
    await pay(members[0].id, 334);
    await pay(members[1].id, 333);
    await pay(members[2].id, 333);
    await pumpApp(tester);

    expect(inCard('精算不要'), findsOneWidget);
    expect(inCard('精算に必要な支払い'), findsNothing);
    expect(inCard('みく は\n¥0'), findsNothing);
    expect(inCard('たいち は\n¥0'), findsNothing);
    expect(inCard('精算する'), findsNothing);
    expect(inCard('割り勘を見る'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('3人以上は支払う人と各不足額を対応させて全行表示する', (tester) async {
    await db.insertMember('みく');
    await db.insertMember('たいち');
    final members = await db.getMembers();
    await pay(members[0].id, 900);
    await pay(members[1].id, 300);
    await pumpApp(tester);

    expect(inCard('精算に必要な支払い'), findsOneWidget);
    expect(inCard('みく は\n¥100'), findsOneWidget);
    expect(inCard('たいち は\n¥400'), findsOneWidget);
    expect(inCard('自分 は\n¥500'), findsNothing);
    expect(inCard('精算する'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('360px・文字倍率2.0でも長い名前と上限金額を省略せず描く', (tester) async {
    setPhoneSize(tester);
    final first = (await db.getMembers()).single;
    await db.updateMemberName(first.id, 'あ' * 50);
    await db.insertMember('い' * 50);
    // 2件の上限金額を立て替えると、精算額が kMaxAmount になる。
    await pay(first.id, kMaxAmount);
    await pay(first.id, kMaxAmount);
    final split = await db.getSplit(2026, 7);

    Future<void> pumpCard(double scale) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ledgerTheme,
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [SettlementSummaryCard(split: split, onTap: () {})],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final text = '${'い' * 50} → ${'あ' * 50} に\n¥999,999,999,999';
    await pumpCard(1);
    final normalHeight = tester.getSize(card).height;
    await pumpCard(2);
    expect(inCard(text), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(card).height, greaterThan(normalHeight));
    final paragraph = tester.renderObject<RenderParagraph>(inCard(text));
    // 全文の行数と描画域を比較し、ellipsis だけでなく縦のクリップも検出する。
    expect(paragraph.didExceedMaxLines, isFalse);
    final painter = TextPainter(
      text: paragraph.text,
      textDirection: paragraph.textDirection,
      textScaler: paragraph.textScaler,
    )..layout(maxWidth: paragraph.size.width);
    addTearDown(painter.dispose);
    expect(paragraph.size.height, closeTo(painter.height, 0.01));
    final bounds = tester.getRect(card);
    expect(
      tester.getRect(inCard(text)).left,
      greaterThanOrEqualTo(bounds.left),
    );
    expect(tester.getRect(inCard(text)).right, lessThanOrEqualTo(bounds.right));
    final button = find.descendant(
      of: card,
      matching: find.byType(FilledButton),
    );
    expect(
      tester.getRect(button).top,
      greaterThanOrEqualTo(tester.getRect(inCard(text)).bottom),
    );
    await tester.ensureVisible(inCard('精算する'));
    await tester.pumpAndSettle();
    expect(inCard('精算する').hitTestable(), findsOneWidget);
  });
}
