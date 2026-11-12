// lib/services/file_format_detector.dart
import 'package:excel/excel.dart';
import 'dart:io';

enum FileFormat { catalog, orders, unknown }

class FileFormatDetector {
  /// Определяет формат файла по его заголовкам.
  /// Возвращает FileFormat.catalog, FileFormat.orders или FileFormat.unknown.
  static Future<FileFormat> detectFormat(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      
      bool hasCatalogSigns = false;
      bool hasOrderSigns = false;

      // Проходим по всем листам в файле
      for (var table in excel.tables.keys) {
        final sheet = excel.tables[table];
        if (sheet == null) continue;

        // Проверяем первые 20 строк каждого листа
        for (int i = 0; i < sheet.rows.length && i < 20; i++) {
          final row = sheet.rows[i];
          if (row.isEmpty) continue;
          
          final rowStr = row
              .map((c) => c?.value?.toString().toLowerCase() ?? '')
              .join(' ');

          // Ищем признаки каталога препаратов
          if (rowStr.contains('препарат') || 
              rowStr.contains('наименование') || 
              rowStr.contains('название') ||
              rowStr.contains('состав')) {
            hasCatalogSigns = true;
          }

          // Ищем признаки выгрузки заказов
          if (rowStr.contains('id заказа') || 
              (rowStr.contains('клиент') && rowStr.contains('дата'))) {
            hasOrderSigns = true;
          }
        }
      }

      // Принимаем решение на основе найденных признаков
      if (hasCatalogSigns && hasOrderSigns) {
        // Если есть признаки обоих форматов (например, выгрузили всё в один файл),
        // отдаем приоритет каталогу, либо можно возвращать unknown и спрашивать.
        // Пока приоритет каталогу.
        return FileFormat.catalog;
      } else if (hasCatalogSigns) {
        return FileFormat.catalog;
      } else if (hasOrderSigns) {
        return FileFormat.orders;
      } else {
        return FileFormat.unknown;
      }
    } catch (e) {
      return FileFormat.unknown;
    }
  }
}