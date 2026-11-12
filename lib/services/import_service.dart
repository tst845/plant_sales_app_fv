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
  
  // === 1. АНАЛИЗ ЛИСТА ===
  static SheetConfig? analyzeSheet(Sheet sheet, String sheetName) {
    // 1. Определяем формат (Каталог с колонкой "Тип" или Прайс-лист с "№ п/п")
    String? format;
    int headerRowIndex = -1;

    for (int i = 0; i < sheet.rows.length && i < 30; i++) {
      final row = sheet.rows[i];
      if (row.isEmpty) continue;
      final rowStr = row.map((c) => c?.value?.toString().toLowerCase() ?? '').join(' ');
      
      if (rowStr.contains('тип') && rowStr.contains('название')) {
        format = 'catalog';
        headerRowIndex = i;
        break;
      }
      if (rowStr.contains('препарат') || rowStr.contains('наименование')) {
        format = 'price';
        headerRowIndex = i;
        break;
      }
    }

    if (format == null || headerRowIndex == -1) return null;

    final headerRow = sheet.rows[headerRowIndex];
    final headerLabels = headerRow.map((c) => c?.value?.toString().trim() ?? '').toList();
    
    // 2. Ищем возможные колонки по корням слов
    final Map<String, List<int>> availableColumns = {
      'name': [], 'category': [], 'composition': [], 'manufacturer': [],
      'package': [], 'rate': [], 'price': [], 'description': [],
      'cultures': [], 'diseases': [],
    };

    final keywords = {
      'name': ['препарат', 'название', 'наименование'],
      'category': ['тип', 'категория'],
      'composition': ['состав', 'действующ', 'веществ', 'дв'],
      'manufacturer': ['производитель'],
      'package': ['упаковк', 'фасовк'],
      'rate': ['норм', 'расход'],
      'price': ['цен', 'стоим', 'руб'],
      'description': ['описан', 'примен', 'характеристик'],
      'cultures': ['культур', 'обрабат'],
      'diseases': ['болезн', 'заболев', 'вредит'],
    };

    for (int i = 0; i < headerLabels.length; i++) {
      final lower = headerLabels[i].toLowerCase();
      if (lower.isEmpty) continue;
      
      for (var entry in keywords.entries) {
        for (var kw in entry.value) {
          if (lower.contains(kw)) {
            availableColumns[entry.key]!.add(i);
            break; 
          }
        }
      }
    }

    // По умолчанию выбираем первую найденную колонку для каждого поля
    final Map<String, int?> selectedColumns = {};
    availableColumns.forEach((key, indices) {
      selectedColumns[key] = indices.isNotEmpty ? indices.first : null;
    });

    return SheetConfig(
      sheetName: sheetName,
      format: format,
      headerLabels: headerLabels,
      availableColumns: availableColumns,
      selectedColumns: selectedColumns,
      headerRowIndex: headerRowIndex,
      dataRows: sheet.rows.sublist(headerRowIndex + 1),
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

    for (int i = 0; i < config.dataRows.length; i++) {
      final row = config.dataRows[i];
      if (row.isEmpty) continue;

      String getCell(int idx) => (idx != -1 && idx < row.length) ? (row[idx]?.value?.toString().trim() ?? '') : '';

      final name = getCell(nameIdx);
      if (name.isEmpty) continue; // Название обязательно всегда

      // Пропускаем строки-разделители (например, ГЕРБИЦИДЫ), если нет колонки категории
      if (categoryIdx == -1) {
         final upper = name.toUpperCase();
         if (upper == 'ГЕРБИЦИДЫ' || upper == 'ИНСЕКТИЦИДЫ' || upper == 'ФУНГИЦИДЫ') continue;
      }

      stats.totalRows++;

      final category = getCell(categoryIdx);
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
               if (!knownCultures.contains(norm)) stats.newCultures.add(norm);
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
               if (!knownDiseases.contains(norm)) stats.newDiseases.add(norm);
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

    final existingNamesSet = await db.getExistingProductNames();

    await database.transaction((txn) async {
      for (var p in state.parsedProducts) {
        bool isExisting = existingNamesSet.contains(p.name.trim().toLowerCase());
        
        // 1. Валидация для новых препаратов
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
          
          final existingProducts = await txn.query('products', columns: ['id'], where: 'name = ?', whereArgs: [p.name.trim()]);
          if (existingProducts.isNotEmpty) {
            final id = existingProducts.first['id'] as int;
            
            if (state.ignoreEmptyCells) {
              // УМНОЕ ОБНОВЛЕНИЕ: берем старые данные, если новые пустые
              final existingMaps = await txn.rawQuery('''
                SELECT p.*, c.name as category, m.name as manufacturer 
                FROM products p
                LEFT JOIN categories c ON p.category_id = c.id
                LEFT JOIN manufacturers m ON p.manufacturer_id = m.id
                WHERE p.id = ?
              ''', [id]);
              
              if (existingMaps.isNotEmpty) {
                final existingProduct = Product.fromMap(existingMaps.first);
                
                // Сливаем: приоритет у новых данных, если они не пусты
                final mergedProduct = Product(
                  id: id,
                  name: p.name, // Название всегда берем новое (или старое, они совпадают)
                  category: p.category.isNotEmpty ? p.category : existingProduct.category,
                  composition: p.composition ?? existingProduct.composition,
                  manufacturer: p.manufacturer ?? existingProduct.manufacturer,
                  package: p.package ?? existingProduct.package,
                  consumptionRate: p.consumptionRate ?? existingProduct.consumptionRate,
                  price: p.price ?? existingProduct.price,
                  description: p.description ?? existingProduct.description,
                  // Культуры/болезни берем из файла, если они там не пусты
                  cultures: p.cultures.isNotEmpty ? p.cultures : existingProduct.cultures,
                  diseases: p.diseases.isNotEmpty ? p.diseases : existingProduct.diseases,
                );
                
                await db.updateProduct(mergedProduct);
                updated++;
              }
            } else {
              // ПОЛНАЯ ПЕРЕЗАПИСЬ (ignoreEmptyCells == false)
              final updatedProduct = p.copyWith(id: id);
              await db.updateProduct(updatedProduct);
              updated++;
            }
          }
        } 
        // 3. Добавление нового
        else {
          if (state.mode == ImportMode.updateOnly) {
            skipped++;
            continue;
          }
          await db.insertProduct(p);
          added++;
          existingNamesSet.add(p.name.trim().toLowerCase());
        }
      }
    });

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