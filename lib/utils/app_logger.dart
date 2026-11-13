import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;
  AppLogger._internal();

  late Logger _logger;
  File? _logFile;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _logFile = File('${dir.path}/app.log');

    _logger = Logger(
      filter: ProductionFilter(),
      printer: PrettyPrinter(
        methodCount: 0,
        errorMethodCount: 5,
        lineLength: 80,
        colors: false,
        printEmojis: false,
      ),
      output: MultiOutput([
        ConsoleOutput(),
        FileOutput(file: _logFile!),
      ]),
    );
    // Файл создастся сам — только когда появится первая запись
  }

  void e(String message, {Object? error, StackTrace? stackTrace}) =>
      _logger.e(message, error: error, stackTrace: stackTrace);

  /// Готовит лог к отправке. Возвращает путь к копии,
  /// либо null, если файла нет / он пуст.
  Future<String?> prepareForSharing() async {
    if (_logFile == null) return null;
    if (!await _logFile!.exists()) return null;
    if (await _logFile!.length() == 0) return null;

    final tempDir = await getTemporaryDirectory();
    final tempFile = File(
      '${tempDir.path}/plant_sales_log_${DateTime.now().millisecondsSinceEpoch}.log',
    );
    await _logFile!.copy(tempFile.path);
    return tempFile.path;
  }
}