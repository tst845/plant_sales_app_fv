// lib/services/file_format_detector.dart
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

enum FileFormat { catalog, orders, unknown }

class FileFormatDetector {
  static Future<FileFormat> detectFormat(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final excel = Excel.decodeBytes(bytes);

      bool hasOrderSigns = false;
      bool hasCatalogSigns = false;
      bool hasOrdersSheet = false;
      bool hasItemsSheet = false;

      for (final table in excel.tables.keys) {
        final lowerName = table.toLowerCase();
        if (lowerName.contains('заказ') || lowerName.contains('order')) {
          hasOrdersSheet = true;
        }
        if (lowerName.contains('позиц') || lowerName.contains('item')) {
          hasItemsSheet = true;
        }

        final sheet = excel.tables[table];
        if (sheet == null) continue;

        for (int i = 0; i < sheet.rows.length && i < 20; i++) {
          final row = sheet.rows[i];
          if (row.isEmpty) continue;

          final rowStr =
              row.map((c) => c?.value?.toString().toLowerCase() ?? '').join(' ');

          // --- СИЛЬНЫЕ признаки заказов ---
          if (rowStr.contains('id заказа') ||
              (rowStr.contains('клиент') && rowStr.contains('статус'))) {
            hasOrderSigns = true;
          }

          // --- Признаки каталога / прайс-листа (шире) ---
          if (rowStr.contains('тип') ||
              rowStr.contains('категор') ||
              rowStr.contains('препарат') ||
              rowStr.contains('название') ||
              rowStr.contains('наименование') ||
              rowStr.contains('состав') ||
              rowStr.contains('действующ')) {
            hasCatalogSigns = true;
          }
        }
      }

      // Приоритет: заказы важнее каталога.
      if (hasOrderSigns || (hasOrdersSheet && hasItemsSheet)) {
        return FileFormat.orders;
      }
      if (hasCatalogSigns) return FileFormat.catalog;
      return FileFormat.unknown;
    } catch (e) {
      debugPrint('FileFormatDetector error: $e');
      return FileFormat.unknown;
    }
  }
}