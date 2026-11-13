// lib/services/import_service.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../database/database_helper.dart';
import '../models/product.dart';
import '../models/import_state.dart';
import '../utils/data_normalizer.dart';

class ImportService {
  
  // Словарь вынесен на уровень класса (сюда!)
  static const Map<String, List<String>> _columnKeywords = {
    'name': [
      'название препарата', 'наименование препарата', 'название удобрения', 'номенклатура',
      'название', 'наименование', 'препарат', 'продукт', 'товар', 'удобрение', 'средство'
    ],
    'category': [
      'категория', 'группа', 'раздел', 'класс', 'тип', 'вид'
    ],
    'composition': [
      'действующее вещество', 'действующие вещества', 'состав', 'дв', 'формула', 'компонент'
    ],
    'manufacturer': [
      'производитель', 'изготовитель', 'компания', 'бренд', 'фирма', 'вендор', 'торговая марка'
    ],
    'package': [
      'фасовка', 'упаковка', 'объем', 'объём', 'тара', 'единица'
    ],
    'rate': [
      'норма расхода', 'расход', 'дозировка', 'норматив'
    ],
    'price': [
      'цена за ед', 'цена', 'стоимость', 'прайс', 'тариф', 'с ндс', 'без ндс', 'руб'
    ],
    'description': [
      'описание', 'применение', 'характеристики', 'назначение', 'свойства', 'инструкция'
    ],
    'cultures': [
      'культуры', 'обрабатываемые', 'растения', 'посевы'
    ],
    'diseases': [
      'болезни', 'заболевания', 'вредители', 'вредные объекты', 'сорняки', 'защита от'
    ],
  };

  // === 1. АНАЛИЗ ЛИСТА (Скоринг шапки) ===
  static SheetConfig? analyzeSheet(Sheet sheet, String sheetName) {
    int bestScore = 0;
    int headerRowIndex = -1;

    // 1. Поиск строки шапки с помощью весов
    for (int i = 0; i < sheet.rows.length && i < 30; i++) {
      final row = sheet.rows[i];
      if (row.isEmpty) continue;
      final rowStr = row.map((c) => c?.value?.toString().toLowerCase() ?? '').join(' ');
      
      if (rowStr.contains('id заказа')) return null; 

      int score = 0;
      if (_columnKeywords['name']!.any((kw) => rowStr.contains(kw))) score += 3;
      if (_columnKeywords['price']!.any((kw) => rowStr.contains(kw))) score += 2;
      if (_columnKeywords['composition']!.any((kw) => rowStr.contains(kw)) ||
          _columnKeywords['manufacturer']!.any((kw) => rowStr.contains(kw)) ||
          _columnKeywords['package']!.any((kw) => rowStr.contains(kw)) ||
          _columnKeywords['rate']!.any((kw) => rowStr.contains(kw))) score += 1;

      if (score > bestScore && score >= 3) {
        bestScore = score;
        headerRowIndex = i;
      }
    }

    if (headerRowIndex == -1) return null;

    final headerRow = sheet.rows[headerRowIndex];
    final headerLabels = headerRow.map((c) => c?.value?.toString().trim() ?? '').toList();
    
    // 2. Распределение колонок с учетом весов
    final Map<String, List<int>> availableColumns = {};
    final Map<String, int?> selectedColumns = {};

    _columnKeywords.forEach((field, keywords) {
      availableColumns[field] = [];
      int? bestIdx = null;
      int bestColScore = 0;

      for (int i = 0; i < headerLabels.length; i++) {
        final lower = headerLabels[i].toLowerCase().trim();
        if (lower.isEmpty) continue;

        int colScore = 0;
        for (int k = 0; k < keywords.length; k++) {
          if (lower.contains(keywords[k])) {
            int weight = (keywords.length - k) * 10 + keywords[k].length;
            if (weight > colScore) colScore = weight;
          }
        }

        if (colScore > 0) {
          availableColumns[field]!.add(i);
          if (colScore > bestColScore) {
            bestColScore = colScore;
            bestIdx = i;
          }
        }
      }
      selectedColumns[field] = bestIdx;
    });

    // 3. Определяем формат
    final hasCategoryCol = availableColumns['category']!.isNotEmpty;
    final dataRows = sheet.rows.sublist(headerRowIndex + 1);

    // Собираем категории из разделителей (если колонки нет)
    final List<String> detectedCats = [];
    if (!hasCategoryCol) {
      for (var row in dataRows) {
        if (row.isEmpty) continue;
        for (int i = 0; i < row.length; i++) {
          if (i == selectedColumns['name']) continue;
          final val = row[i]?.value?.toString() ?? '';
          final normType = DataNormalizer.normalizeProductType(val);
          if (normType != 'Другое' && !detectedCats.contains(normType)) {
             detectedCats.add(normType);
          }
        }
      }
    }

    return SheetConfig(
      sheetName: sheetName,
      format: hasCategoryCol ? 'catalog' : 'pricelist',
      categorySource: hasCategoryCol 
          ? CategorySource.column 
          : (detectedCats.isNotEmpty ? CategorySource.separatorRows : CategorySource.fallbackOnly),
      detectedCategories: detectedCats,
      headerLabels: headerLabels,
      availableColumns: availableColumns,
      selectedColumns: selectedColumns,
      headerRowIndex: headerRowIndex,
      dataRows: dataRows,
    );
  }

  // === 2. ПАРСИНГ ЛИСТА ===
  static List<Product> parseSheet(
    SheetConfig config,
    SheetStats stats, {
    required List<String> knownCultures,
    required List<String> knownDiseases,
    required bool ignoreEmptyCells,
  }) {
    final List<Product> products = [];
    final int nameIdx = config.selectedColumns['name'] ?? -1;
    if (nameIdx == -1) return products;

    final categoryIdx = config.selectedColumns['category'] ?? -1;
    final compIdx = config.selectedColumns['composition'] ?? -1;
    final manIdx = config.selectedColumns['manufacturer'] ?? -1;
    final packIdx = config.selectedColumns['package'] ?? -1;
    final rateIdx = config.selectedColumns['rate'] ?? -1;
    final priceIdx = config.selectedColumns['price'] ?? -1;
    final descIdx = config.selectedColumns['description'] ?? -1;
    final cultIdx = config.selectedColumns['cultures'] ?? -1;
    final disIdx = config.selectedColumns['diseases'] ?? -1;

    String currentCategory = config.fallbackCategory;

    for (int i = 0; i < config.dataRows.length; i++) {
      final row = config.dataRows[i];
      if (row.isEmpty) continue;

      String getCell(int idx) => (idx != -1 && idx < row.length) ? (row[idx]?.value?.toString().trim() ?? '') : '';

      // 1. Проверяем на строку-разделитель (только если колонки "Категория" нет)
      if (config.categorySource != CategorySource.column) {
        bool isSeparator = false;
        for (int c = 0; c < row.length; c++) {
          if (c == nameIdx) continue; // не считаем колонку с названием
          final val = getCell(c);
          if (val.isNotEmpty) {
            final norm = DataNormalizer.normalizeProductType(val);
            if (norm != 'Другое') {
              currentCategory = norm; // Обновили категорию
              isSeparator = true;
              break;
            }
          }
        }
        if (isSeparator) continue; // Переходим к следующей строке
      }

      // 2. Парсим препарат
      final name = getCell(nameIdx);
      if (name.isEmpty) continue; // Название обязательно всегда

      // Пропускаем очевидный мусор (итого, всего)
      final upperName = name.toUpperCase();
      if (upperName.startsWith('ИТОГО') || upperName.startsWith('ВСЕГО')) continue;

      stats.totalRows++;

      final category = (config.categorySource == CategorySource.column) ? getCell(categoryIdx) : currentCategory;
      final composition = getCell(compIdx);
      final manufacturer = getCell(manIdx);
      final package = getCell(packIdx);
      final rateStr = getCell(rateIdx);
      final priceStr = getCell(priceIdx);
      final description = getCell(descIdx);

      // Нормализация
      double? price;
      if (priceStr.isNotEmpty) {
        price = double.tryParse(priceStr.replaceAll(',', '.').replaceAll(RegExp(r'[^\d.]'), ''));
        if (price == null) {
          stats.skipped++;
          stats.skippedDetails.add({'row': i+1, 'name': name, 'reason': 'Некорректная цена'});
          continue;
        }
      } else if (!ignoreEmptyCells) {
         price = null; // Затрем цену в БД, если разрешено
      }

      List<String> cultures = [];
      final cultStr = getCell(cultIdx);
      if (cultStr.isNotEmpty) {
         for (var c in cultStr.split(',')) {
            final norm = DataNormalizer.normalizeCategoryNameSync(c, isCulture: true, knownCultures: knownCultures, knownDiseases: knownDiseases);
            if (norm.isNotEmpty) {
              cultures.add(norm);
              if (!knownCultures.contains(norm)) {
                stats.newCultures.add(norm);
                knownCultures.add(norm);
            }
            }
         }
      }

      List<String> diseases = [];
      final disStr = getCell(disIdx);
      if (disStr.isNotEmpty) {
         for (var d in disStr.split(',')) {
            final norm = DataNormalizer.normalizeCategoryNameSync(d, isCulture: false, knownCultures: knownCultures, knownDiseases: knownDiseases);
            if (norm.isNotEmpty) {
               diseases.add(norm);
               if (!knownDiseases.contains(norm)) {
                stats.newDiseases.add(norm);
                knownDiseases.add(norm);
               }
            }
         }
      }

      products.add(Product(
        name: name,
        category: category, // Может быть пустым, проверим при сохранении
        composition: composition.isNotEmpty ? composition : null,
        manufacturer: manufacturer.isNotEmpty ? manufacturer : null,
        package: package.isNotEmpty ? package : null,
        consumptionRate: rateStr.isNotEmpty ? rateStr : null,
        price: price,
        description: description.isNotEmpty ? description : null,
        cultures: cultures,
        diseases: diseases,
      ));
      stats.accepted++;
    }
    return products;
  }

  // === 3. ПОИСК ДУБЛЕЙ ===
  static List<DuplicateGroup> findDuplicates(List<Product> products, Map<Product, String> productToSheet) {
    final Map<String, List<DuplicateVariant>> grouped = {};
    
    for (var p in products) {
      final normName = p.name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      final sheetName = productToSheet[p] ?? 'Unknown'; 
      grouped.putIfAbsent(normName, () => []).add(
        DuplicateVariant(sheetName: sheetName, rowIndex: 0, product: p)
      );
    }

    final duplicates = <DuplicateGroup>[];
    grouped.forEach((normName, variants) {
      if (variants.length > 1) {
        duplicates.add(DuplicateGroup(normalizedName: normName, variants: variants));
      }
    });
    return duplicates;
  }

  // === 4. УМНОЕ СЛИЯНИЕ ДУБЛЕЙ ===
  static Product mergeDuplicates(DuplicateGroup group, String prioritySheetName) {
    // 1. Находим приоритетный вариант (основу)
    var priorityVariant = group.variants.firstWhere(
      (v) => v.sheetName == prioritySheetName, 
      orElse: () => group.variants.first
    );
    var merged = priorityVariant.product;

    // 2. Дополняем пустые поля из других вариантов
    for (var variant in group.variants) {
      if (variant.sheetName == prioritySheetName) continue;
      var p = variant.product;
      
      merged = Product(
        id: merged.id,
        name: merged.name,
        category: merged.category.isNotEmpty ? merged.category : p.category,
        composition: merged.composition ?? p.composition,
        manufacturer: merged.manufacturer ?? p.manufacturer,
        package: merged.package ?? p.package,
        consumptionRate: merged.consumptionRate ?? p.consumptionRate,
        price: merged.price ?? p.price,
        description: merged.description ?? p.description,
        cultures: {...merged.cultures, ...p.cultures}.toList(),
        diseases: {...merged.diseases, ...p.diseases}.toList(),
      );
    }
    return merged;
  }

  // === 5. ЭКСПОРТ ДУБЛЕЙ ===
  static Future<void> exportDuplicatesToExcel(List<DuplicateGroup> duplicates) async {
    final excel = Excel.createExcel();
    final sheet = excel['Дубли'];
    
    sheet.appendRow([
      TextCellValue('ЛИСТ'), TextCellValue('Название'), TextCellValue('Тип'),
      TextCellValue('Состав'), TextCellValue('Описание'), TextCellValue('Норма'),
      TextCellValue('Фасовка'), TextCellValue('Цена'), TextCellValue('Производитель'),
      TextCellValue('Культуры'), TextCellValue('Болезни'),
    ]);

    for (var group in duplicates) {
      for (var variant in group.variants) {
        var p = variant.product;
        sheet.appendRow([
          TextCellValue(variant.sheetName),
          TextCellValue(p.name),
          TextCellValue(p.category),
          TextCellValue(p.composition ?? ''),
          TextCellValue(p.description ?? ''),
          TextCellValue(p.consumptionRate ?? ''),
          TextCellValue(p.package ?? ''),
          p.price != null ? DoubleCellValue(p.price!) : TextCellValue(''),
          TextCellValue(p.manufacturer ?? ''),
          TextCellValue(p.cultures.join(', ')),
          TextCellValue(p.diseases.join(', ')),
        ]);
      }
    }

    final bytes = excel.save();
    if (bytes == null) return;

    final uint8Bytes = Uint8List.fromList(bytes); // Конвертируем в Uint8List

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/duplicates_${DateTime.now().millisecondsSinceEpoch}.xlsx');
    await file.writeAsBytes(uint8Bytes);

    await FilePicker.saveFile(
      dialogTitle: 'Сохранить дубли',
      fileName: 'duplicates.xlsx',
      bytes: uint8Bytes, // Передаем Uint8List
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

  }

  // === 6. ПРИМЕНЕНИЕ ИМПОРТА ===
  static Future<ImportResult> applyImport(ImportState state) async {
    final db = DatabaseHelper.instance;
    final database = await db.database;
    
    int added = 0;
    int updated = 0;
    int skipped = 0;
    List<String> errors = [];

    final allProducts = await db.getAllProducts();
    final existingProductsMap = {
      for (var prod in allProducts)
        prod.name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase(): prod
    };


    await database.transaction((txn) async {
      for (var p in state.parsedProducts) {
        final normName = p.name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
        final existingProduct = existingProductsMap[normName];
        final isExisting = existingProduct != null;

        // 1. Валидация для НОВЫХ препаратов
        if (!isExisting && p.category.isEmpty) {
          skipped++;
          errors.add('${p.name}: нет категории (пропущен)');
          continue;
        }

        // 2. Обновление существующего
        if (isExisting) {
          if (state.mode == ImportMode.addOnly) {
            skipped++;
            continue;
          }

          final id = existingProduct.id!;

          if (state.ignoreEmptyCells) {
            final mergedProduct = Product(
              id: id,
              name: p.name,
              category: p.category.isNotEmpty ? p.category : existingProduct.category,
              composition: p.composition ?? existingProduct.composition,
              manufacturer: p.manufacturer ?? existingProduct.manufacturer,
              package: p.package ?? existingProduct.package,
              consumptionRate: p.consumptionRate ?? existingProduct.consumptionRate,
              price: p.price ?? existingProduct.price,
              description: p.description ?? existingProduct.description,
              cultures: p.cultures.isNotEmpty ? p.cultures : existingProduct.cultures,
              diseases: p.diseases.isNotEmpty ? p.diseases : existingProduct.diseases,
            );
            await db.updateProductWithExecutor(mergedProduct, txn);
            updated++;
          } else {
            await db.updateProductWithExecutor(p.copyWith(id: id), txn);
            updated++;
          }
        } 
        // 3. Добавление нового
        else {
          if (state.mode == ImportMode.updateOnly) {
            skipped++;
            continue;
          }
          final newId = await db.insertProductWithExecutor(p, txn);
          added++;
          // Добавляем в кэш, чтобы если в файле дважды "Дерби" с разными пробелами, не вставить дважды
          existingProductsMap[normName] = p.copyWith(id: newId); 
        }
      }
}).timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        throw Exception(
          'Импорт занял больше 60 секунд и был прерван. '
          'Скорее всего, в БД осталась блокировка — перезапустите приложение.',
        );
      },
    );
    return ImportResult(
      added: added, 
      updated: updated, 
      skipped: skipped, 
      errors: errors,
      newCultures: state.sheetStats.values.fold(0, (sum, s) => sum + s.newCultures.length),
      newDiseases: state.sheetStats.values.fold(0, (sum, s) => sum + s.newDiseases.length),
    );
  }

}