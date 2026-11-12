// lib/models/editable_dict_item.dart
class EditableDictItem {
  final int? id;
  final String originalName;
  String newName;
  bool isDeleted;
  bool isModified;

  EditableDictItem({
    this.id,
    required this.originalName,
  })  : newName = originalName,
        isDeleted = false,
        isModified = false;

  // Сброс к исходному состоянию
  void reset() {
    newName = originalName;
    isDeleted = false;
    isModified = false;
  }
}