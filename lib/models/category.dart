/// カテゴリの表示用モデル
class CategoryView {
  final int id;
  final String name;
  final int? colorValue;
  final int sortOrder;

  /// 削除と並べ替えができない受け皿カテゴリかどうか。名前と色は変えられる。
  final bool isFixed;

  const CategoryView({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.sortOrder,
    this.isFixed = false,
  });
}
