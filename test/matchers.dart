import 'package:flutter_test/flutter_test.dart';

/// amount の CHECK 制約違反であることを確かめるマッチャ。
///
/// 単なる `isA<Exception>()` だと FK 違反や型エラーでも通ってしまい、
/// 「制約が効いている」ことの証明にならない。
///
/// 文言に列名（`CHECK constraint failed: amount`）まで含めないのは、
/// SQLite のバージョンによって列名ではなくテーブル名や制約式が入るため。
/// `sqlite3` パッケージは transitive 依存なので、型で縛らず文言で判定する。
final throwsAmountCheckViolation = throwsA(
  isA<Exception>().having(
    (e) => e.toString(),
    'メッセージ',
    contains('CHECK constraint failed'),
  ),
);

/// 外部キー制約違反であることを確かめるマッチャ。
final throwsForeignKeyViolation = throwsA(
  isA<Exception>().having(
    (e) => e.toString(),
    'メッセージ',
    contains('FOREIGN KEY constraint failed'),
  ),
);
