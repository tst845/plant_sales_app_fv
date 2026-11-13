// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'dart:typed_data';
import '../database/database_helper.dart';
import '../widgets/import_wizard_dialog.dart';
import '../services/order_import_service.dart';
import '../widgets/dictionary_editor_dialog.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  // ============================================================
  // ИМПОРТ И ЭКСПОРТ ЗАКАЗОВ
  // ============================================================
  
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
      
      final sheetOrders = excel['Заказы'];
      sheetOrders.appendRow([
        TextCellValue('ID заказа'), TextCellValue('Дата'), TextCellValue('Клиент'),
        TextCellValue('Статус'), TextCellValue('Примечание'), TextCellValue('Итоговая сумма')
      ]);

      final sheetItems = excel['Позиции'];
      sheetItems.appendRow([
        TextCellValue('ID заказа'), TextCellValue('ID Препарата'), TextCellValue('Наименование'),
        TextCellValue('Цена (базовая)'), TextCellValue('Скидка %'), TextCellValue('Норма расхода'),
        TextCellValue('Площадь, га'), TextCellValue('Ед. изм.'), TextCellValue('Стоимость позиции')
      ]);

      if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

      for (var order in orders) {
        final dateStr = '${order.orderDate.day}.${order.orderDate.month}.${order.orderDate.year}';
        
        sheetOrders.appendRow([
          IntCellValue(order.id!),
          TextCellValue(dateStr),
          TextCellValue(order.clientName),
          TextCellValue(order.status),
          TextCellValue(order.notes ?? ''),
          DoubleCellValue(order.totalAmount),
        ]);

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

  // ============================================================
  // ЭКСПОРТ КАТАЛОГА
  // ============================================================
  Future<void> _exportToExcel(BuildContext context) async {
    final products = await DatabaseHelper.instance.getAllProducts();
    if (products.isEmpty) {
      _showMessage(context, 'База данных пуста — нечего экспортировать');
      return;
    }

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
      final excel = Excel.createExcel();
      final Sheet sheet = excel['Каталог'];
      
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

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

      final bytes = excel.save();
      if (bytes == null) throw Exception('Не удалось сгенерировать файл');
      
      final Uint8List uint8Bytes = Uint8List.fromList(bytes);

      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final defaultFileName = 'catalog_export_$dateStr.xlsx';

      final Uri? outputUri = await FilePicker.saveFile(
        dialogTitle: 'Сохранить базу данных',
        fileName: defaultFileName,
        bytes: uint8Bytes,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (outputUri != null) {
        if (context.mounted) {
          _showMessage(context, 'Экспорт успешно завершен!\nФайл сохранен: $defaultFileName', isSuccess: true);
        }
      } else {
        if (context.mounted) _showMessage(context, 'Сохранение отменено');
      }

    } catch (e, st) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop(); 
      debugPrint('Export error: $e\n$st');
      if (context.mounted) {
        _showMessage(context, 'Ошибка экспорта: $e');
      }
    }
  }

  // ============================================================
  // ОЧИСТКА ДАННЫХ
  // ============================================================
  
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

  void _showMessage(BuildContext context, String message, {bool isSuccess = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? Colors.green : Colors.red,
      ),
    );
  }

  // ============================================================
  // UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Настройки', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),
            
            // --- ЕДИНАЯ КНОПКА ИМПОРТА КАТАЛОГА (МАСТЕР) ---
            ElevatedButton.icon(
              onPressed: () async {
                await showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => const ImportWizardDialog(),
                );
                DatabaseHelper.dbUpdateTrigger.value++;
              },
              icon: const Icon(Icons.upload_file),
              label: const Text('Импорт данных из Excel'),
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
              onPressed: () => OrderImportService.importOrders(context), // ИСПРАВЛЕНО: вызываем статический метод
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
            // --- КНОПКА УПРАВЛЕНИЯ СПРАВОЧНИКАМИ ---
            ElevatedButton.icon(
              onPressed: () async {
                await showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => const DictionaryEditorDialog(),
                );
                DatabaseHelper.dbUpdateTrigger.value++; // Обновляем UI после закрытия
              },
              icon: const Icon(Icons.menu_book),
              label: const Text('Типы, Культуры, Болезни'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(250, 50),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 15),

            const Divider(),
            const SizedBox(height: 10),

            // --- ВЫПАДАЮЩИЙ СПИСОК ОЧИСТКИ ---
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
                      minimumSize: const Size(double.infinity, 45),
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
            const SizedBox(height: 40),
          ],
        ),
      ),
      ),
    );
  }
}