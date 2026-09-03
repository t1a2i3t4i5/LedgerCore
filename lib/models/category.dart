/// カテゴリの表示用モデル
class CategoryView {
  final int id;
  final String name;
  final int? colorValue;
  final int sortOrder;

  const CategoryView({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.sortOrder,
  });
}
