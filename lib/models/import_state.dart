// lib/models/import_state.dart
import 'package:flutter/foundation.dart';
import 'product.dart';

enum ImportStep { sheets, columns, emptyCells, duplicates, mode, report }
enum ImportMode { addOnly, updateOnly, updateAndAdd }

class SheetConfig {
  final String sheetName;
  final String format; // 'price' | 'catalog'
  final List<String> headerLabels;
  final Map<String, List<int>> availableColumns; // field -> indices
  final Map<String, int?> selectedColumns; // field -> chosen index
  final int headerRowIndex;
  final List<dynamic> dataRows;

  SheetConfig({
    required this.sheetName,
    required this.format,
    required this.headerLabels,
    required this.availableColumns,
    required this.selectedColumns,
    required this.headerRowIndex,
    required this.dataRows,
  });

  bool get hasName => selectedColumns['name'] != null;
  bool get hasCategory => selectedColumns['category'] != null;
  
  // Проверка на дубли колонок (например, две колонки "Цена")
  bool get hasDuplicateSelections {
    final selectedIndices = <int>[];
    for (var idx in selectedColumns.values) {
      if (idx != null) {
        if (selectedIndices.contains(idx)) return true;
        selectedIndices.add(idx);
      }
    }
    return false;
  }
}

class SheetStats {
  int totalRows = 0;
  int accepted = 0;
  int skipped = 0;
  final List<Map<String, dynamic>> skippedDetails = [];
  final Set<String> newCultures = {};
  final Set<String> newDiseases = {};
}

class DuplicateVariant {
  final String sheetName;
  final int rowIndex;
  final Product product;
  
  DuplicateVariant({
    required this.sheetName, 
    required this.rowIndex, 
    required this.product
  });
}

class DuplicateGroup {
  final String normalizedName;
  final List<DuplicateVariant> variants;
  
  DuplicateGroup({
    required this.normalizedName, 
    required this.variants
  });
}

class ImportResult {
  final int added;
  final int updated;
  final int skipped;
  final List<String> errors;
  final int newCultures;
  final int newDiseases;

  ImportResult({
    required this.added,
    required this.updated,
    required this.skipped,
    required this.errors,
    required this.newCultures,
    required this.newDiseases,
  });
}

class ImportState extends ChangeNotifier {
  String filePath;
  List<String> availableSheets;
  List<String> selectedSheets;
  Map<String, SheetConfig> configs;
  
  bool ignoreEmptyCells = true;
  
  // Приоритет для дублей: нормализованное имя -> имя листа
  Map<String, String> duplicatePriorities;
  List<DuplicateGroup> duplicates;
  bool duplicatesIgnored = false; // Если пользователь нажал "Игнорировать дубли"
  
  ImportMode mode = ImportMode.updateAndAdd;
  
  List<Product> parsedProducts = [];
  Map<String, SheetStats> sheetStats = {};
  
  // Результаты
  ImportResult? result;

  ImportState({
    required this.filePath,
    required this.availableSheets,
    this.selectedSheets = const [],
    Map<String, SheetConfig>? configs,
    Map<String, String>? duplicatePriorities,
    this.duplicates = const [],
  })  : configs = configs ?? {},
        duplicatePriorities = duplicatePriorities ?? {};

  void notify() => notifyListeners();
}