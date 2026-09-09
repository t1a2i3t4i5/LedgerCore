import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/main.dart';
import 'package:ledger_app/providers/member_provider.dart';
import 'package:ledger_app/screens/members_screen.dart';
import 'package:ledger_app/theme/ledger_theme.dart';
import 'package:ledger_app/theme/ledger_tokens.dart';
import 'package:ledger_app/widgets/chart_palette.dart';
import 'package:ledger_app/widgets/page_header.dart';
import 'package:provider/provider.dart';

import '../seed.dart';

class _RecordingMemberProvider extends MemberProvider {
  _RecordingMemberProvider(super.db);

  final updateCalls = <String>[];

  @override
  Future<void> updateMember(int id, String name) async {
    updateCalls.add('$id:$name');
    await super.updateMember(id, name);
  }
}

void main() {
  late AppDatabase db;
  late _RecordingMemberProvider provider;

  final fixedNow = DateTime(2026, 7, 15);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedMembers(db);
    provider = _RecordingMemberProvider(db);
  });
  tearDown(() async => db.close());

  void setPhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpMembersScreen(
    WidgetTester tester, {
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    setPhoneSize(tester);
    await tester.pumpWidget(
      ChangeNotifierProvider<MemberProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: ledgerTheme,
          home: Builder(
            builder:
                (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                  child: const MembersScreen(),
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpMembersScreenThroughSettings(WidgetTester tester) async {
    setPhoneSize(tester);
    await tester.pumpWidget(LedgerApp(db: db, clock: () => fixedNow));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.settings_outlined),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('メンバー管理'));
    await tester.pumpAndSettle();
  }

  Finder rowFor(int memberId) => find.byKey(ValueKey(memberId));

  Finder nameSlotFor(int memberId) =>
      find.byKey(ValueKey('member-name-slot-$memberId'));

  bool isEllipsized(WidgetTester tester, String text) =>
      tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines;

  testWidgets('メンバー見出しの戻るボタンで設定画面へ戻れる', (tester) async {
    await pumpMembersScreenThroughSettings(tester);
    expect(find.byType(AppBar), findsNothing);
    expect(find.widgetWithText(PageHeader, 'メンバー'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(PageHeader, 'メンバー'), findsNothing);
    expect(find.text('メンバー管理'), findsOneWidget);
  });

  testWidgets('追加と削除の導線を置かず、名前の用途を一覧の下に表示する', (tester) async {
    await seedMembers(db, const ['パートナー']);
    await pumpMembersScreen(tester);

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.text('名前は取引の記録と精算画面に表示されます'), findsOneWidget);
    expect(find.text('メンバー 1'), findsNothing);
    expect(find.text('メンバー 2'), findsNothing);
  });

  testWidgets('行は色の丸・名前・鉛筆を72pxに並べ、行の間を区切り線で仕切る', (tester) async {
    await seedMembers(db, const ['パートナー']);
    final members = await db.getMembers();
    await pumpMembersScreen(tester);

    final firstRow = rowFor(members.first.id);
    final secondRow = rowFor(members.last.id);
    final dot = tester.widget<Container>(
      find.byKey(ValueKey('member-dot-${members.first.id}')),
    );
    final editButton = find.descendant(
      of: firstRow,
      matching: find.byType(IconButton),
    );

    expect(tester.getSize(firstRow).height, 72);
    expect(tester.getSize(secondRow).height, 72);
    expect(
      (dot.decoration! as BoxDecoration).color,
      memberColor(members.first.id),
    );
    expect((dot.decoration! as BoxDecoration).shape, BoxShape.circle);
    expect(find.byType(Divider), findsOneWidget);
    expect(
      tester.widget<Divider>(find.byType(Divider)).color,
      LedgerTokens.barTrack,
    );
    expect(isEllipsized(tester, 'パートナー'), isFalse);
    expect(tester.getSize(editButton), const Size.square(44));
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: firstRow,
              matching: find.byIcon(Icons.edit_outlined),
            ),
          )
          .color,
      LedgerTokens.subtext,
    );
  });

  testWidgets('2人のときだけ重なる2円を描く', (tester) async {
    await pumpMembersScreen(tester);
    expect(find.byKey(const ValueKey('member-venn')), findsNothing);

    await seedMembers(db, const ['パートナー']);
    await provider.fetchMembers();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('member-venn')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('member-venn'))),
      const Size(300, 190),
    );

    await seedMembers(db, const ['3人目']);
    await provider.fetchMembers();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('member-venn')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('名前のタップと鉛筆アイコンのどちらでも行内編集を始める', (tester) async {
    await pumpMembersScreen(tester);

    await tester.tap(find.text('自分'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('2/50'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('入力中は50文字カウンタがその場で追従する', (tester) async {
    await pumpMembersScreen(tester);
    await tester.tap(find.text('自分'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'パートナー');
    await tester.pump();
    expect(find.text('5/50'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.text('0/50'), findsOneWidget);
  });

  testWidgets('絵文字を含む名前はDBと同じ長さ50まで保存できる', (tester) async {
    final member = (await db.getMembers()).single;
    const family = '👨‍👩‍👧‍👦';
    final name = '$family$family$family$family${'あ' * 6}';
    expect(name.length, 50);

    await pumpMembersScreen(tester);
    await tester.tap(find.text('自分'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), name);
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(ValueKey('member-counter-${member.id}')),
        matching: find.text('50/50'),
      ),
      findsOneWidget,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(provider.updateCalls, ['${member.id}:$name']);
    expect((await db.getMembers()).single.name, name);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('DBの長さ50を超える絵文字入力を受け付けない', (tester) async {
    const family = '👨‍👩‍👧‍👦';
    final tooLongName = family * 5;
    expect(tooLongName.length, 55);

    await pumpMembersScreen(tester);
    await tester.tap(find.text('自分'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), tooLongName);
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '自分',
    );
    expect(find.text('2/50'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(provider.updateCalls, isEmpty);
    expect((await db.getMembers()).single.name, '自分');
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Enterで変更名を一度だけMemberProviderへ渡して保存する', (tester) async {
    final member = (await db.getMembers()).single;
    await pumpMembersScreen(tester);
    await tester.tap(find.text('自分'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'わたし');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(provider.updateCalls, ['${member.id}:わたし']);
    expect((await db.getMembers()).single.name, 'わたし');
    expect(find.text('わたし'), findsOneWidget);
  });

  testWidgets('フォーカスアウトで変更名をMemberProviderへ渡して保存する', (tester) async {
    final member = (await db.getMembers()).single;
    await pumpMembersScreen(tester);
    await tester.tap(find.text('自分'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '本人');
    await tester.ensureVisible(find.text('名前は取引の記録と精算画面に表示されます'));

    await tester.tap(find.text('名前は取引の記録と精算画面に表示されます'));
    await tester.pumpAndSettle();

    expect(provider.updateCalls, ['${member.id}:本人']);
    expect((await db.getMembers()).single.name, '本人');
  });

  testWidgets('名前が変わっていなければMemberProviderを呼ばない', (tester) async {
    await pumpMembersScreen(tester);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(provider.updateCalls, isEmpty);
    expect((await db.getMembers()).single.name, '自分');
  });

  testWidgets('空欄で確定すると通知を出さず元の名前へ戻す', (tester) async {
    await pumpMembersScreen(tester);
    await tester.tap(find.text('自分'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(provider.updateCalls, isEmpty);
    expect(find.text('自分'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('カウンタの表示切替でも行の高さと名前の幅が動かない', (tester) async {
    final member = (await db.getMembers()).single;
    await pumpMembersScreen(tester);
    final row = rowFor(member.id);
    final slot = nameSlotFor(member.id);
    final heightBefore = tester.getSize(row).height;
    final widthBefore = tester.getSize(slot).width;
    final counter = find.byKey(ValueKey('member-counter-${member.id}'));
    expect(tester.widget<Visibility>(counter).visible, isFalse);

    await tester.tap(find.text('自分'));
    await tester.pump();

    expect(tester.widget<Visibility>(counter).visible, isTrue);
    expect(tester.getSize(row).height, heightBefore);
    expect(tester.getSize(slot).width, widthBefore);
    expect(heightBefore, 72);
  });

  testWidgets('文字倍率2.0でもカウンタ末尾が切れず名前幅が動かない', (tester) async {
    final member = (await db.getMembers()).single;
    await pumpMembersScreen(tester, textScaler: const TextScaler.linear(2));
    final slot = nameSlotFor(member.id);
    final widthBefore = tester.getSize(slot).width;
    await tester.tap(find.text('自分'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'あ' * 50);
    await tester.pump();

    final counter = find.byKey(ValueKey('member-counter-${member.id}'));
    final counterText = find.descendant(
      of: counter,
      matching: find.text('50/50'),
    );
    final paragraph = tester.renderObject<RenderParagraph>(counterText);
    expect(
      paragraph.getMaxIntrinsicWidth(double.infinity),
      lessThanOrEqualTo(tester.getSize(counterText).width),
    );
    expect(tester.getSize(slot).width, widthBefore);
    expect(tester.takeException(), isNull);
  });

  testWidgets('文字倍率2.0では編集欄に合わせて行が下端まで伸びる', (tester) async {
    final member = (await db.getMembers()).single;
    await pumpMembersScreen(tester, textScaler: const TextScaler.linear(2));
    final row = rowFor(member.id);
    final heightBefore = tester.getSize(row).height;

    await tester.tap(find.text('自分'));
    await tester.pump();

    final field = find.byType(TextField);
    final heightWhileEditing = tester.getSize(row).height;
    expect(heightBefore, 72);
    expect(heightWhileEditing, greaterThan(heightBefore));
    expect(
      tester.getBottomLeft(field).dy,
      lessThanOrEqualTo(tester.getBottomLeft(row).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('50文字名は非編集中に省略し、描画例外を起こさない', (tester) async {
    final name = 'あ' * 50;
    await db.updateMemberName((await db.getMembers()).single.id, name);
    await pumpMembersScreen(tester);

    expect(find.text(name), findsOneWidget);
    expect(isEllipsized(tester, name), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('メンバーが無いときはアイコン付きの空状態を描く', (tester) async {
    for (final member in await db.getMembers()) {
      await db.deleteMember(member.id);
    }
    await pumpMembersScreen(tester);

    final empty = find.ancestor(
      of: find.text('メンバーがいません'),
      matching: find.byType(Column),
    );
    expect(
      find.descendant(of: empty, matching: find.byIcon(Icons.people_outline)),
      findsOneWidget,
    );
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
