// lib/models/import_state.dart
import 'package:flutter/foundation.dart';
import 'product.dart';

enum ImportStep { sheets, columns, emptyCells, duplicates, mode, report }
enum ImportMode { addOnly, updateOnly, updateAndAdd }

enum CategorySource { column, separatorRows, fallbackOnly }

class SheetConfig {
  final String sheetName;
  final String format; // 'catalog' | 'pricelist'
  final CategorySource categorySource;
  
  final List<String> headerLabels;
  final Map<String, List<int>> availableColumns;
  final Map<String, int?> selectedColumns;
  final int headerRowIndex;
  final List<dynamic> dataRows;
  
  // Список найденных в файле категорий (для отображения в UI)
  final List<String> detectedCategories; 
  
  // Категория по умолчанию (для формы C или если разделитель не распознан)
  String fallbackCategory;

  SheetConfig({
    required this.sheetName,
    required this.format,
    required this.categorySource,
    required this.headerLabels,
    required this.availableColumns,
    required this.selectedColumns,
    required this.headerRowIndex,
    required this.dataRows,
    this.detectedCategories = const [],
    this.fallbackCategory = 'Другое',
  });

  bool get hasName => selectedColumns['name'] != null;
  bool get hasCategory => categorySource == CategorySource.column 
      ? selectedColumns['category'] != null 
      : true; // Для прайсов категория всегда "есть" (через разделители или дефолт)
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
    List<String>? selectedSheets,          // ← было this.selectedSheets = const []
    Map<String, SheetConfig>? configs,
    Map<String, String>? duplicatePriorities,
    List<DuplicateGroup>? duplicates,      // ← на всякий случай тоже
  })  : selectedSheets = selectedSheets ?? [],     // ← новый mutable-список
        configs = configs ?? {},
        duplicatePriorities = duplicatePriorities ?? {},
        duplicates = duplicates ?? [];

  void notify() => notifyListeners();
}