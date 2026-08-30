import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/main.dart';
import 'package:provider/provider.dart';
import 'package:ledger_app/providers/transaction_provider.dart';

/// 取引を保存したときのフィードバックを、UI を実際に操作して確かめる。
///
/// 保存の成否は DB を見れば分かるが、この画面の問題は「保存は成功しているのに
/// 画面上の変化がゼロ」という見え方のほうにある。表示月と保存先の月がずれると
/// 一覧にも合計にも現れないので、Provider のテストでは拾えない。
void main() {
  late AppDatabase db;

  // 表示月を実時刻から切り離す。この月が「今月」になる
  final fixedNow = DateTime(2026, 7, 15);

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(LedgerApp(db: db, clock: () => fixedNow));
    await tester.pumpAndSettle();

    // 起動直後はサマリータブなので、取引タブへ移る
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();
  }

  /// 取引追加画面を開く
  Future<void> openAddScreen(WidgetTester tester) async {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
  }

  /// 日付ピッカーを開き、[date] を明示的に選ぶ。
  ///
  /// 既定日付は実時刻の「今日」なので（CLAUDE.md の約束どおり clock では
  /// 動かない）、テストが実行月に左右されないよう必ず打ち直す。
  /// カレンダーの升目を辿ると初期表示月が実時刻依存になるため、
  /// テキスト入力モードに切り替えて日付を直接打ち込む
  Future<void> pickDate(WidgetTester tester, DateTime date) async {
    await tester.tap(
      find.ancestor(
        of: find.byIcon(Icons.calendar_today),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();

    // カレンダー ⇄ テキスト入力の切り替えボタン
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    // ロケール未指定なので MaterialLocalizations の既定（en_US）の書式
    final text =
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.day.toString().padLeft(2, '0')}/${date.year}';
    await tester.enterText(
      find.descendant(
        of: find.byType(InputDatePickerFormField),
        matching: find.byType(TextField),
      ),
      text,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  /// 金額とカテゴリを埋めて保存する
  Future<void> fillAndSave(WidgetTester tester, String amount) async {
    final firstCategory = (await db.getCategories()).first.name;
    await tester.enterText(find.byType(TextFormField).first, amount);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(firstCategory).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
  }

  testWidgets('キャンセルで入力を保存せず一覧へ戻る', (tester) async {
    await pumpApp(tester);
    await openAddScreen(tester);
    await tester.enterText(find.byType(TextFormField).first, '1500');

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    expect(find.text('支出を追加'), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(await db.getAllTransactions(), isEmpty);
  });

  testWidgets('表示月と同じ月に保存すると一覧に出て、保存した旨が出る', (tester) async {
    await pumpApp(tester);
    expect(find.text('2026年7月'), findsOneWidget);

    await openAddScreen(tester);
    await pickDate(tester, DateTime(2026, 7, 20));
    await fillAndSave(tester, '1500');

    // 一覧に増えている（従来どおりの挙動）
    expect(find.text('¥1,500'), findsNWidgets(2));
    // 成功時も無言で閉じない
    expect(find.text('保存しました'), findsOneWidget);
    // 同じ月なら月名を名乗る必要はなく、移動先も無い
    expect(find.text('その月を表示'), findsNothing);
  });

  testWidgets('表示月と違う月に保存すると、保存先の月を名指しした案内が出る', (tester) async {
    await pumpApp(tester);

    await openAddScreen(tester);
    await pickDate(tester, DateTime(2026, 8, 7));
    await fillAndSave(tester, '1500');

    // 保存は成功しているが、7 月の一覧には現れない
    expect((await db.getAllTransactions()).length, 1);
    expect(find.text('2026年7月'), findsOneWidget);
    expect(find.text('取引がありません'), findsOneWidget);

    // 「失敗した」と読まれないよう、保存先の月を名指しする
    expect(find.text('2026年8月に保存しました'), findsOneWidget);
  });

  testWidgets('「その月を表示」で保存先の月へ移り、一覧に現れる', (tester) async {
    await pumpApp(tester);

    await openAddScreen(tester);
    await pickDate(tester, DateTime(2026, 8, 7));
    await fillAndSave(tester, '1500');
    expect(find.text('¥1,500'), findsNothing);

    await tester.tap(find.text('その月を表示'));
    await tester.pumpAndSettle();

    // 表示月が移ったうえで、その月のデータを読み直している
    expect(find.text('2026年8月'), findsOneWidget);
    expect(find.text('¥1,500'), findsNWidgets(2));
  });

  testWidgets('保存後に表示月が勝手に動かない', (tester) async {
    // 閲覧中の月を無断で移さない。案内を無視した（押さなかった）ときは
    // 元の月を見続けられる
    await pumpApp(tester);

    await openAddScreen(tester);
    await pickDate(tester, DateTime(2026, 8, 7));
    await fillAndSave(tester, '1500');

    expect(find.text('2026年7月'), findsOneWidget);
    expect(find.text('2026年8月'), findsNothing);
  });

  testWidgets('日付欄は表示月と違う月を選んだ時点で知らせる', (tester) async {
    // 事後の SnackBar より前に、保存する前の段階で気づける
    await pumpApp(tester);
    await openAddScreen(tester);

    await pickDate(tester, DateTime(2026, 7, 20));
    expect(find.text('表示中の2026年7月とは別の月です'), findsNothing);

    await pickDate(tester, DateTime(2026, 8, 7));
    expect(find.text('表示中の2026年7月とは別の月です'), findsOneWidget);
  });

  testWidgets('編集で別の月へ動かしたときも案内が出る', (tester) async {
    // 追加だけでなく編集も同じ穴を持つ。日付を翌月に直すと一覧から消える
    await pumpApp(tester);
    await openAddScreen(tester);
    await pickDate(tester, DateTime(2026, 7, 20));
    await fillAndSave(tester, '1500');
    expect(find.text('¥1,500'), findsNWidgets(2));

    // 一覧の行をタップして編集画面へ
    await tester.tap(
      find.descendant(of: find.byType(ListTile), matching: find.text('¥1,500')),
    );
    await tester.pumpAndSettle();
    await pickDate(tester, DateTime(2026, 8, 7));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('2026年8月に保存しました'), findsOneWidget);
    expect(find.text('¥0'), findsOneWidget);

    await tester.tap(find.text('その月を表示'));
    await tester.pumpAndSettle();
    expect(find.text('2026年8月'), findsOneWidget);
    expect(find.text('¥1,500'), findsNWidgets(2));
  });

  testWidgets('保存に失敗したときは成功の案内を出さない', (tester) async {
    // 成功時 SnackBar を足したことで、失敗しても「保存しました」が出る
    // 経路を作っていないことを見る。選択済みのカテゴリを DB から消して
    // 外部キー制約で insert を落とす（画面の入力は正しいまま失敗する）
    await pumpApp(tester);
    await openAddScreen(tester);
    await pickDate(tester, DateTime(2026, 7, 20));

    final firstCategory = (await db.getCategories()).first;
    await tester.enterText(find.byType(TextFormField).first, '1500');
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(firstCategory.name).last);
    await tester.pumpAndSettle();

    await db.deleteCategory(firstCategory.id);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(await db.getAllTransactions(), isEmpty);
    expect(find.text('保存しました'), findsNothing);
    expect(find.textContaining('保存失敗'), findsOneWidget);
    // 失敗したのだから画面は閉じない（入力をやり直せる）
    expect(find.text('支出を編集'), findsNothing);
    expect(find.text('支出を追加'), findsOneWidget);
  });

  testWidgets('別月の案内は表示中の Provider の月を基準にする', (tester) async {
    // 月を送ってから追加すると、基準は「送った先の月」になる。
    // 起動時の月で判定していると、ここで誤った案内が出る
    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text('2026年6月'), findsOneWidget);

    await openAddScreen(tester);
    await pickDate(tester, DateTime(2026, 7, 20));
    expect(find.text('表示中の2026年6月とは別の月です'), findsOneWidget);
    await fillAndSave(tester, '1500');

    expect(find.text('2026年7月に保存しました'), findsOneWidget);

    await tester.tap(find.text('その月を表示'));
    await tester.pumpAndSettle();
    expect(find.text('2026年7月'), findsOneWidget);
    expect(find.text('¥1,500'), findsNWidgets(2));
  });

  testWidgets('goToMonth は月選択の状態を壊さない', (tester) async {
    // 「その月を表示」で飛んだあとも、通常の月送りがそこから続く
    await pumpApp(tester);
    await openAddScreen(tester);
    await pickDate(tester, DateTime(2026, 8, 7));
    await fillAndSave(tester, '1500');
    await tester.tap(find.text('その月を表示'));
    await tester.pumpAndSettle();

    // 飛んだ先は「今月」(2026年7月) ではないので、今月に戻るボタンが押せる
    final todayButton = tester.widget<IconButton>(
      find.ancestor(of: find.text('今月'), matching: find.byType(IconButton)),
    );
    expect(todayButton.onPressed, isNotNull);

    await tester.tap(find.text('今月'));
    await tester.pumpAndSettle();
    expect(find.text('2026年7月'), findsOneWidget);
  });

  testWidgets('案内が出ている間も FAB で次の取引を追加できる', (tester) async {
    // SnackBar は MainScreen 側（ルートの ScaffoldMessenger）に出るので、
    // 取引一覧の FAB は押し上げられない。既定の fixed のままだと
    // 「その月を表示」が FAB にぴたりと重なり、続けて 1 件追加しようとした
    // タップが月移動になる（実測: FAB の座標でヒットするのは SnackBarAction）
    await pumpApp(tester);
    await openAddScreen(tester);
    await pickDate(tester, DateTime(2026, 8, 7));
    await fillAndSave(tester, '1500');
    expect(find.text('その月を表示'), findsOneWidget);

    // 案内が出ている間に FAB を押す
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // 追加画面が開く。月が動いていない（＝アクションを踏んでいない）
    expect(find.text('支出を追加'), findsOneWidget);
    expect(find.text('2026年8月'), findsNothing);
  });

  testWidgets('別のタブへ移ると案内は消える', (tester) async {
    // 残ったまま押せてしまうと、画面は何も変わらないのに取引一覧の表示月
    // だけが裏で動く。閲覧文脈が変わった以上、案内も一緒に引き取る
    await pumpApp(tester);
    final provider = Provider.of<TransactionProvider>(
      tester.element(find.byType(FloatingActionButton)),
      listen: false,
    );
    await openAddScreen(tester);
    await pickDate(tester, DateTime(2026, 8, 7));
    await fillAndSave(tester, '1500');
    expect(find.text('その月を表示'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.bar_chart_outlined));
    await tester.pumpAndSettle();

    expect(find.text('その月を表示'), findsNothing);
    expect(find.text('2026年8月に保存しました'), findsNothing);
    // 取引タブへ戻っても、勝手に月が動いていない
    expect(provider.month, 7);
  });

  testWidgets('追加画面の既定日付は表示月ではなく「今日」', (tester) async {
    // この機能は「既定日付が表示月と独立している」ことの上に成り立つ。
    // 表示月へ寄せる実装に変わると、過去月を見返している最中に思い出した
    // 今日の出費が徴候なくその月へ沈む（CLAUDE.md の約束）。
    // 寄せられてもこのファイルの他のテストは pickDate で日付を打ち直すため
    // 全部緑のまま通ってしまうので、既定値そのものをここで固定する
    final fmt = DateFormat('yyyy年MM月dd日');
    // now を 2 回読む間に日付が変わりうるので、前後どちらかに出ていれば良しとする
    final before = fmt.format(DateTime.now());
    await pumpApp(tester);
    await openAddScreen(tester);
    final after = fmt.format(DateTime.now());

    expect(
      {before, after}.any((t) => find.text(t).evaluate().isNotEmpty),
      isTrue,
      reason: '既定日付が実時刻の「今日」になっていない（表示月に寄せられた可能性）',
    );
  });

  testWidgets('Provider の表示月は保存の前後で変わらない', (tester) async {
    // 画面ではなく Provider の状態としても確認する
    await pumpApp(tester);
    final provider = Provider.of<TransactionProvider>(
      tester.element(find.byType(FloatingActionButton)),
      listen: false,
    );

    await openAddScreen(tester);
    await pickDate(tester, DateTime(2026, 8, 7));
    await fillAndSave(tester, '1500');

    expect(provider.year, 2026);
    expect(provider.month, 7);
  });
}
