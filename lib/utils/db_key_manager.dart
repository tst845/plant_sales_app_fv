import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DbKeyManager {
  static const _storage = FlutterSecureStorage();
  static const _keyName = 'plant_sales_db_key';

  /// Возвращает существующий ключ или генерирует новый 256-битный ключ
  static Future<String> obtainOrCreateKey() async {
    // Пытаемся прочитать ключ
    String? existingKey = await _storage.read(key: _keyName);
    if (existingKey != null) return existingKey;

    // Генерируем новый криптостойкий ключ
    final random = Random.secure();
    final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final newKey = base64UrlEncode(keyBytes);

    // Сохраняем и возвращаем
    await _storage.write(key: _keyName, value: newKey);
    return newKey;
  }
}