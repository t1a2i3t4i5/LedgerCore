import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import 'log_export.dart';
import 'log_share.dart';
import 'operation_logger.dart';

/// ファイルの組み立てと OS の共有シートをつなぐ。
/// テストは shareFile を差し替え、プラグインを起動せず添付を検証する。
class FileLogShare implements LogShare {
  final Directory directory;
  final OperationLogger logger;
  final Future<Directory> Function() temporaryDirectory;
  final Future<void> Function(File file, Rect origin) _shareFile;
  final LogClock _clock;
  bool _sharing = false;

  FileLogShare({
    required this.directory,
    required this.logger,
    required this.temporaryDirectory,
    Future<void> Function(File file, Rect origin)? shareFile,
    LogClock? clock,
  }) : _shareFile = shareFile ?? _openShareSheet,
       _clock = clock ?? DateTime.now;

  @override
  Future<bool> share({required Rect origin}) async {
    // 設定タブを離れて戻ると画面の State は作り直されるので、ここでも防ぐ。
    if (_sharing) return true;
    _sharing = true;
    Directory? exportDirectory;
    try {
      // 最初の await より前にキューへ予約する。直後の log.share は
      // この読み出しより後へ並ぶので、空ログを押下記録だけで非空にしない。
      final contents = await logger.withPausedWrites(
        () => readLogsForExport(directory),
      );
      if (contents.trim().isEmpty) return false;

      final temporary = await temporaryDirectory();
      exportDirectory = await temporary.createTemp('ledgercore-log-share-');
      final file = File(
        p.join(exportDirectory.path, logExportFileName(_clock())),
      );
      await file.writeAsString(contents, flush: true);
      // OS を待つ間はロガーを止めない。元のログや DB は一切渡さない。
      await _shareFile(file, origin);
      return true;
    } finally {
      try {
        // iOS は共有の完了・キャンセル後に戻る。渡したコピーだけ片付ける。
        if (exportDirectory != null) {
          await exportDirectory.delete(recursive: true);
        }
      } catch (e) {
        // 後片付けの失敗で共有結果を上書きしない。残りは OS の一時領域。
        debugPrint('共有用ログの後片付けに失敗しました: $e');
      } finally {
        _sharing = false;
      }
    }
  }

  static Future<void> _openShareSheet(File file, Rect origin) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain')],
        sharePositionOrigin: origin,
      ),
    );
  }
}
