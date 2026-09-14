/// メンバー（割り勘の対象者）。端末内で管理する。
class HouseholdMember {
  final int id;
  final String name;
  final int? colorValue;

  const HouseholdMember({
    required this.id,
    required this.name,
    this.colorValue,
  });
}
