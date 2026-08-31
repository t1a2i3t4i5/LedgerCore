import 'dart:io';

import 'package:path/path.dart' as p;

import 'file_log_sink.dart';

/// ログの内容は加工せず、末尾改行のない退避ログとの境界だけを補う。
String combineLogs({required String rotated, required String current}) {
  if (rotated.isEmpty) return current;
  if (current.isEmpty) return rotated;
  final separator = rotated.endsWith('\n') ? '' : '\n';
  return '$rotated$separator$current';
}

/// OS のファイル名に使えないコロンを避けた、共有専用の名前。
String logExportFileName(DateTime time) {
  String pad(int value, [int width = 2]) =>
      value.toString().padLeft(width, '0');
  return 'ledgercore-${pad(time.year, 4)}${pad(time.month)}${pad(time.day)}-'
      '${pad(time.hour)}${pad(time.minute)}${pad(time.second)}.txt';
}

/// 書き込み側と同じディレクトリから、退避→現行の順に読む。
/// 呼び出し側は OperationLogger.withPausedWrites で世代交代との競合を防ぐ。
Future<String> readLogsForExport(Directory directory) async {
  Future<String> read(String name) async {
    final file = File(p.join(directory.path, name));
    return await file.exists() ? file.readAsString() : '';
  }

  final rotated = await read(kRotatedLogFileName);
  final current = await read(kLogFileName);
  return combineLogs(rotated: rotated, current: current);
}
