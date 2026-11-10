// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../models/product.dart';
import 'dart:io';
import 'dart:typed_data';
import '../models/order.dart';

// ============================================================
// Структуры данных
// ============================================================

class SheetAnalysis {
  final String sheetName;
  final String format; // 'price' | 'catalog'
  final List<String> headerLabels; // заголовки шапки
  final Map<String, List<int>> foundColumns; // поле -> индексы колонок
  final List<dynamic> dataRows; // строки ПОСЛЕ шапки
  String? manualCategory; // значение, введённое пользователем вручную
  final List<String> missingRequired;
  final bool hasRequired;
  final bool hasCategoryColumn;
  final bool hasCategoryInSeparators;

  SheetAnalysis({
    required this.sheetName,
    required this.format,
    required this.headerLabels,
    required this.foundColumns,
    required this.dataRows,
    this.manualCategory,
    required this.missingRequired,
    required this.hasRequired,
    required this.hasCategoryColumn,
    required this.hasCategoryInSeparators,
  });

  bool get hasDuplicates => foundColumns.values.any((v) => v.length > 1);

  bool get hasAnyCategorySource =>
      hasCategoryColumn || hasCategoryInSeparators || manualCategory != null;
}

class SheetStats {
  int totalRows = 0;
  int accepted = 0;
  int skipped = 0;
  int separatorsFound = 0;
  int emptyOrNoNumberRows = 0;
  List<Map<String, dynamic>> skippedDetails = [];
  Map<String, int> columnNonEmpty = {};
}

class SheetRejection {
  final String sheetName;
  final String reason;
  SheetRejection(this.sheetName, this.reason);
}
// ============================================================

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  // Ключевые слова для поиска колонок по корням слов
  static const Map<String, List<String>> fieldKeywords = {
    'name': ['препарат', 'название'],
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

  // Канонический вид известных категорий
  static const Map<String, String> typeVariants = {
    'ГЕРБИЦИДЫ': 'Гербициды',
    'ГЕРБЕЦИДЫ': 'Гербициды',
    'ИНСЕКТИЦИДЫ': 'Инсектициды',
    'ФУНГИЦИДЫ': 'Фунгициды',
    'ДЕСИКАНТЫ': 'Десиканты',
    'ПРОТРАВИТЕЛИ': 'Протравители',
    'ФУМИГАНТЫ': 'Фумиганты',
    'СПЕЦПРЕПАРАТЫ': 'Спецпрепараты',
    'РОДЕНТИЦИДЫ': 'Родентициды',
    'МИКРОУДОБРЕНИЯ': 'Микроудобрения', 
    'УДОБРЕНИЯ': 'Удобрения',           
  };

  // Корни для нечёткого распознавания категории
  static const List<String> _categoryRoots = [
    'гербицид',
    'гербецид',
    'инсектицид',
    'фунгицид',
    'десикант',
    'протравител',
    'фумигант',
    'спецпрепарат',
    'родентицид',
  ];

  // ---------- Безопасное чтение ячейки ----------
  static String _safeCellText(dynamic cell) {
    if (cell == null) return '';
    try {
      final dynamic v = cell.value;
      if (v == null) return '';
      return v.toString().trim();
    } catch (_) {
      return '';
    }
  }

  // ---------- "1.0" -> "1" ----------
  static String _normalizeNumber(String s) {
    if (s.endsWith('.0')) return s.substring(0, s.length - 2);
    return s;
  }

  // ---------- Распознавание категории в строке ----------
  static String? _matchCategoryWord(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final upper = trimmed.toUpperCase();

    // 1. Точное совпадение
    if (typeVariants.containsKey(upper)) return typeVariants[upper];

    // 2. Нечёткое совпадение по корню
    final lower = trimmed.toLowerCase();
    for (final root in _categoryRoots) {
      if (lower.contains(root)) {
        for (final canonical in typeVariants.values) {
          if (canonical.toLowerCase().contains(root)) return canonical;
        }
      }
    }
    return null;
  }

  // ---------- Определение строки-разделителя ----------
  // Разделитель = в первой непустой ячейке стоит только слово категории.
  static String? _detectSeparator(List<dynamic> row) {
    if (row.isEmpty) return null;
    String first = '';
    for (final c in row) {
      final t = _safeCellText(c);
      if (t.isNotEmpty) {
        first = t;
        break;
      }
    }
    if (first.isEmpty) return null;
    return _matchCategoryWord(first);
  }

    // ---------- Утилита для проверки текстовых цен ----------
  static bool _isTextPrice(String s) {
    final lower = s.toLowerCase();
    const textMarkers = [
      'по запросу', 'уточняйте', 'нет', 'звоните', 
      'договорная', 'под заказ', 'запрашивайте'
    ];
    for (final m in textMarkers) {
      if (lower.contains(m)) return true;
    }
    // Если в строке нет ни одной цифры, это тоже просто текст (например, "бесплатно")
    return !RegExp(r'\d').hasMatch(s);
  }
  // ---------- Утилита для парсинга чисел (исключает даты) ----------
  static double? _parseNumericValue(String raw) {
    if (raw.isEmpty) return null;
    
    // Убираем все пробелы и меняем запятую на точку
    final cleaned = raw.replaceAll(RegExp(r'\s+'), '').replaceAll(',', '.');
    
    // Регулярка пропускает только целые или десятичные числа (например, 100, 1.5, -2.5).
    // Даты (содержащие дефисы или слэши) и прочий текст сюда не пройдут.
    if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(cleaned)) {
      return double.tryParse(cleaned);
    }
    return null;
  }

  // --------------- Метод экспорта заказов ----------
  Future<void> _exportOrders(BuildContext context) async {
    final orders = await DatabaseHelper.instance.getAllOrders();
    if (orders.isEmpty) {
      _showMessage(context, 'В базе нет заказов для экспорта');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Экспорт заказов'),
        content: const Text('Будет создан Excel-файл с двумя листами:\n'
            '1. «Заказы» (общая информация)\n'
            '2. «Позиции» (список препаратов в заказах).\n\nПродолжить?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Экспортировать')),
        ],
      ),
    );

    if (confirm != true) return;

    showDialog(context: context, barrierDismissible: false, builder: (ctx) => const AlertDialog(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text('Генерация файла...')])));

    try {
      final excel = Excel.createExcel();
      
      // --- Лист 1: Заказы ---
      final sheetOrders = excel['Заказы'];
      sheetOrders.appendRow([
        TextCellValue('ID заказа'), TextCellValue('Дата'), TextCellValue('Клиент'),
        TextCellValue('Статус'), TextCellValue('Примечание'), TextCellValue('Итоговая сумма')
      ]);

      // --- Лист 2: Позиции ---
      final sheetItems = excel['Позиции'];
      sheetItems.appendRow([
        TextCellValue('ID заказа'), TextCellValue('ID Препарата'), TextCellValue('Наименование'),
        TextCellValue('Цена (базовая)'), TextCellValue('Скидка %'), TextCellValue('Норма расхода'),
        TextCellValue('Площадь, га'), TextCellValue('Ед. изм.'), TextCellValue('Стоимость позиции')
      ]);

      if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

      for (var order in orders) {
        final dateStr = '${order.orderDate.day}.${order.orderDate.month}.${order.orderDate.year}';
        
        // Пишем в лист Заказов
        sheetOrders.appendRow([
          IntCellValue(order.id!),
          TextCellValue(dateStr),
          TextCellValue(order.clientName),
          TextCellValue(order.status),
          TextCellValue(order.notes ?? ''),
          DoubleCellValue(order.totalAmount),
        ]);

        // Пишем в лист Позиций
        for (var item in order.items) {
          sheetItems.appendRow([
            IntCellValue(order.id!),
            item.productId != null ? IntCellValue(item.productId!) : TextCellValue(''),
            TextCellValue(item.productName),
            DoubleCellValue(item.basePrice),
            DoubleCellValue(item.discountPercent),
            DoubleCellValue(item.rate),
            DoubleCellValue(item.area),
            TextCellValue(item.packageUnit),
            DoubleCellValue(item.totalPrice),
          ]);
        }
      }

      final bytes = excel.save();
      if (bytes == null) throw Exception('Ошибка генерации');

      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

      final now = DateTime.now();
      final fileName = 'orders_backup_${now.year}-${now.month}-${now.day}.xlsx';

      final Uri? outputUri = await FilePicker.saveFile(
        dialogTitle: 'Сохранить бэкап заказов',
        fileName: fileName,
        bytes: Uint8List.fromList(bytes),
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (outputUri != null && context.mounted) {
        _showMessage(context, 'Заказы успешно экспортированы!', isSuccess: true);
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) _showMessage(context, 'Ошибка: $e');
    }
  }

  // --------------- Метод импорта  заказов  ----------
  Future<void> _importOrders(BuildContext context) async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx']);
      if (result == null) return;
      
      final bytes = await result.first.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final allSheetNames = excel.tables.keys.toList();

      if (allSheetNames.isEmpty) {
        _showMessage(context, 'Файл пуст');
        return;
      }

      // 1. СОПОСТАВЛЕНИЕ ЛИСТОВ
      final mapping = await _showOrderSheetMappingDialog(context, allSheetNames);
      if (mapping == null) return;

      final ordersSheetName = mapping['orders'];
      final itemsSheetName = mapping['items'];

      if (ordersSheetName == null && itemsSheetName == null) {
        _showMessage(context, 'Не выбрано ни одного листа для импорта');
        return;
      }

      // 2. ПАРСИНГ ЗАКАЗОВ (Лист 1)
      List<Order> parsedOrders = [];
      List<String> parseErrors = [];

      if (ordersSheetName != null) {
        final sheet = excel.tables[ordersSheetName]!;
        int headerRow = _findHeaderRow(sheet, [
          ['id', 'номер'], 
          ['клиент', 'заказчик', 'контрагент']
        ]);
        if (headerRow == -1) {
          _showMessage(context, 'Не найдены обязательные колонки в листе Заказы (ID, Клиент)');
          return;
        }

        final headers = sheet.rows[headerRow].map((c) => _safeCellText(c).toLowerCase()).toList();
        int idIdx = _findCol(headers, ['id', 'номер']);
        int clientIdx = _findCol(headers, ['клиент', 'заказчик']);
        int dateIdx = _findCol(headers, ['дата']);
        int statusIdx = _findCol(headers, ['статус']);
        int notesIdx = _findCol(headers, ['примечан', 'коммент']);

        for (int i = headerRow + 1; i < sheet.rows.length; i++) {
          final row = sheet.rows[i];
          if (row.isEmpty) continue;
          
          final idStr = _safeCellText(row[idIdx]);
          final client = _safeCellText(row[clientIdx]);
          
          if (idStr.isEmpty || client.isEmpty) {
            parseErrors.add('Заказы, строка ${i+1}: пропущен ID или Клиент');
            continue;
          }

          final id = int.tryParse(idStr);
          if (id == null) {
            parseErrors.add('Заказы, строка ${i+1}: некорректный ID ($idStr)');
            continue;
          }

          DateTime date = DateTime.now();
          if (dateIdx != -1) {
            final dStr = _safeCellText(row[dateIdx]);
            try { date = DateTime.parse(dStr); } catch(_) {}
          }

          parsedOrders.add(Order(
            id: id, clientName: client, orderDate: date, items: [],
            status: statusIdx != -1 ? _safeCellText(row[statusIdx]) : 'Новый',
            notes: notesIdx != -1 ? _safeCellText(row[notesIdx]) : null,
          ));
        }
      }

      // 3. ПАРСИНГ ПОЗИЦИЙ (Лист 2)
      if (itemsSheetName != null) {
        final sheet = excel.tables[itemsSheetName]!;
        int headerRow = _findHeaderRow(sheet, [
          ['id заказа', 'заказ'], 
          ['наименование', 'название', 'препарат']
        ]);
        if (headerRow == -1) {
          _showMessage(context, 'Не найдены обязательные колонки в листе Позиции (ID заказа, Наименование)');
          return;
        }

        final headers = sheet.rows[headerRow].map((c) => _safeCellText(c).toLowerCase()).toList();
        int orderIdIdx = _findCol(headers, ['id заказа', 'заказ']);
        int prodIdIdx = _findCol(headers, ['id препарата', 'id товара']);
        int nameIdx = _findCol(headers, ['наименование', 'название', 'препарат']);
        int priceIdx = _findCol(headers, ['цена']);
        int discIdx = _findCol(headers, ['скидк']);
        int rateIdx = _findCol(headers, ['норм']);
        int areaIdx = _findCol(headers, ['площад']);
        int unitIdx = _findCol(headers, ['ед', 'измер']);

        for (int i = headerRow + 1; i < sheet.rows.length; i++) {
          final row = sheet.rows[i];
          if (row.isEmpty) continue;

          final orderIdStr = _safeCellText(row[orderIdIdx]);
          final name = _safeCellText(row[nameIdx]);

          if (orderIdStr.isEmpty || name.isEmpty) {
             parseErrors.add('Позиции, строка ${i+1}: пропущен ID заказа или Наименование');
             continue;
          }

          final orderId = int.tryParse(orderIdStr);
          if (orderId == null) continue;

          // Ищем заказ в спарсенных или в БД
          Order? targetOrder = parsedOrders.where((o) => o.id == orderId).firstOrNull;
          
          int? prodId;
          if (prodIdIdx != -1) {
            prodId = int.tryParse(_safeCellText(row[prodIdIdx]));
          }

          final item = OrderItem(
            productId: prodId,
            productName: name,
            basePrice: priceIdx != -1 ? (double.tryParse(_safeCellText(row[priceIdx]).replaceAll(',', '.')) ?? 0) : 0,
            discountPercent: discIdx != -1 ? (double.tryParse(_safeCellText(row[discIdx]).replaceAll(',', '.')) ?? 0) : 0,
            rate: rateIdx != -1 ? (double.tryParse(_safeCellText(row[rateIdx]).replaceAll(',', '.')) ?? 0) : 1,
            area: areaIdx != -1 ? (double.tryParse(_safeCellText(row[areaIdx]).replaceAll(',', '.')) ?? 0) : 1,
            packageUnit: unitIdx != -1 ? _safeCellText(row[unitIdx]) : 'л',
          );

          if (targetOrder != null) {
            targetOrder.items.add(item);
          } else {
            // Если импортируем только позиции, сохраняем их во временный список
            parseErrors.add('Позиции, строка ${i+1}: Заказ №$orderId не найден в файле (будет попытка привязки к БД)');
            // Мы можем добавить логику сохранения во временный массив для привязки к БД позже.
          }
        }
      }

      if (parsedOrders.isEmpty && itemsSheetName == null) {
        _showMessage(context, 'Не найдено валидных заказов для импорта');
        return;
      }

      // 4. ВЫБОР РЕЖИМА ИМПОРТА
      final mode = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Режим импорта'),
          content: Text('Найдено заказов для импорта: ${parsedOrders.length}.\nОшибок при чтении: ${parseErrors.length}.\n\nКак применить данные?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'add'), child: const Text('Только новые')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'update'), child: const Text('Обновить и добавить')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, 'replace'), child: const Text('Заменить всё')),
          ],
        ),
      );

      if (mode == null || mode == 'cancel') return;

      // 5. СОХРАНЕНИЕ В БД
      showDialog(context: context, barrierDismissible: false, builder: (ctx) => const AlertDialog(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text('Сохранение данных...')])));

      final db = DatabaseHelper.instance;
      
      if (mode == 'replace') {
        await db.deleteAllOrders();
      }

      final existingIds = await db.getAllOrderIds();
      final productsMap = await db.getProductsIdMap();
      
      int added = 0, updated = 0;

      for (var order in parsedOrders) {
        // Разрешаем препараты (привязка по ID или создание заглушки)
        for (int i = 0; i < order.items.length; i++) {
          var item = order.items[i];
          int? resolvedId = item.productId;

          // Если ID есть, но такого препарата нет в БД -> сбрасываем ID
          if (resolvedId != null && !productsMap.containsKey(resolvedId)) {
            resolvedId = null;
          }

          // Если ID нет, ищем по имени
          if (resolvedId == null) {
            final existing = productsMap.values.where((p) => p.name.toLowerCase() == item.productName.toLowerCase()).firstOrNull;
            if (existing != null) {
              resolvedId = existing.id;
            } else {
              // Создаем заглушку
              resolvedId = await db.createStubProduct(item.productName);
              productsMap[resolvedId] = Product(id: resolvedId, name: item.productName, category: 'Импортированные (без категории)');
            }
          }
          
          // Обновляем ID в объекте позиции
          order.items[i] = item.copyWith(productId: resolvedId);
        }

        // Сохраняем заказ
        if (existingIds.contains(order.id)) {
          if (mode == 'update') {
            await db.updateOrder(order);
            updated++;
          }
        } else {
          await db.insertOrderWithId(order);
          added++;
        }
      }

      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      
      DatabaseHelper.dbUpdateTrigger.value++; // Обновляем UI

      // 6. ОТЧЕТ
      String report = 'Импорт завершен.\nДобавлено: $added\nОбновлено: $updated\n';
      if (parseErrors.isNotEmpty) {
        report += '\nПропущено/Ошибки: ${parseErrors.length}';
      }

      _showMessage(context, report, isSuccess: true);

    } catch (e, st) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      debugPrint('Order import error: $e\n$st');
      if (context.mounted) _showMessage(context, 'Ошибка импорта заказов: $e');
    }
  }

  // --- Вспомогательные методы для импорта ---
  int _findHeaderRow(Sheet sheet, List<List<String>> keywordGroups) {
    for (int i = 0; i < sheet.rows.length && i < 20; i++) {
      final row = sheet.rows[i];
      if (row.isEmpty) continue;
      final rowStr = row.map((c) => _safeCellText(c).toLowerCase()).join(' ');
      
      bool allGroupsFound = true;
      for (var group in keywordGroups) {
        bool groupFound = false;
        for (var kw in group) {
          if (rowStr.contains(kw)) {
            groupFound = true;
            break;
          }
        }
        if (!groupFound) { 
          allGroupsFound = false; 
          break; 
        }
      }
      if (allGroupsFound) return i;
    }
    return -1;
  }

  int _findCol(List<String> headers, List<String> keywords) {
    for (int i = 0; i < headers.length; i++) {
      for (var kw in keywords) {
        if (headers[i].contains(kw)) return i;
      }
    }
    return -1;
  }

  Future<Map<String, String?>?> _showOrderSheetMappingDialog(BuildContext context, List<String> sheets) async {
    String? ordersSheet = sheets.where((s) => s.toLowerCase().contains('заказ')).firstOrNull;
    String? itemsSheet = sheets.where((s) => s.toLowerCase().contains('позиц') || s.toLowerCase().contains('препарат')).firstOrNull;

    return showDialog<Map<String, String?>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Сопоставление листов'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Укажите, какой лист содержит какую информацию:'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Лист с Заказами (Шапки)'),
                value: ordersSheet,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Нет')),
                  ...sheets.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                ],
                onChanged: (val) => setState(() => ordersSheet = val),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Лист с Позициями (Препараты)'),
                value: itemsSheet,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Нет')),
                  ...sheets.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                ],
                onChanged: (val) => setState(() => itemsSheet = val),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () {
                if (ordersSheet == null && itemsSheet == null) return;
                Navigator.pop(ctx, {'orders': ordersSheet, 'items': itemsSheet});
              }, 
              child: const Text('Импортировать')
            ),
          ],
        ),
      ),
    );
  }

  // ---------- UI: Виджет диалога прогресса ----------
  Widget _buildProgressDialog(
      BuildContext context, ValueNotifier<String> progressNotifier, VoidCallback onCancel) {
    return AlertDialog(
      title: const Text('Импорт данных'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          ValueListenableBuilder<String>(
            valueListenable: progressNotifier,
            builder: (context, value, child) {
              return Text(
                value,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              );
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: const Text('Отмена', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }

  // ============================================================
  // ГЛАВНЫЙ МЕТОД ИМПОРТА
  // ============================================================
  Future<void> _importFromExcel(BuildContext context) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );
      if (result == null || result.isEmpty) {
        _showMessage(context, 'Файл не выбран');
        return;
      }

      final bytes = await result.first.readAsBytes();
      final excel = Excel.decodeBytes(bytes);

      final sheetNames = excel.tables.keys
          .where((n) => !n.startsWith('_'))
          .toList();

      if (sheetNames.isEmpty) {
        _showMessage(context, 'Файл не содержит листов с данными');
        return;
      }

      final selected = await _showSheetSelectionDialog(context, sheetNames);
      if (selected == null || selected.isEmpty) return;

      // ---------- Анализ листов ----------
      final analyses = <SheetAnalysis>[];
      final rejectedAtAnalysis = <SheetRejection>[];
      for (final name in selected) {
        final sheet = excel.tables[name];
        if (sheet == null) {
          rejectedAtAnalysis
              .add(SheetRejection(name, 'лист отсутствует в файле'));
          continue;
        }
        final a = _analyzeSheet(sheet, name, rejectedAtAnalysis);
        if (a != null) analyses.add(a);
      }

      if (analyses.isEmpty) {
        final buf = StringBuffer();
        buf.writeln('Не удалось распознать ни один из выбранных листов.\n');
        if (rejectedAtAnalysis.isNotEmpty) {
          buf.writeln('Причины:');
          for (final r in rejectedAtAnalysis) {
            buf.writeln('  • "${r.sheetName}" — ${r.reason}');
          }
        }
        _showMessage(context, buf.toString());
        return;
      }

      // ---------- Отчёт-анализ ----------
      // ---------- Разделяем на валидные и невалидные ----------
      final validAnalyses = analyses.where((a) => a.hasRequired).toList();
      final invalidAnalyses = analyses.where((a) => !a.hasRequired).toList();

      /// Список листов, которые НЕ будут импортированы:
      // сюда попадут невалидные + те, что пользователь отбросил сам
      final List<SheetAnalysis> rejectedSheets = [];
      final List<SheetRejection> rejectedReasons = [];
      for (final r in rejectedAtAnalysis) {
        rejectedReasons.add(r);
      }

      // Случай 1: все листы невалидны — прерываем импорт
      if (validAnalyses.isEmpty) {
        final buf = StringBuffer();
        buf.writeln('Ни один лист не может быть импортирован.\n');
        buf.writeln('Листы с пропущенными обязательными полями:');
        for (final a in invalidAnalyses) {
          buf.writeln(
              '  • "${a.sheetName}": ${a.missingRequired.join(', ')}');
        }
        _showMessage(context, buf.toString());
        return;
      }

      // Случай 2: есть и валидные, и невалидные — спрашиваем пользователя
      if (invalidAnalyses.isNotEmpty) {
        final proceed = await _showPartialImportDialog(
          context,
          invalidAnalyses,
          validAnalyses,
        );
        if (proceed != true) {
          _showMessage(context, 'Импорт отменён пользователем');
          return;
        }
        // Пользователь выбрал «Продолжить с пригодными» — запоминаем отброшенные
        rejectedSheets.addAll(invalidAnalyses);
        for (final a in invalidAnalyses) {
          rejectedReasons.add(SheetRejection(
            a.sheetName,
            a.missingRequired.isNotEmpty
                ? 'пропущены: ${a.missingRequired.join(', ')}'
                : 'непригодны к импорту',
          ));
        }
      }

      // ---------- Дубли колонок ----------
      for (final a in validAnalyses) {
        if (a.hasDuplicates) {
          final chosen = await _showColumnSelectionDialog(context, a);
          if (chosen == null) {
            _showMessage(context, 'Импорт отменён пользователем');
            return;
          }
          for (final e in chosen.entries) {
            a.foundColumns[e.key] = [e.value];
          }
        }
      }

      // ---------- Ручной ввод категории, если её нигде нет ----------
      for (final a in validAnalyses) {
        if (!a.hasAnyCategorySource) {
          final cat = await _showManualCategoryDialog(context, a.sheetName);
          if (cat == null) {
            _showMessage(context,
                'Импорт отменён: не введена категория для "${a.sheetName}"');
            return;
          }
          a.manualCategory = cat;
        }
      }

            // ---------- Парсинг ----------
      final allProducts = <Product>[];
      final allStats = <String, SheetStats>{};

      // Считаем общее количество строк
      final totalRowsToParse = validAnalyses.fold<int>(0, (sum, a) => sum + a.dataRows.length);
      final showProgress = totalRowsToParse > 150;

      final progressNotifier = ValueNotifier<String>('Подготовка к парсингу...');
      bool isCancelled = false; // Флаг отмены
      bool isProgressDialogOpen = false;

      if (showProgress) {
        isProgressDialogOpen = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => _buildProgressDialog(ctx, progressNotifier, () {
            // Коллбэк нажатия на «Отмена»
            isCancelled = true;
            Navigator.of(ctx).pop();
          }),
        );
      }

      try {
        for (final a in validAnalyses) {
          if (isCancelled) break; // Если нажали отмену, выходим

          final stats = SheetStats();
          final products = await _parseSheet(
            a,
            stats,
            progress: showProgress ? progressNotifier : null,
            isCancelled: () => isCancelled,
          );
          
          if (isCancelled) break; // Проверяем после завершения листа

          allProducts.addAll(products);
          allStats[a.sheetName] = stats;
        }
      } finally {
        if (isProgressDialogOpen) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      }

      if (isCancelled) {
        _showMessage(context, 'Импорт отменён пользователем');
        return;
      }

            // ---------- Проверка дубликатов в БД ----------
      final existingNames =
          await DatabaseHelper.instance.getExistingProductNames();

      final duplicates = <Product>[];
      final uniqueProducts = <Product>[];
      for (final p in allProducts) {
        final key = p.name.trim().toLowerCase();
        if (existingNames.contains(key)) {
          duplicates.add(p);
        } else {
          uniqueProducts.add(p);
        }
      }

      // Переменные для итогового отчета
      int addedCount = 0;
      int updatedCount = 0;
      int skippedDuplicatesCount = 0;
      int totalParsed = allProducts.length;

      if (duplicates.isNotEmpty) {
        final action = await _showDuplicatesDialog(
          context,
          duplicates,
          uniqueProducts.length,
        );

        if (action == null || action == 'cancel') {
          _showMessage(context, 'Импорт отменён пользователем');
          return;
        }

        if (action == 'skip') {
          skippedDuplicatesCount = duplicates.length;
          allProducts
            ..clear()
            ..addAll(uniqueProducts);
        } else if (action == 'update_only') {
          updatedCount = duplicates.length;
          allProducts.clear(); // Ничего не добавляем, только обновляем
        } else if (action == 'update_and_add') {
          updatedCount = duplicates.length;
          allProducts
            ..clear()
            ..addAll(uniqueProducts);
        }

        if (allProducts.isEmpty && action == 'skip') {
          _showMessage(
            context,
            'Все записи уже есть в базе данных — нечего импортировать',
          );
          return;
        }
      }

      // ---------- Итоговый отчёт и вставка ----------
      if (allProducts.isEmpty && updatedCount == 0) {
        await _showImportReportDialog(
          context,
          allStats,
          totalParsed: 0,
          addedCount: 0,
          updatedCount: 0,
          skippedDuplicatesCount: 0,
          dryRun: true,
          rejectedSheets: rejectedSheets,
          rejectedReasons: rejectedReasons,
        );
        _showMessage(context, 'Не найдено корректных записей для импорта');
        return;
      }

      final confirmed = await _showImportReportDialog(
        context,
        allStats,
        totalParsed: totalParsed,
        addedCount: allProducts.length,
        updatedCount: updatedCount,
        skippedDuplicatesCount: skippedDuplicatesCount,
        rejectedSheets: rejectedSheets,
        rejectedReasons: rejectedReasons,
      );

      if (confirmed == true) {
        // ВАЖНО: Делаем изменения в БД только после финального подтверждения!
        if (updatedCount > 0) {
          await DatabaseHelper.instance.updateProducts(duplicates);
        }
        if (allProducts.isNotEmpty) {
          await DatabaseHelper.instance.insertProducts(allProducts);
          addedCount = allProducts.length;
        }
        DatabaseHelper.dbUpdateTrigger.value++; // <-- ТРИГГЕР (Импорт)
        String msg = 'Импорт завершён. ';
        if (addedCount > 0) msg += 'Добавлено: $addedCount. ';
        if (updatedCount > 0) msg += 'Обновлено: $updatedCount. ';
        if (skippedDuplicatesCount > 0) msg += 'Пропущено дублей: $skippedDuplicatesCount.';
        
        _showMessage(context, msg.trim(), isSuccess: true);
      } else {
        _showMessage(context, 'Импорт отменён');
      }
    } catch (e, st) {
      
      debugPrint('=== Import error ===');
      debugPrint('Type: ${e.runtimeType}');
      debugPrint('Message: $e');
      debugPrint('Stack:\n$st');
      _showMessage(context, 'Ошибка импорта: $e');
    }
  }

  // ============================================================
  // АНАЛИЗ ОДНОГО ЛИСТА
  // ============================================================
  SheetAnalysis? _analyzeSheet(
    Sheet sheet,
    String sheetName,
    List<SheetRejection> rejections,
  ) {
    debugPrint('--- Analyze sheet "$sheetName" ---');
    debugPrint('  total sheet.rows = ${sheet.rows.length}');

    final format = _detectFormat(sheet);
    debugPrint('  format = $format');
    if (format == null) {
      rejections.add(SheetRejection(
        sheetName,
        'не распознан формат (нет ни шапки «№ п/п + Препараты», '
        'ни колонки «Тип»)',
      ));
      return null;
    }

    // ---------- Поиск строки шапки ----------
    int headerIdx = -1;
    for (int i = 0; i < sheet.rows.length && i < 50; i++) {
      final row = sheet.rows[i];
      if (row.isEmpty) continue;

      if (format == 'price') {
        // Ищем строку, где есть колонка с названием препарата
        bool hasNameCol = false;
        for (final c in row) {
          final val = _safeCellText(c).toLowerCase();
          if (val.contains('препарат') || val.contains('название') || val.contains('наименование')) {
            hasNameCol = true;
            break;
          }
        }
        if (hasNameCol) {
          headerIdx = i;
          break;
        }
      } else {
        // catalog
        final first = _safeCellText(row[0]);
        if (first.toLowerCase() == 'название') {
          headerIdx = i;
          break;
        }
      }
    }


    debugPrint('  headerIdx = $headerIdx');
    if (headerIdx == -1) {
      rejections.add(SheetRejection(
        sheetName,
        format == 'price'
            ? 'не найдена строка заголовка «№ п/п … Препараты»'
            : 'не найдена строка заголовка с «Название» в первой колонке',
      ));
      return null;
    }

    // ---------- Шапка ----------
    final headerRow = sheet.rows[headerIdx];
    final headerLabels = headerRow.map((c) => _safeCellText(c)).toList();
    debugPrint('  headerLabels = $headerLabels');

    // ---------- Данные после шапки (объявляем ЗДЕСЬ!) ----------
    final List<dynamic> dataRows = sheet.rows.sublist(headerIdx + 1);

    // ---------- Поиск колонок по ключевым словам ----------
    final foundColumns = <String, List<int>>{};
    for (final entry in fieldKeywords.entries) {
      final field = entry.key;
      final keywords = entry.value;
      final indices = <int>[];
      for (int i = 0; i < headerRow.length; i++) {
        final val = _safeCellText(headerRow[i]);
        if (val.isEmpty) continue;
        final lower = val.toLowerCase();
        for (final kw in keywords) {
          if (lower.contains(kw)) {
            indices.add(i);
            break;
          }
        }
      }
      if (indices.isNotEmpty) foundColumns[field] = indices;
    }
    debugPrint('  foundColumns = $foundColumns');

    // ---------- Категория ----------
    final hasName = foundColumns['name']?.isNotEmpty == true;
    final hasCategoryColumn = foundColumns['category']?.isNotEmpty == true;

    bool hasCategoryInSeparators = false;
    if (format == 'price' && !hasCategoryColumn) {
      for (final r in dataRows) {
        if (r.isEmpty) continue;
        if (_detectSeparator(r) != null) {
          hasCategoryInSeparators = true;
          break;
        }
      }
    }

    // ---------- Обязательные поля ----------
    final missingRequired = <String>[];
    if (!hasName) missingRequired.add('Название');

    final hasCategorySource =
        hasCategoryColumn || hasCategoryInSeparators;
    if (!hasCategorySource) missingRequired.add('Категория');

    // Лист пригоден, если есть колонка «name». Если у категории нет
    // ни колонки, ни разделителей — спросим пользователя вручную.
    final hasRequired = hasName;

    debugPrint('  hasName=$hasName, hasCategoryColumn=$hasCategoryColumn, '
        'sep=$hasCategoryInSeparators');

    return SheetAnalysis(
      sheetName: sheetName,
      format: format,
      headerLabels: headerLabels,
      foundColumns: foundColumns,
      dataRows: dataRows,
      manualCategory: null, // заполняется позже, если пользователь введёт
      missingRequired: missingRequired,
      hasRequired: hasRequired,
      hasCategoryColumn: hasCategoryColumn,
      hasCategoryInSeparators: hasCategoryInSeparators,
    );
  }

  // ============================================================
  // ОПРЕДЕЛЕНИЕ ФОРМАТА
  // ============================================================
  String? _detectFormat(Sheet sheet) {
    // 1. Сначала проверяем Каталог (есть колонка "Тип")
    for (int i = 0; i < sheet.rows.length && i < 20; i++) {
      final row = sheet.rows[i];
      if (row.isEmpty) continue;
      for (final c in row) {
        if (_safeCellText(c).toLowerCase() == 'тип') return 'catalog';
      }
    }
    
    // 2. Затем проверяем Прайс (есть колонка с названием)
    for (int i = 0; i < sheet.rows.length && i < 30; i++) {
      final row = sheet.rows[i];
      if (row.isEmpty) continue;
      for (final c in row) {
        final t = _safeCellText(c).toLowerCase();
        if (t.contains('препарат') || t.contains('название') || t.contains('наименование')) {
          return 'price';
        }
      }
    }
    return null;
  }

  // ============================================================
  // ПАРСИНГ ОДНОГО ЛИСТА
  // ============================================================
  Future<List<Product>> _parseSheet(
    SheetAnalysis a,
    SheetStats stats, {
    ValueNotifier<String>? progress,
    bool Function()? isCancelled, // Добавили функцию проверки
  }) async {
    debugPrint('--- Parse sheet "${a.sheetName}" ---');
    
    if (a.foundColumns['name']?.isEmpty ?? true) {
      return [];
    }

    int idx(Map<String, List<int>> m, String key) =>
        (m[key]?.isNotEmpty == true) ? m[key]!.first : -1;

    final nameIdx = idx(a.foundColumns, 'name');
    final categoryIdx = idx(a.foundColumns, 'category');
    final compositionIdx = idx(a.foundColumns, 'composition');
    final manufacturerIdx = idx(a.foundColumns, 'manufacturer');
    final packageIdx = idx(a.foundColumns, 'package');
    final rateIdx = idx(a.foundColumns, 'rate');
    final priceIdx = idx(a.foundColumns, 'price');
    final descriptionIdx = idx(a.foundColumns, 'description');
    final culturesIdx = idx(a.foundColumns, 'cultures');
    final diseasesIdx = idx(a.foundColumns, 'diseases');

    stats.columnNonEmpty = {
      'Название': 0,
      'Категория': 0,
      'Состав': 0,
      'Производитель': 0,
      'Упаковка': 0,
      'Норма расхода': 0,
      'Цена': 0,
    };

    final products = <Product>[];
    String currentCategory = a.manualCategory ?? '';

    for (int i = 0; i < a.dataRows.length; i++) {
      // Проверка на отмену каждые 20 строк
      if (i > 0 && i % 20 == 0) {
        if (isCancelled != null && isCancelled()) return []; // Экстренный выход
        
        if (progress != null) {
          progress.value = 'Обработка листа "${a.sheetName}":\n$i из ${a.dataRows.length} строк';
        }
        await Future.delayed(Duration.zero);
      }
      

      final row = a.dataRows[i];
      if (row.isEmpty) continue;

      String getCell(int i2) {
        if (i2 < 0 || i2 >= row.length) return '';
        return _safeCellText(row[i2]);
      }

      // ---------- Для прайса: разделитель и номер ----------
      if (a.format == 'price') {
        // 1. Проверяем строку на разделитель (например, "ГЕРБИЦИДЫ", "ИНСЕКТИЦИДЫ")
        final sep = _detectSeparator(row);
        if (sep != null) {
          currentCategory = sep;
          stats.separatorsFound++;
          continue; // Пропускаем саму строку разделителя
        }
        
        // Проверяем только, есть ли в строке хоть какие-то данные.
        // Это защитит от пустых строк в конце файла или между препаратами.
        bool isRowEmpty = true;
        for (final c in row) {
          if (_safeCellText(c).isNotEmpty) {
            isRowEmpty = false;
            break;
          }
        }
        
        if (isRowEmpty) {
          stats.emptyOrNoNumberRows++;
          continue; // Пропускаем полностью пустую строку
        }
      }

      // ---------- Данные ----------
      stats.totalRows++;

      final name = getCell(nameIdx);
      final category =
          categoryIdx != -1 ? getCell(categoryIdx) : currentCategory;
      final composition = getCell(compositionIdx);
      final manufacturer = getCell(manufacturerIdx);
      final package = getCell(packageIdx);
      final rate = getCell(rateIdx);
      final priceStr = getCell(priceIdx);
      final description = getCell(descriptionIdx);

      // Изменяем функцию, чтобы она возвращала List<String>
      List<String> normalizeTags(String input) {
        if (input.isEmpty) return [];
        return input.split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .map((e) => e[0].toUpperCase() + e.substring(1).toLowerCase())
            .toList(); // <-- Возвращаем список, а не строку
      }

      final cultures = normalizeTags(getCell(culturesIdx));
      final diseases = normalizeTags(getCell(diseasesIdx));

      void bump(String k) {
        stats.columnNonEmpty[k] = (stats.columnNonEmpty[k] ?? 0) + 1;
      }

      if (name.isNotEmpty) bump('Название');
      if (category.isNotEmpty) bump('Категория');
      if (composition.isNotEmpty) bump('Состав');
      if (manufacturer.isNotEmpty) bump('Производитель');
      if (package.isNotEmpty) bump('Упаковка');
      if (rate.isNotEmpty) bump('Норма расхода');
      if (priceStr.isNotEmpty) bump('Цена');

      // ---------- Валидация ----------
      if (name.isEmpty || category.isEmpty) {
        stats.skipped++;
        stats.skippedDetails.add({
          'row': i + 1,
          'name': name.isNotEmpty ? name : '(пусто)',
          'reason': name.isEmpty ? 'Нет названия' : 'Нет категории',
        });
        continue;
      }

      // ---------- Цена (Пункт 8) ----------
      double? price;
      if (priceStr.isNotEmpty) {
        price = _parseNumericValue(priceStr); // Пытаемся распарсить
        
        if (price == null) {
          // Если не распарсилось, проверяем, может это текст ("по запросу")
          if (_isTextPrice(priceStr)) {
            price = null; 
          } else {
            // Это не число и не текст (например, дата или "1500-2000")
            stats.skipped++;
            stats.skippedDetails.add({
              'row': i + 1,
              'name': name,
              'reason': 'Некорректная цена: "$priceStr"',
            });
            continue;
          }
        }
      }

      // ---------- Норма расхода (проверка на дату/мусор) ----------
      // Норму мы храним как String (т.к. бывают диапазоны "0,7-1,0"), 
      // но проверим, не является ли она датой
      if (rate.isNotEmpty) {
        // Если это похоже на дату (например, 2026-10-19 или 19.10.2026) — это ошибка
        if (RegExp(r'^\d{2,4}[\.\/-]\d{2}[\.\/-]\d{2,4}$').hasMatch(rate)) {
          stats.skipped++;
          stats.skippedDetails.add({
            'row': i + 1,
            'name': name,
            'reason': 'Норма расхода записана как дата: "$rate"',
          });
          continue;
        }
      }

      products.add(Product(
        name: name,
        category: category,
        composition: composition.isNotEmpty ? composition : null,
        manufacturer: manufacturer.isNotEmpty ? manufacturer : null,
        package: package.isNotEmpty ? package : null,
        consumptionRate: rate.isNotEmpty ? rate : null,
        price: price,
        description: description.isNotEmpty ? description : null,
        cultures: cultures, 
        diseases: diseases,
      ));
      stats.accepted++;
    }

    return products;
  }

  // ============================================================
  // ДИАЛОГИ
  // ============================================================

  // ---- 1. Выбор листов ----
  Future<List<String>?> _showSheetSelectionDialog(
      BuildContext context, List<String> sheetNames) async {
    final selected = <String, bool>{for (final n in sheetNames) n: false};
    String? errorText;

    return showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Выберите листы для импорта'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.maxFinite,
                height: 300,
                child: ListView(
                  children: sheetNames
                      .map((n) => CheckboxListTile(
                            title: Text(n),
                            value: selected[n] ?? false,
                            onChanged: (v) => setState(() {
                              selected[n] = v ?? false;
                              errorText = null;
                            }),
                          ))
                      .toList(),
                ),
              ),
              if (errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(errorText!,
                      style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
                final chosen = selected.entries
                    .where((e) => e.value)
                    .map((e) => e.key)
                    .toList();
                if (chosen.isEmpty) {
                  setState(
                      () => errorText = 'Выберите хотя бы один лист');
                  return;
                }
                Navigator.pop(ctx, chosen);
              },
              child: const Text('Далее'),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 2. Отчёт по анализу ----
  Future<bool?> _showAnalysisReportDialog(
    BuildContext context,
    List<SheetAnalysis> analyses,
    List<SheetRejection> rejectedAtAnalysis,
  ) async {
    // Считаем статистику
    final validSheets = analyses.where((a) => a.hasRequired).toList();
    final invalidSheets = analyses.where((a) => !a.hasRequired).toList();

    final totalCount = analyses.length + rejectedAtAnalysis.length;
    final validCount = validSheets.length;
    final invalidCount = invalidSheets.length + rejectedAtAnalysis.length;

    final buf = StringBuffer();
    // ---------- Сводка ----------
    buf.writeln('Всего выбрано листов: $totalCount');
    buf.writeln('✅ Пригодных к импорту: $validCount');
    buf.writeln('❌ Непригодных (будут пропущены): $invalidCount\n');

    // ---------- Валидные листы ----------
    if (validSheets.isNotEmpty) {
      buf.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      buf.writeln('✅ ПРИГОДНЫЕ ЛИСТЫ:');
      buf.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      
      for (final a in validSheets) {
        buf.writeln('📄 "${a.sheetName}"');
        buf.writeln(
            '  Формат: ${a.format == 'price' ? 'прайс-лист' : 'каталог'}');
        buf.writeln('  Строк данных (после шапки): ${a.dataRows.length}');

        if (a.foundColumns.isNotEmpty) {
          buf.writeln('  Найденные колонки:');
          a.foundColumns.forEach((f, idxs) {
            final labels = idxs
                .map((i) => i < a.headerLabels.length
                    ? a.headerLabels[i]
                    : '#${i + 1}')
                .join(', ');
            buf.writeln('    ${_getFieldLabel(f)}: $labels');
          });
        } else {
          buf.writeln('  ⚠️ Колонки не найдены');
        }

        if (a.hasCategoryColumn) {
          final catColIdx = a.foundColumns['category']!.first;
          final catLabel = catColIdx < a.headerLabels.length
              ? a.headerLabels[catColIdx]
              : 'колонка ${catColIdx + 1}';
          buf.writeln('  Категория: из колонки "$catLabel"');
        } else if (a.hasCategoryInSeparators) {
          buf.writeln('  Категория: из строк-разделителей внутри данных');
        } else {
          buf.writeln('  ⚠️ Категорию надо будет ввести вручную');
        }

        if (a.missingRequired.isNotEmpty) {
          buf.writeln('  ⚠️ Отсутствуют: ${a.missingRequired.join(', ')}');
        }
        buf.writeln();
      }
    }

    // ---------- Невалидные и отклоненные листы ----------
    if (invalidCount > 0) {
      buf.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      buf.writeln('❌ НЕПРИГОДНЫЕ ЛИСТЫ (будут пропущены):');
      buf.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

      // Листы, где нашли шапку, но нет обязательных колонок
      for (final a in invalidSheets) {
        buf.writeln('📄 "${a.sheetName}"');
        buf.writeln('  Формат: ${a.format == 'price' ? 'прайс-лист' : 'каталог'}');
        buf.writeln('  Причина: пропущены поля: ${a.missingRequired.join(', ')}');
        buf.writeln();
      }

      // Листы, где вообще не нашли шапку или формат
      for (final r in rejectedAtAnalysis) {
        buf.writeln('📄 "${r.sheetName}"');
        buf.writeln('  Причина: ${r.reason}');
        buf.writeln();
      }
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Анализ листов'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(buf.toString(), style: const TextStyle(fontSize: 13)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Продолжить'),
          ),
        ],
      ),
    );
  }


    // ---- 2.5. Диалог частичной обработки ----
  Future<bool?> _showPartialImportDialog(
    BuildContext context,
    List<SheetAnalysis> invalidSheets,
    List<SheetAnalysis> validSheets,
  ) async {
    final buf = StringBuffer();
    buf.writeln(
        'Некоторые листы не могут быть импортированы из-за отсутствия '
        'обязательных полей.\n');

    buf.writeln('❌ Листы с пропусками:');
    for (final a in invalidSheets) {
      buf.writeln('  • "${a.sheetName}" — ${a.missingRequired.join(', ')}');
    }

    buf.writeln();
    buf.writeln('✅ Листы, готовые к импорту:');
    for (final a in validSheets) {
      buf.writeln('  • "${a.sheetName}"');
    }

    buf.writeln();
    buf.writeln('Продолжить импорт только с пригодными листами? '
        'Непригодные будут проигнорированы.');

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Частичная обработка'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(buf.toString(),
                style: const TextStyle(fontSize: 13)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Прервать'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Продолжить с пригодными'),
          ),
        ],
      ),
    );
  }

    // ---- Диалог о дубликатах в БД ----
  Future<String?> _showDuplicatesDialog(
    BuildContext context,
    List<Product> duplicates,
    int uniqueCount,
  ) async {
    final buf = StringBuffer();
    buf.writeln('Найдено ${duplicates.length} препаратов, которые уже есть в базе.\n');
    buf.writeln('Новых препаратов: $uniqueCount.\n');
    buf.writeln('Как поступить с существующими?');
    
    if (duplicates.isNotEmpty) {
      buf.writeln('\nПримеры совпадений:');
      for (final p in duplicates.take(5)) {
        buf.writeln('  • "${p.name}" — категория: ${p.category}');
      }
      if (duplicates.length > 5) {
        buf.writeln('  ... и ещё ${duplicates.length - 5}');
      }
    }

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Дубликаты в базе'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(buf.toString(), style: const TextStyle(fontSize: 13)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'update_only'),
            child: const Text('Только обновление'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'skip'),
            child: const Text('Добавить новые'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'update_and_add'),
            child: const Text('Обновить и добавить'),
          ),
        ],
      ),
    );
  }

  // ---- 3. Выбор колонок при дублях ----
  Future<Map<String, int>?> _showColumnSelectionDialog(
      BuildContext context, SheetAnalysis a) async {
    final dupFields = <String, List<int>>{};
    a.foundColumns.forEach((f, idxs) {
      if (idxs.length > 1) dupFields[f] = idxs;
    });

    final selectedMap = <String, int>{};
    for (final e in dupFields.entries) {
      selectedMap[e.key] = e.value.first;
    }

    return showDialog<Map<String, int>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Выбор колонок: "${a.sheetName}"'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: dupFields.entries.map((e) {
                  final field = e.key;
                  final idxs = e.value;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: Text(_getFieldLabel(field),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                      ),
                      ...idxs.map((idx) => RadioListTile<int>(
                            value: idx,
                            groupValue: selectedMap[field],
                            onChanged: (v) => setState(
                                () => selectedMap[field] = v!),
                            title: Text(
                              (idx < a.headerLabels.length &&
                                      a.headerLabels[idx].isNotEmpty)
                                  ? a.headerLabels[idx]
                                  : 'Колонка ${idx + 1}',
                            ),
                          )),
                      const Divider(),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, selectedMap),
              child: const Text('Применить'),
            ),
          ],
        ),
      ),
    );
  }

    // ---- 4. Ручной ввод категории ----
  Future<String?> _showManualCategoryDialog(
      BuildContext context, String sheetName) async {
    final controller = TextEditingController();
    // Получаем уникальные названия категорий и сортируем их по алфавиту
    final knownCategories = typeVariants.values.toSet().toList()..sort();

    String? selectedValue;
    bool isCustom = false;
    String? errorText; // Для вывода ошибок валидации

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: Text('Категория для "$sheetName"'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'В файле не найдена колонка с категорией и строки-разделители. '
                    'Выберите категорию из списка или введите своё значение:',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: 'Категория',
                      border: const OutlineInputBorder(),
                      errorText: errorText, // Показываем ошибку прямо здесь
                    ),
                    value: selectedValue,
                    items: [
                      ...knownCategories.map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(c),
                          )),
                      const DropdownMenuItem(
                        value: '__other__',
                        child: Text('Другое (ввести вручную)...'),
                      ),
                    ],
                    onChanged: (val) {
                      setState(() {
                        selectedValue = val;
                        isCustom = (val == '__other__');
                        errorText = null; // Сбрасываем ошибку при изменении
                        if (isCustom) {
                          controller.clear();
                        }
                      });
                    },
                  ),
                  if (isCustom) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) {
                        if (errorText != null) {
                          setState(() => errorText = null);
                        }
                      },
                      onSubmitted: (_) => _handleSubmit(
                        ctx,
                        isCustom,
                        selectedValue,
                        controller,
                        (err) => setState(() => errorText = err),
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Своя категория',
                        hintText: 'Например, Регуляторы роста',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Отмена'),
              ),
              ElevatedButton(
                onPressed: () => _handleSubmit(
                  ctx,
                  isCustom,
                  selectedValue,
                  controller,
                  (err) => setState(() => errorText = err),
                ),
                child: const Text('ОК'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Вспомогательный метод для валидации и возврата результата
  void _handleSubmit(
    BuildContext ctx,
    bool isCustom,
    String? selectedValue,
    TextEditingController controller,
    void Function(String?) setError,
  ) {
    if (!isCustom) {
      if (selectedValue == null) {
        setError('Выберите категорию из списка');
        return;
      }
      Navigator.pop(ctx, selectedValue);
      return;
    }

    final rawText = controller.text.trim();

    // 1. Проверка на пустоту
    if (rawText.isEmpty) {
      setError('Введите название категории');
      return;
    }

    // 2. Проверка длины (например, не менее 3 символов)
    if (rawText.length < 3) {
      setError('Название категории слишком короткое');
      return;
    }

    // 3. Проверка на допустимые символы (только буквы, пробелы и дефисы)
    // Отсекаем строки, состоящие только из цифр или спецсимволов (типа "123" или "...")
    final hasLetters = RegExp(r'[а-яА-Яa-zA-Z]').hasMatch(rawText);
    if (!hasLetters) {
      setError('Название должно содержать буквы');
      return;
    }

    // 4. Нормализация и распознавание
    // Пытаемся сопоставить введенное значение с известными категориями
    // (сработает, если ввели "гербициды" с маленькой буквы или "гербециды" с опечаткой)
    String finalCategory = rawText;
    final matchedCategory = _matchCategoryWord(rawText);
    if (matchedCategory != null) {
      finalCategory = matchedCategory;
    } else {
      // Если это совершенно новое слово, делаем первую букву заглавной, остальные строчными
      // Например, "регуляторы РОСТА" -> "Регуляторы роста"
      finalCategory = rawText[0].toUpperCase() + 
                      rawText.substring(1).toLowerCase();
    }

    Navigator.pop(ctx, finalCategory);
  }

  // ---- 5. Итоговый отчёт ----
  Future<bool?> _showImportReportDialog(
    BuildContext context,
    Map<String, SheetStats> allStats, {
    required int totalParsed,
    required int addedCount,
    required int updatedCount,
    required int skippedDuplicatesCount,
    bool dryRun = false,
    List<SheetAnalysis> rejectedSheets = const [],
    List<SheetRejection> rejectedReasons = const [],
  }) async {
    final buf = StringBuffer();
    
    // Считаем общее количество ошибок по всем листам
    final totalErrors = allStats.values.fold<int>(0, (sum, s) => sum + s.skipped);

    // ---------- Сводка ----------
    buf.writeln('📊 ИТОГОВАЯ СТАТИСТИКА:');
    buf.writeln('Всего строк прошло валидацию: $totalParsed');
    
    if (addedCount > 0) {
      buf.writeln('✅ Будет добавлено новых: $addedCount');
    }
    if (updatedCount > 0) {
      buf.writeln('♻️ Будет обновлено существующих: $updatedCount');
    }
    if (skippedDuplicatesCount > 0) {
      buf.writeln('⏭️ Пропущено дубликатов: $skippedDuplicatesCount');
    }
    if (totalErrors > 0) {
      buf.writeln('❌ Пропущено из-за ошибок: $totalErrors');
    }
    buf.writeln();

    // ---------- Детализация по листам ----------
    buf.writeln('📋 ДЕТАЛИЗАЦИЯ ПО ЛИСТАМ:');
    for (final e in allStats.entries) {
      final s = e.value;
      if (s.totalRows == 0) continue; // Пропускаем пустые

      buf.writeln('📄 "${e.key}"');
      buf.writeln('  Обработано строк: ${s.totalRows}');
      buf.writeln('  Принято: ${s.accepted}');
      
      if (s.skipped > 0) {
        buf.writeln('  Пропущено (ошибки): ${s.skipped}');
        // Выводим первые 3 ошибки сразу
        for (final item in s.skippedDetails.take(3)) {
          buf.writeln('    - Строка ${item['row']}: "${item['name']}" — ${item['reason']}');
        }
      }
      buf.writeln();
    }

    // ---------- Отброшенные листы ----------
    if (rejectedReasons.isNotEmpty) {
      buf.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      buf.writeln('⚠️ Листы, которые НЕ будут импортированы:');
      for (final r in rejectedReasons) {
        buf.writeln('  • "${r.sheetName}" — ${r.reason}');
      }
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(dryRun ? 'Диагностика (нет данных)' : 'Результат импорта'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(buf.toString(), style: const TextStyle(fontSize: 13)),
          ),
        ),
        actions: [
          // Если ошибок больше 3, показываем кнопку "Детали"
          if (totalErrors > 3)
            TextButton(
              onPressed: () => _showAllErrorsDialog(context, allStats),
              child: Text('Все ошибки ($totalErrors)'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          if (!dryRun)
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Принять'),
            ),
        ],
      ),
    );
  }
  // ---- 6. Диалог со всеми ошибками ----
  Future<void> _showAllErrorsDialog(
      BuildContext context, Map<String, SheetStats> allStats) async {
    final buf = StringBuffer();
    
    for (final e in allStats.entries) {
      final s = e.value;
      if (s.skippedDetails.isEmpty) continue;

      buf.writeln('📄 Лист "${e.key}":');
      for (final item in s.skippedDetails) {
        buf.writeln('  • Строка ${item['row']}: "${item['name']}"');
        buf.writeln('    Причина: ${item['reason']}');
      }
      buf.writeln();
    }

    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Все ошибки импорта'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(buf.toString(), style: const TextStyle(fontSize: 13)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }


  // ---- Утилиты ----
  String _getFieldLabel(String field) {
    switch (field) {
      case 'name':  return 'Название';
      case 'category':  return 'Категория';
      case 'composition':  return 'Состав';
      case 'manufacturer':  return 'Производитель';
      case 'package':  return 'Упаковка';
      case 'rate':  return 'Норма расхода';
      case 'price':  return 'Цена';
      case 'description': return 'Описание';
      case 'cultures': return 'Культуры';
      case 'diseases': return 'Болезни';
      default:
        return field;
    }
  }

  void _showMessage(BuildContext context, String message,
      {bool isSuccess = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? Colors.green : Colors.red,
      ),
    );
  }

  // ============================================================
  // ВЫБОРОЧНОЕ ОБНОВЛЕНИЕ (ПО КОЛОНКАМ)
  // ============================================================
  Future<void> _importPartialUpdate(BuildContext context) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );
      if (result == null || result.isEmpty) return;

      final bytes = await result.first.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheetNames = excel.tables.keys.where((n) => !n.startsWith('_')).toList();
      if (sheetNames.isEmpty) return;

      final selectedSheets = await _showSheetSelectionDialog(context, sheetNames);
      if (selectedSheets == null || selectedSheets.isEmpty) return;

      // 1. Анализ листов
      final List<Map<String, dynamic>> rowsToUpdate = [];
      final Set<String> allFoundFields = {};
      final List<String> rejectedSheets = [];

      for (final sheetName in selectedSheets) {
        final sheet = excel.tables[sheetName];
        if (sheet == null) continue;

        int headerIdx = -1;
        for (int i = 0; i < sheet.rows.length && i < 50; i++) {
          final row = sheet.rows[i];
          if (row.isEmpty) continue;
          bool hasName = false;
          for (final c in row) {
            final text = _safeCellText(c).toLowerCase();
            if (text.contains('название') || text.contains('препарат') || text.contains('наименование')) {
              hasName = true;
              break;
            }
          }
          if (hasName) {
            headerIdx = i;
            break;
          }
        }
        
        if (headerIdx == -1) {
          rejectedSheets.add(sheetName);
          continue;
        }

        final headerRow = sheet.rows[headerIdx];
        final Map<String, int> colIndices = {};
        
        for (final entry in fieldKeywords.entries) {
          final field = entry.key;
          final keywords = entry.value;
          for (int i = 0; i < headerRow.length; i++) {
            final val = _safeCellText(headerRow[i]).toLowerCase();
            if (val.isEmpty) continue;
            for (final kw in keywords) {
              if (val.contains(kw)) {
                colIndices[field] = i;
                if (field != 'name') allFoundFields.add(field);
                break;
              }
            }
          }
        }

        if (!colIndices.containsKey('name')) {
          rejectedSheets.add(sheetName);
          continue;
        }

        final dataRows = sheet.rows.sublist(headerIdx + 1);
        for (final row in dataRows) {
          if (row.isEmpty) continue;
          final name = _safeCellText(row[colIndices['name']!]);
          if (name.isEmpty) continue;
          
          rowsToUpdate.add({
            'name': name,
            'rowData': row,
            'colIndices': Map<String, int>.from(colIndices),
          });
        }
      }

      // ПРОВЕРКА: Если нет колонок для обновления
      if (allFoundFields.isEmpty) {
        _showMessageDialog(
          context, 
          'Ошибка', 
          'В файле не найдено колонок для обновления (кроме наименования).\n\nЛисты без колонки "Наименование": ${rejectedSheets.join(', ')}'
        );
        return;
      }

      // 2. Диалог выбора колонок
      final selectedFields = await _showUpdateColumnsSelectionDialog(context, allFoundFields.toList());
      if (selectedFields == null || selectedFields.isEmpty) {
        _showMessage(context, 'Обновление отменено');
        return;
      }

      // 3. Формируем данные для проверки (БЕЗ обновления БД)
      int totalProcessed = 0;
      int notFoundCount = 0;
      final existingNames = await DatabaseHelper.instance.getExistingProductNames();
      final Map<String, Map<String, dynamic>> updatesMap = {}; 

      for (final item in rowsToUpdate) {
        final String name = item['name'];
        final List<dynamic> row = item['rowData'];
        final Map<String, int> colIndices = item['colIndices'];

        if (!existingNames.contains(name.trim().toLowerCase())) {
          notFoundCount++;
          continue;
        }

        final Map<String, dynamic> updateData = {};
        for (final field in selectedFields) {
          if (colIndices.containsKey(field)) {
            final idx = colIndices[field]!;
            final val = idx < row.length ? _safeCellText(row[idx]) : '';
            
            if (field == 'price') {
              updateData['price'] = _parseNumericValue(val);
            } else if (field == 'rate') {
              updateData['consumption_rate'] = val.isNotEmpty ? val : null;
            } else {
              updateData[field] = val.isNotEmpty ? val : null;
            }
          }
        }
        
        if (updateData.isNotEmpty) {
          updatesMap[name] = updateData;
          totalProcessed++;
        }
      }

      if (updatesMap.isEmpty) {
        _showMessage(context, 'Не найдено совпадений с текущей базой данных');
        return;
      }

      // 4. ПОКАЗЫВАЕМ ИТОГОВЫЙ ОТЧЕТ ПЕРЕД ОБНОВЛЕНИЕМ
      final confirmed = await _showPartialUpdateReportDialog(
        context, 
        totalProcessed, 
        notFoundCount, 
        selectedFields
      );

      // 5. ОБНОВЛЯЕМ ТОЛЬКО ЕСЛИ НАЖАТО "ПРИНЯТЬ"
      if (confirmed == true) {
        await DatabaseHelper.instance.batchUpdateProductsByField(updatesMap);
        DatabaseHelper.dbUpdateTrigger.value++; // <-- ТРИГГЕР (Выборочное обновление)
        _showMessage(
          context, 
          'Успешно обновлено $totalProcessed записей', 
          isSuccess: true
        );
      } else {
        _showMessage(context, 'Обновление отменено');
      }

    } catch (e, st) {
      debugPrint('Partial update error: $e\n$st');
      _showMessage(context, 'Ошибка обновления: $e');
    }
  }
  
  // Простой диалог для вывода ошибки (вместо SnackBar)
  void _showMessageDialog(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ОК'),
          ),
        ],
      ),
    );
  }

  // Диалог выбора колонок (без изменений)
  Future<List<String>?> _showUpdateColumnsSelectionDialog(
      BuildContext context, List<String> availableFields) async {
    final Map<String, bool> selected = {for (final f in availableFields) f: true};

    return showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Что обновить?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Выберите колонки, данные из которых нужно перезаписать в базе:'),
              const SizedBox(height: 8),
              ...availableFields.map((f) => CheckboxListTile(
                title: Text(_getFieldLabel(f)),
                value: selected[f] ?? false,
                onChanged: (val) {
                  setState(() => selected[f] = val ?? false);
                },
              )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
                final chosen = selected.entries.where((e) => e.value).map((e) => e.key).toList();
                if (chosen.isEmpty) return;
                Navigator.pop(ctx, chosen);
              },
              child: const Text('Далее'),
            ),
          ],
        ),
      ),
    );
  }

  // Диалог итогового отчета перед обновлением
  Future<bool?> _showPartialUpdateReportDialog(
    BuildContext context,
    int foundCount,
    int notFoundCount,
    List<String> selectedFields,
  ) async {
    final fieldsText = selectedFields.map((f) => _getFieldLabel(f)).join(', ');

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Результат проверки'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Колонки для обновления: $fieldsText\n'),
            Text('✅ Найдено в БД и будет обновлено: $foundCount'),
            Text('❌ Пропущено (нет в БД): $notFoundCount'),
            const SizedBox(height: 16),
            const Text('Применить изменения в базе данных?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Принять'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ОЧИСТКА БД (без изменений)
  // ============================================================
  Future<void> _clearDatabase(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Подтверждение'),
        content: const Text('Вы уверены, что хотите удалить все данные?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await DatabaseHelper.instance.deleteAllProducts();
      DatabaseHelper.dbUpdateTrigger.value++; // <-- ТРИГГЕР (Очистка БД)
      if (context.mounted) {
        _showMessage(context, 'База данных очищена', isSuccess: true);
      }
    } catch (e) {
      if (context.mounted) {
        _showMessage(context, 'Ошибка очистки: $e');
      }
    }
  }

    // ============================================================
  // ЭКСПОРТ В EXCEL
  // ============================================================
  Future<void> _exportToExcel(BuildContext context) async {
    // 1. Получаем данные из БД
    final products = await DatabaseHelper.instance.getAllProducts();
    if (products.isEmpty) {
      _showMessage(context, 'База данных пуста — нечего экспортировать');
      return;
    }

    // Показываем индикатор загрузки
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Генерация Excel-файла...'),
          ],
        ),
      ),
    );

    try {
      // 2. Создаем Excel-документ
      final excel = Excel.createExcel();
      final Sheet sheet = excel['Каталог'];
      
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      // 3. Формируем заголовки
      sheet.appendRow([
        TextCellValue('Название'),
        TextCellValue('Тип'),
        TextCellValue('Действующие вещества'),
        TextCellValue('Описание'),
        TextCellValue('Норма расхода'),
        TextCellValue('Фасовка'),
        TextCellValue('Цена, руб.'),
        TextCellValue('Производитель'),
        TextCellValue('Культуры'),
        TextCellValue('Болезни'),
      ]);

      // 4. Заполняем строки данными
      for (final p in products) {
        sheet.appendRow([
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

      // 5. Сохраняем в байты
      final bytes = excel.save();
      if (bytes == null) throw Exception('Не удалось сгенерировать файл');
      
      // Преобразуем List<int> в Uint8List (требование нового API file_picker)
      final Uint8List uint8Bytes = Uint8List.fromList(bytes);

      // Закрываем диалог загрузки, так как файл сгенерирован
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

      // 6. Формируем имя файла с текущей датой
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final defaultFileName = 'catalog_export_$dateStr.xlsx';

      // 7. Открываем нативный диалог сохранения файла и передаем байты
      final Uri? outputUri = await FilePicker.saveFile(
        dialogTitle: 'Сохранить базу данных',
        fileName: defaultFileName,
        bytes: uint8Bytes, // Передаем сами данные!
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      // 8. Проверяем результат (если Uri не null, значит сохранение прошло успешно)
      if (outputUri != null) {
        if (context.mounted) {
          _showMessage(context, 'Экспорт успешно завершен!\nФайл сохранен: $defaultFileName', isSuccess: true);
        }
      } else {
        // Пользователь закрыл диалог выбора файла без сохранения
        if (context.mounted) _showMessage(context, 'Сохранение отменено');
      }

    } catch (e, st) {
      // Если произошла ошибка, закрываем диалог загрузки (если он еще открыт)
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop(); 
      
      debugPrint('Export error: $e\n$st');
      if (context.mounted) {
        _showMessage(context, 'Ошибка экспорта: $e');
      }
    }
  }
    // Обертка для подтверждения действия
  Future<bool> _confirmAction(BuildContext context, String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Удалить', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
  }

  // 1. Очистка заказов
  Future<void> _clearOrders(BuildContext context) async {
    if (!await _confirmAction(context, 'Очистка заказов', 'Вы уверены, что хотите удалить ВСЕ заказы? Каталог препаратов останется без изменений.')) return;
    try {
      await DatabaseHelper.instance.clearOrdersOnly();
      DatabaseHelper.dbUpdateTrigger.value++;
      if (context.mounted) _showMessage(context, 'Все заказы удалены', isSuccess: true);
    } catch (e) {
      if (context.mounted) _showMessage(context, 'Ошибка: $e');
    }
  }

  // 2. Очистка каталога
  Future<void> _clearProducts(BuildContext context) async {
    if (!await _confirmAction(context, 'Очистка каталога', 'Вы уверены, что хотите удалить ВСЕ препараты?\n\nИстория заказов сохранится, но позиции в них потеряют связь с каталогом.')) return;
    try {
      await DatabaseHelper.instance.clearProductsOnly();
      DatabaseHelper.dbUpdateTrigger.value++;
      if (context.mounted) _showMessage(context, 'Каталог препаратов удален', isSuccess: true);
    } catch (e) {
      if (context.mounted) _showMessage(context, 'Ошибка: $e');
    }
  }

  // 3. Полный сброс
  Future<void> _clearEverything(BuildContext context) async {
    if (!await _confirmAction(context, 'ПОЛНЫЙ СБРОС', 'ВНИМАНИЕ! Будут удалены ВСЕ данные: заказы, препараты, справочники культур и болезней.\n\nЭто действие нельзя отменить. Продолжить?')) return;
    try {
      await DatabaseHelper.instance.clearEverything();
      DatabaseHelper.dbUpdateTrigger.value++;
      if (context.mounted) _showMessage(context, 'База данных полностью очищена', isSuccess: true);
    } catch (e) {
      if (context.mounted) _showMessage(context, 'Ошибка: $e');
    }
  }
  // ============================================================
  // UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView( // <-- ОБЯЗАТЕЛЬНО: защита от переполнения экрана
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Настройки', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),
            
            // --- БЛОК ИМПОРТА ---
            ElevatedButton.icon(
              onPressed: () => _importFromExcel(context),
              icon: const Icon(Icons.upload_file),
              label: const Text('Импортировать препараты из Excel'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(250, 50),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 15),
            ElevatedButton.icon(
              onPressed: () => _importPartialUpdate(context),
              icon: const Icon(Icons.update),
              label: const Text('Выборочное обновление данных'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(250, 50),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 15),
            
            // --- БЛОК ЗАКАЗОВ ---
            ElevatedButton.icon(
              onPressed: () => _importOrders(context),
              icon: const Icon(Icons.shopping_cart),
              label: const Text('Импортировать заказы из Excel'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(250, 50),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 15),
            ElevatedButton.icon(
              onPressed: () => _exportOrders(context),
              icon: const Icon(Icons.archive),
              label: const Text('Экспортировать заказы в Excel'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(250, 50),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 15),
            
            // --- БЛОК ЭКСПОРТА КАТАЛОГА ---
            ElevatedButton.icon(
              onPressed: () => _exportToExcel(context),
              icon: const Icon(Icons.download),
              label: const Text('Экспортировать каталог в Excel'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(250, 50),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
              ),
            ),
            
            const SizedBox(height: 30),
            const Divider(),
            const SizedBox(height: 10),

            // --- ВЫПАДАЮЩИЙ СПИСОК ОЧИСТКИ (ExpansionTile) ---
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.red.shade200, width: 1),
              ),
              child: ExpansionTile(
                leading: Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
                title: Text(
                  'Очистка данных',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade700),
                ),
                subtitle: const Text('Удаление заказов, каталога или полный сброс'),
                childrenPadding: const EdgeInsets.all(16),
                expandedCrossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _clearOrders(context),
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: const Text('Очистить только заказы'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 45), // Кнопка на всю ширину
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () => _clearProducts(context),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('Очистить только каталог препаратов'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 45),
                      backgroundColor: Colors.deepOrange.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () => _clearEverything(context),
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('ПОЛНЫЙ СБРОС (удалить всё)'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 45),
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40), // Отступ снизу для красоты
          ],
        ),
      ),
    );
  }


}