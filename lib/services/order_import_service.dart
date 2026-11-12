// lib/services/order_import_service.dart
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:io';
import '../database/database_helper.dart';
import '../models/order.dart';
import '../models/product.dart';


class OrderImportService {
  
  // ДОБАВЛЕН параметр filePath
  static Future<void> importOrders(BuildContext context, {String? filePath}) async {
    try {
      String? path = filePath;
      if (path == null) {
        final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx']);
        if (result == null || result.isEmpty) return;
        path = result.first.path;
      }

      final bytes = await File(path!).readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final allSheetNames = excel.tables.keys.toList();

      if (allSheetNames.isEmpty) {
        if (context.mounted) _showMessage(context, 'Файл пуст');
        return;
      }

      final mapping = await _showOrderSheetMappingDialog(context, allSheetNames);
      if (mapping == null) return;

      final ordersSheetName = mapping['orders'];
      final itemsSheetName = mapping['items'];

      if (ordersSheetName == null && itemsSheetName == null) {
        if (context.mounted) _showMessage(context, 'Не выбрано ни одного листа для импорта');
        return;
      }

      List<Order> parsedOrders = [];
      Map<int, List<OrderItem>> itemsForExistingOrders = {};
      List<String> parseErrors = [];

      // --- ПАРСИНГ ЗАКАЗОВ ---
      if (ordersSheetName != null) {
        final sheet = excel.tables[ordersSheetName]!;
        int headerRow = _findHeaderRow(sheet, [
          ['id', 'номер'], 
          ['клиент', 'заказчик', 'контрагент']
        ]);
        if (headerRow == -1) {
          if (context.mounted) _showMessage(context, 'Не найдены обязательные колонки в листе Заказы (ID, Клиент)');
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

      // --- ПАРСИНГ ПОЗИЦИЙ ---
      if (itemsSheetName != null) {
        final sheet = excel.tables[itemsSheetName]!;
        int headerRow = _findHeaderRow(sheet, [
          ['id заказа', 'заказ'], 
          ['наименование', 'название', 'препарат']
        ]);
        if (headerRow == -1) {
          if (context.mounted) _showMessage(context, 'Не найдены обязательные колонки в листе Позиции (ID заказа, Наименование)');
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
            itemsForExistingOrders.putIfAbsent(orderId, () => []).add(item);
          }
        }
      }

      if (parsedOrders.isEmpty && itemsForExistingOrders.isEmpty) {
        if (context.mounted) _showMessage(context, 'Не найдено валидных данных для импорта');
        return;
      }

      // --- ВЫБОР РЕЖИМА ---
      String modeDialogText = 'Найдено заказов: ${parsedOrders.length}.\n';
      if (itemsForExistingOrders.isNotEmpty) {
        modeDialogText += 'Найдено позиций для заказов не из файла: ${itemsForExistingOrders.length} заказов.\n';
      }
      modeDialogText += 'Ошибок при чтении: ${parseErrors.length}.\n\nКак применить данные?';

      if (!context.mounted) return;
      final mode = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Режим импорта'),
          content: Text(modeDialogText),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'add'), child: const Text('Только новые')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'update'), child: const Text('Обновить и добавить')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, 'replace'), child: const Text('Заменить всё')),
          ],
        ),
      );

      if (mode == null || mode == 'cancel') return;

      // --- СОХРАНЕНИЕ ---
      if (!context.mounted) return;
      showDialog(context: context, barrierDismissible: false, builder: (ctx) => const AlertDialog(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text('Сохранение данных...')])));

      final db = DatabaseHelper.instance;
      final database = await db.database; 

      int addedOrders = 0;
      int updatedOrders = 0;
      int itemsAddedToExisting = 0;
      List<String> criticalErrors = [];

      await database.transaction((txn) async {
        if (mode == 'replace') {
          await txn.delete('order_items');
          await txn.delete('orders');
        }

        final rows = await txn.query('orders', columns: ['id']);
        final existingIds = rows.map((r) => r['id'] as int).toSet();
        final productsMap = await db.getProductsIdMap();

        for (var order in parsedOrders) {
          for (int i = 0; i < order.items.length; i++) {
            var item = order.items[i];
            int? resolvedId = item.productId;
            if (resolvedId != null && !productsMap.containsKey(resolvedId)) resolvedId = null;

            if (resolvedId == null) {
              final existing = productsMap.values.where((p) => p.name.toLowerCase() == item.productName.toLowerCase()).firstOrNull;
              if (existing != null) {
                resolvedId = existing.id;
              } else {
                resolvedId = await db.createStubProduct(item.productName, executor: txn);
                productsMap[resolvedId] = Product(id: resolvedId, name: item.productName, category: 'Импортированные (без категории)');
              }
            }
            order.items[i] = item.copyWith(productId: resolvedId);
          }

          if (existingIds.contains(order.id)) {
            if (mode == 'update') {
              await db.updateOrder(order, executor: txn);
              updatedOrders++;
            }
          } else {
            await db.insertOrderWithId(order, executor: txn);
            addedOrders++;
          }
        }

        for (var entry in itemsForExistingOrders.entries) {
          final orderId = entry.key;
          final newItems = entry.value;

          if (existingIds.contains(orderId)) {
             final dbOrderMaps = await txn.query('orders', where: 'id = ?', whereArgs: [orderId]);
             if (dbOrderMaps.isNotEmpty) {
                 final existingOrder = Order.fromMap(dbOrderMaps.first, []);
                 
                 for (int i = 0; i < newItems.length; i++) {
                    var item = newItems[i];
                    int? resolvedId = item.productId;
                    if (resolvedId != null && !productsMap.containsKey(resolvedId)) resolvedId = null;

                    if (resolvedId == null) {
                      final existing = productsMap.values.where((p) => p.name.toLowerCase() == item.productName.toLowerCase()).firstOrNull;
                      if (existing != null) {
                        resolvedId = existing.id;
                      } else {
                        resolvedId = await db.createStubProduct(item.productName, executor: txn);
                        productsMap[resolvedId] = Product(id: resolvedId, name: item.productName, category: 'Импортированные (без категории)');
                      }
                    }
                    newItems[i] = item.copyWith(productId: resolvedId);
                 }

                 if (mode == 'add') {
                     final oldItemsQuery = await txn.query('order_items', where: 'order_id = ?', whereArgs: [orderId]);
                     final oldItemsList = oldItemsQuery.map((e) => OrderItem.fromMap(e)).toList();
                     
                     final combinedItems = [...oldItemsList, ...newItems];
                     final updatedOrder = existingOrder.copyWith(items: combinedItems);
                     await db.updateOrder(updatedOrder, executor: txn);
                     itemsAddedToExisting += newItems.length;
                 } else {
                     final updatedOrder = existingOrder.copyWith(items: newItems);
                     await db.updateOrder(updatedOrder, executor: txn);
                     updatedOrders++;
                 }
             }
          } else {
            criticalErrors.add('Заказ №$orderId не найден в БД. Пропущено позиций: ${newItems.length}');
          }
        }
      });

      if (context.mounted) Navigator.of(context).pop(); // Закрываем диалог прогресса
      DatabaseHelper.dbUpdateTrigger.value++; 

      String report = 'Импорт заказов завершен.\n';
      if (addedOrders > 0) report += '✅ Добавлено новых заказов: $addedOrders\n';
      if (updatedOrders > 0) report += '♻️ Обновлено существующих заказов: $updatedOrders\n';
      if (itemsAddedToExisting > 0) report += '📦 Добавлено позиций к заказам в БД: $itemsAddedToExisting\n';
      
      if (parseErrors.isNotEmpty || criticalErrors.isNotEmpty) {
        report += '\n⚠️ Ошибки и предупреждения:\n';
        report += parseErrors.take(5).join('\n');
        report += criticalErrors.take(5).join('\n');
        if (parseErrors.length + criticalErrors.length > 5) {
          report += '\n... и еще ${parseErrors.length + criticalErrors.length - 5} ошибок.';
        }
      }

      if (context.mounted) _showMessage(context, report, isSuccess: true);

    } catch (e, st) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      debugPrint('Order import error: $e\n$st');
      if (context.mounted) _showMessage(context, 'Ошибка импорта заказов: $e');
    }
  }

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

  static int _findHeaderRow(Sheet sheet, List<List<String>> keywordGroups) {
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

  static int _findCol(List<String> headers, List<String> keywords) {
    for (int i = 0; i < headers.length; i++) {
      for (var kw in keywords) {
        if (headers[i].contains(kw)) return i;
      }
    }
    return -1;
  }

  static Future<Map<String, String?>?> _showOrderSheetMappingDialog(BuildContext context, List<String> sheets) async {
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
                initialValue: ordersSheet,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Нет')),
                  ...sheets.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                ],
                onChanged: (val) => setState(() => ordersSheet = val),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Лист с Позициями (Препараты)'),
                initialValue: itemsSheet,
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

  static void _showMessage(BuildContext context, String message, {bool isSuccess = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? Colors.green : Colors.red,
      ),
    );
  }
}