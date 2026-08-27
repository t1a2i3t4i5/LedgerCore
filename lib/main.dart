import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'db/database.dart';
import 'logging/file_log_sink.dart';
import 'logging/operation_logger.dart';
import 'providers/category_provider.dart';
import 'providers/member_provider.dart';
import 'providers/month_scoped_provider.dart';
import 'providers/summary_provider.dart';
import 'providers/transaction_provider.dart';
import 'screens/main_screen.dart';

void main() {
  // ゾーンのエラーハンドラから参照するので、外側に置いて後から差し替える。
  // 初期化が終わるまでのエラーは何も書かないロガーに落ちる（ログは取れないが、
  // ログの都合で起動が止まるほうが困る）
  var logger = OperationLogger.noop();

  // **`ensureInitialized()` はこのゾーンの中で呼ぶ。** 外で呼ぶと binding が
  // root zone に紐づき、別ゾーンから runApp することになって Flutter が
  // ゾーンの不一致を報告する
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      _registerFontLicenses();
      logger = await _createLogger();

      // 描画中の例外。presentError を呼び直して、今までどおり赤い画面と
      // コンソール出力も出す（ログに移すのではなく、ログにも残す）
      FlutterError.onError = (details) {
        logger.error('app.uncaught', '${details.exception}\n${details.stack}');
        FlutterError.presentError(details);
      };

      final db = AppDatabase();
      runApp(LedgerApp(db: db, logger: logger));
    },
    (error, stack) {
      // 非同期の未捕捉例外。スタックは error 側に載せて、長すぎるぶんは
      // LogEntry の truncate に任せる
      //
      // **コンソールにも出し直す。** runZonedGuarded を挟むと、それまで
      // 未捕捉の非同期例外を stderr へ出していた Dart 既定のハンドラが
      // このハンドラに置き換わる。ログに書くだけだと flutter run 中の
      // コンソールから例外が消え、ロガーが noop に倒れた端末では
      // どこにも残らなくなる。同期側の FlutterError.onError が
      // presentError() を呼び直しているのと揃える
      debugPrint('未捕捉の非同期例外: $error\n$stack');
      logger.error('app.uncaught', '$error\n$stack');
    },
  );
}

/// 同梱フォントの SIL Open Font License をライセンス画面へ登録する。
void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final file in const [
      'OFL-ZenMaruGothic',
      'OFL-ZenKakuGothicNew',
      'OFL-Outfit',
    ]) {
      yield LicenseEntryWithLineBreaks([
        'fonts',
      ], await rootBundle.loadString('assets/fonts/$file.txt'));
    }
  });
}

/// 端末内のログファイルへ書くロガーを組み立てる。
///
/// **失敗してもアプリは必ず起動する。** 書き込み先が取れない端末で家計簿が
/// 使えなくなるほうが、ログが残らないことより重い
Future<OperationLogger> _createLogger() async {
  try {
    // パスの解決はここだけで行う。FileLogSink はディレクトリを引数で受け取る
    // ので、テストは path_provider を通さずに一時ディレクトリを渡せる
    final directory = await getApplicationDocumentsDirectory();
    return OperationLogger(FileLogSink(directory));
  } catch (e) {
    debugPrint('操作ログの初期化に失敗しました。ログ無しで起動します: $e');
    return OperationLogger.noop();
  }
}

class LedgerApp extends StatelessWidget {
  final AppDatabase db;

  /// 表示月の基準となる「今」。既定（null）は [DateTime.now]。
  /// テストから固定時刻を注入して、画面を実時刻から切り離すために使う
  final Clock? clock;

  /// 操作ログの出力先。既定（null）は何も書かないロガー。
  /// テストから [MemoryLogSink] 付きのロガーを注入して中身を確かめる
  final OperationLogger? logger;

  const LedgerApp({super.key, required this.db, this.clock, this.logger});

  @override
  Widget build(BuildContext context) {
    final log = logger ?? OperationLogger.noop();

    return MultiProvider(
      providers: [
        // 画面からもログを出す（タブの切り替えは Provider を通らない）ため、
        // ツリーに置いて context.read<OperationLogger>() で拾えるようにする。
        // ChangeNotifier ではないので素の Provider
        Provider<OperationLogger>.value(value: log),
        ChangeNotifierProvider(create: (_) => MemberProvider(db, logger: log)),
        ChangeNotifierProvider(
          create: (_) => TransactionProvider(db, clock: clock, logger: log),
        ),
        ChangeNotifierProvider(
          create: (_) => CategoryProvider(db, logger: log),
        ),
        ChangeNotifierProvider(
          create: (_) => SummaryProvider(db, clock: clock, logger: log),
        ),
      ],
      child: MaterialApp(
        title: '家計簿',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        // 認証は撤廃。起動後すぐにメイン画面へ。
        home: const MainScreen(),
      ),
    );
  }
}
