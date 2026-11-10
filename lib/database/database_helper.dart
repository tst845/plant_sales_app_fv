// lib/database/database_helper.dart
import 'dart:io';
import 'package:sqflite_sqlcipher/sqflite.dart'; 
import '../utils/db_key_manager.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart'; 
import '../models/product.dart';
import '../models/order.dart';

class DatabaseHelper {
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;

  // Триггер обновления базы данных (для обновления UI)
  static final ValueNotifier<int> dbUpdateTrigger = ValueNotifier<int>(0);

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = join(await getDatabasesPath(), 'plant_sales.db');
    final oldDbPath = join(await getDatabasesPath(), 'plant_sales_old.db');

    // 1. Получаем или генерируем пароль
    final password = await DbKeyManager.obtainOrCreateKey();

    // 2. Проверяем, нужна ли миграция (существует ли старый незашифрованный файл)
    final oldFile = File(dbPath);
    final isMigrationNeeded = await oldFile.exists() && !await File('$dbPath.enc').exists();

    if (isMigrationNeeded) {
      // Переименовываем старый файл, чтобы освободить имя для нового
      await oldFile.rename(oldDbPath);
      try {
        // Открываем новую зашифрованную БД и переносим данные
        final newDb = await openDatabase(
          dbPath,
          password: password,
          version: 7, 
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
          onConfigure: _onConfigure, // <-- ИСПРАВЛЕНО: теперь используется метод класса
        );
        await _migrateFromOldDatabase(newDb, oldDbPath);
        await newDb.close();
      } catch (e) {
        // Если миграция не удалась, возвращаем старый файл на место
        await File(oldDbPath).rename(dbPath);
        rethrow;
      }
      // Удаляем старый файл после успешной миграции
      await File(oldDbPath).delete();
    }

    // 3. Открываем (или создаем) зашифрованную БД
    return openDatabase(
      dbPath,
      password: password,
      version: 7,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure, // <-- ИСПРАВЛЕНО
    );
  }

     /// Переносит все таблицы и данные из старой БД в новую
  Future<void> _migrateFromOldDatabase(Database newDb, String oldDbPath) async {
    // Открываем старую БД БЕЗ пароля
    final oldDb = await openDatabase(oldDbPath, readOnly: true);
    try {
      // Получаем список всех таблиц (кроме системных)
      final tables = await oldDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'"
      );
      for (var table in tables) {
        final tableName = table['name'] as String;
        final rows = await oldDb.query(tableName);
        for (var row in rows) {
          await newDb.insert(tableName, row, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    } finally {
      await oldDb.close();
    }
  }


  // ВКЛЮЧАЕМ ПОДДЕРЖКУ ВНЕШНИХ КЛЮЧЕЙ (КРИТИЧНО ДЛЯ ЦЕЛОСТНОСТИ)
  Future _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('CREATE TABLE categories (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE)');
    await db.execute('CREATE TABLE manufacturers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE)');
    await db.execute('CREATE TABLE cultures (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE)');
    await db.execute('CREATE TABLE diseases (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE)');

    await db.execute('''
      CREATE TABLE products(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        category_id INTEGER,
        manufacturer_id INTEGER,
        composition TEXT,
        description TEXT,
        package TEXT,
        consumption_rate TEXT,
        price REAL,
        FOREIGN KEY (category_id) REFERENCES categories (id),
        FOREIGN KEY (manufacturer_id) REFERENCES manufacturers (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE product_cultures(
        product_id INTEGER,
        culture_id INTEGER,
        PRIMARY KEY (product_id, culture_id),
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE,
        FOREIGN KEY (culture_id) REFERENCES cultures (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE product_diseases(
        product_id INTEGER,
        disease_id INTEGER,
        PRIMARY KEY (product_id, disease_id),
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE,
        FOREIGN KEY (disease_id) REFERENCES diseases (id) ON DELETE CASCADE
      )
    ''');
    // Таблица заказов (шапка)
    await db.execute('''
      CREATE TABLE orders(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_name TEXT NOT NULL,
        order_date TEXT NOT NULL,
        status TEXT NOT NULL,
        total_amount REAL NOT NULL,
        notes TEXT 
      )
    ''');
    // Таблица позиций заказа (тело)
    await db.execute('''
      CREATE TABLE order_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        base_price REAL NOT NULL,
        discount_percent REAL NOT NULL,
        rate REAL NOT NULL,
        area REAL NOT NULL,
        package_unit TEXT NOT NULL,
        FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE SET NULL
      )
    ''');
  
        // Индексы для ускорения связей и поиска
    await db.execute('CREATE INDEX idx_products_category ON products(category_id)');
    await db.execute('CREATE INDEX idx_products_manufacturer ON products(manufacturer_id)');
    await db.execute('CREATE INDEX idx_order_items_order ON order_items(order_id)');
    await db.execute('CREATE INDEX idx_order_items_product ON order_items(product_id)');
    await db.execute('CREATE INDEX idx_product_cultures_product ON product_cultures(product_id)');
    await db.execute('CREATE INDEX idx_product_diseases_product ON product_diseases(product_id)');
  
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE orders ADD COLUMN notes TEXT');
      await db.execute('ALTER TABLE order_items RENAME TO order_items_old');
      await db.execute('''
        CREATE TABLE order_items(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          order_id INTEGER NOT NULL,
          product_id INTEGER,
          product_name TEXT NOT NULL,
          quantity REAL NOT NULL,
          price_per_unit REAL NOT NULL,
          discount_percent REAL NOT NULL,
          FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE,
          FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE SET NULL
        )
      ''');
      await db.execute('''
        INSERT INTO order_items (id, order_id, product_id, product_name, quantity, price_per_unit, discount_percent)
        SELECT id, order_id, product_id, product_name, quantity, price_per_unit, discount_percent FROM order_items_old
      ''');
      await db.execute('DROP TABLE order_items_old');
    }
    if (oldVersion < 7) {
      // 1. Переименовываем старую таблицу
      await db.execute('ALTER TABLE order_items RENAME TO order_items_old');

      // 2. Создаем новую таблицу без package_volume
      await db.execute('''
        CREATE TABLE order_items(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          order_id INTEGER NOT NULL,
          product_id INTEGER,
          product_name TEXT NOT NULL,
          base_price REAL NOT NULL,
          discount_percent REAL NOT NULL,
          rate REAL NOT NULL,
          area REAL NOT NULL,
          package_unit TEXT NOT NULL,
          FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE,
          FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE SET NULL
        )
      ''');

      // 3. Переносим данные из старой таблицы в новую
      await db.execute('''
        INSERT INTO order_items (id, order_id, product_id, product_name, base_price, discount_percent, rate, area, package_unit)
        SELECT id, order_id, product_id, product_name, base_price, discount_percent, rate, area, package_unit FROM order_items_old
      ''');

      // 4. Удаляем старую таблицу
      await db.execute('DROP TABLE order_items_old');
    }
  
   
  }

  // ВАЖНО: Используем DatabaseExecutor, чтобы принимать и Database, и Transaction
  Future<int> _getOrCreateId(DatabaseExecutor db, String table, String? name) async {
    if (name == null || name.trim().isEmpty) return 0; 
    final cleanName = name.trim();
    final res = await db.query(table, columns: ['id'], where: 'name = ?', whereArgs: [cleanName]);
    if (res.isNotEmpty) {
      return res.first['id'] as int;
    } else {
      return await db.insert(table, {'name': cleanName});
    }
  }

  Future<int> _insertSingleProduct(DatabaseExecutor db, Product product) async {
    int catId = await _getOrCreateId(db, 'categories', product.category);
    int manId = await _getOrCreateId(db, 'manufacturers', product.manufacturer);

    final Map<String, dynamic> productMap = {
      'name': product.name,
      'category_id': catId,
      'manufacturer_id': manId > 0 ? manId : null,
      'composition': product.composition,
      'description': product.description,
      'package': product.package,
      'consumption_rate': product.consumptionRate,
      'price': product.price,
    };

    int productId = await db.insert('products', productMap, conflictAlgorithm: ConflictAlgorithm.replace);

    for (var culture in product.cultures) {
      int cultId = await _getOrCreateId(db, 'cultures', culture);
      await db.insert('product_cultures', {'product_id': productId, 'culture_id': cultId}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    for (var disease in product.diseases) {
      int disId = await _getOrCreateId(db, 'diseases', disease);
      await db.insert('product_diseases', {'product_id': productId, 'disease_id': disId}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    return productId;
  }

  // Приватный метод обновления (чтобы можно было вызывать внутри транзакции)
  Future<int> _updateSingleProduct(DatabaseExecutor db, Product product) async {
    int catId = await _getOrCreateId(db, 'categories', product.category);
    int manId = await _getOrCreateId(db, 'manufacturers', product.manufacturer);

    final Map<String, dynamic> productMap = {
      'name': product.name,
      'category_id': catId,
      'manufacturer_id': manId > 0 ? manId : null,
      'composition': product.composition,
      'description': product.description,
      'package': product.package,
      'consumption_rate': product.consumptionRate,
      'price': product.price,
    };

    int res = await db.update('products', productMap, where: 'id = ?', whereArgs: [product.id]);

    await db.delete('product_cultures', where: 'product_id = ?', whereArgs: [product.id]);
    await db.delete('product_diseases', where: 'product_id = ?', whereArgs: [product.id]);

    for (var culture in product.cultures) {
      int cultId = await _getOrCreateId(db, 'cultures', culture);
      await db.insert('product_cultures', {'product_id': product.id, 'culture_id': cultId}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    for (var disease in product.diseases) {
      int disId = await _getOrCreateId(db, 'diseases', disease);
      await db.insert('product_diseases', {'product_id': product.id, 'disease_id': disId}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    return res;
  }

  Future<int> insertProduct(Product product) async {
    Database db = await database;
    return await _insertSingleProduct(db, product);
  }

  Future<void> insertProducts(List<Product> products) async {
    Database db = await database;
    await db.transaction((txn) async {
      for (var product in products) {
        await _insertSingleProduct(txn, product);
      }
    });
  }

  Future<List<Product>> getAllProducts() async {
    Database db = await database;
    
    // 1. Получаем препараты
    final productMaps = await db.rawQuery('''
      SELECT p.*, c.name as category, m.name as manufacturer 
      FROM products p
      LEFT JOIN categories c ON p.category_id = c.id
      LEFT JOIN manufacturers m ON p.manufacturer_id = m.id
    ''');

    // 2. Получаем ВСЕ связи культур (один запрос)
    final culturesData = await db.rawQuery('''
      SELECT pc.product_id, c.name 
      FROM product_cultures pc
      JOIN cultures c ON pc.culture_id = c.id
    ''');
    final Map<int, List<String>> culturesMap = {};
    for (var row in culturesData) {
      final pId = row['product_id'] as int;
      culturesMap.putIfAbsent(pId, () => []).add(row['name'] as String);
    }

    // 3. Получаем ВСЕ связи болезней (один запрос)
    final diseasesData = await db.rawQuery('''
      SELECT pd.product_id, d.name 
      FROM product_diseases pd
      JOIN diseases d ON pd.disease_id = d.id
    ''');
    final Map<int, List<String>> diseasesMap = {};
    for (var row in diseasesData) {
      final pId = row['product_id'] as int;
      diseasesMap.putIfAbsent(pId, () => []).add(row['name'] as String);
    }

    // 4. Склеиваем всё в памяти
    List<Product> products = [];
    for (var map in productMaps) {
      int productId = map['id'] as int;
      products.add(Product.fromMap(
        map, 
        cultures: culturesMap[productId] ?? [], 
        diseases: diseasesMap[productId] ?? []
      ));
    }
    return products;
  }

  Future<int> updateProduct(Product product) async {
    Database db = await database;
    return await _updateSingleProduct(db, product);
  }

  Future<int> deleteProduct(int id) async {
    Database db = await database;
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllProducts() async {
    Database db = await database;
    await db.delete('products'); 
  }

  Future<Map<String, List<String>>> getUniqueCulturesAndDiseases() async {
    final db = await database;
    final cultures = (await db.query('cultures', orderBy: 'name')).map((e) => e['name'] as String).toList();
    final diseases = (await db.query('diseases', orderBy: 'name')).map((e) => e['name'] as String).toList();
    return {'cultures': cultures, 'diseases': diseases};
  }

  Future<Set<String>> getExistingProductNames() async {
    final db = await database;
    final rows = await db.query('products', columns: ['name']);
    return rows.map((r) => (r['name'] as String).trim().toLowerCase()).toSet();
  }

  Future<void> updateProducts(List<Product> products) async {
    Database db = await database;
    await db.transaction((txn) async {
      for (var product in products) {
        final res = await txn.query('products', columns: ['id'], where: 'name = ?', whereArgs: [product.name]);
        if (res.isNotEmpty) {
          int id = res.first['id'] as int;
          product = Product(
            id: id,
            name: product.name,
            category: product.category,
            composition: product.composition,
            manufacturer: product.manufacturer,
            package: product.package,
            consumptionRate: product.consumptionRate,
            price: product.price,
            description: product.description,
            cultures: product.cultures,
            diseases: product.diseases,
          );
          await _updateSingleProduct(txn, product); // <-- Исправлено на txn
        }
      }
    });
  }


  // 2. Обновление полей (с учетом новых связей)
  Future<void> batchUpdateProductsByField(Map<String, Map<String, dynamic>> updates) async {
    Database db = await database;
    await db.transaction((txn) async {
      for (var entry in updates.entries) {
        String name = entry.key;
        Map<String, dynamic> fields = entry.value;
        
        // Извлекаем списки культур и болезней, если они есть в обновлении
        List<String>? newCultures;
        if (fields.containsKey('cultures')) {
          final cultStr = fields.remove('cultures') as String?;
          if (cultStr != null) {
            newCultures = cultStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
          }
        }
        
        List<String>? newDiseases;
        if (fields.containsKey('diseases')) {
          final disStr = fields.remove('diseases') as String?;
          if (disStr != null) {
            newDiseases = disStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
          }
        }

        // Обновляем ID категории и производителя
        if (fields.containsKey('category')) {
           fields['category_id'] = await _getOrCreateId(txn, 'categories', fields['category']);
           fields.remove('category');
        }
        if (fields.containsKey('manufacturer')) {
           fields['manufacturer_id'] = await _getOrCreateId(txn, 'manufacturers', fields['manufacturer']);
           fields.remove('manufacturer');
        }
        
        // Обновляем саму таблицу products
        await txn.update('products', fields, where: 'name = ?', whereArgs: [name]);

        // Находим ID обновленного препарата
        final res = await txn.query('products', columns: ['id'], where: 'name = ?', whereArgs: [name]);
        if (res.isNotEmpty) {
          int productId = res.first['id'] as int;

          // Обновляем культуры, если они были выбраны для обновления
          if (newCultures != null) {
            await txn.delete('product_cultures', where: 'product_id = ?', whereArgs: [productId]);
            for (var culture in newCultures) {
              int cultId = await _getOrCreateId(txn, 'cultures', culture);
              await txn.insert('product_cultures', {'product_id': productId, 'culture_id': cultId}, conflictAlgorithm: ConflictAlgorithm.ignore);
            }
          }

          // Обновляем болезни, если они были выбраны
          if (newDiseases != null) {
            await txn.delete('product_diseases', where: 'product_id = ?', whereArgs: [productId]);
            for (var disease in newDiseases) {
              int disId = await _getOrCreateId(txn, 'diseases', disease);
              await txn.insert('product_diseases', {'product_id': productId, 'disease_id': disId}, conflictAlgorithm: ConflictAlgorithm.ignore);
            }
          }
        }
      }
    });
  }

  // ==========================================
  // CRUD ДЛЯ ЗАКАЗОВ
  // ==========================================

    // --- СОХРАНЕНИЕ НОВОГО ЗАКАЗА ---
  Future<int> insertOrder(Order order) async {
    Database db = await database;
    return await db.transaction((txn) async {
      // 1. Сохраняем шапку заказа
      final orderId = await txn.insert('orders', {
        'client_name': order.clientName,
        'order_date': order.orderDate.toIso8601String(),
        'status': order.status,
        'notes': order.notes,
        'total_amount': order.totalAmount,
      });
      
      // 2. Сохраняем позиции
      for (var item in order.items) {
        await txn.insert('order_items', {
          'order_id': orderId,
          'product_id': item.productId,
          'product_name': item.productName,
          'base_price': item.basePrice,
          'discount_percent': item.discountPercent,
          'rate': item.rate,
          'area': item.area,
          'package_unit': item.packageUnit,
        });
      }
      return orderId;
    });
  }

  // --- ОБНОВЛЕНИЕ СУЩЕСТВУЮЩЕГО ЗАКАЗА ---
  Future<void> updateOrder(Order order, {DatabaseExecutor? executor}) async {
    if (executor == null) {
      await (await database).transaction((txn) async {
        await _executeUpdateOrder(txn, order);
      });
    } else {
      await _executeUpdateOrder(executor, order);
    }
  }

  Future<void> _executeUpdateOrder(DatabaseExecutor db, Order order) async {
    await db.update('orders', {
      'client_name': order.clientName,
      'order_date': order.orderDate.toIso8601String(),
      'status': order.status,
      'notes': order.notes,
      'total_amount': order.totalAmount,
    }, where: 'id = ?', whereArgs: [order.id]);

    await db.delete('order_items', where: 'order_id = ?', whereArgs: [order.id]);
    for (var item in order.items) {
      await db.insert('order_items', {
        'order_id': order.id,
        'product_id': item.productId,
        'product_name': item.productName,
        'base_price': item.basePrice,
        'discount_percent': item.discountPercent,
        'rate': item.rate,
        'area': item.area,
        'package_unit': item.packageUnit,
      });
    }
  }

  // --- УДАЛЕНИЕ ЗАКАЗА ---
  Future<int> deleteOrder(int id) async {
    Database db = await database;
    // Если в схеме БД настроен ON DELETE CASCADE для order_items, 
    // то позиции удалятся автоматически. Если нет — удалите их вручную перед удалением шапки.
    return await db.delete('orders', where: 'id = ?', whereArgs: [id]);
  }

  // ПОЛУЧЕНИЕ ВСЕХ ЗАКАЗОВ (Read)
  Future<List<Order>> getAllOrders() async {
    final db = await database;
    
    // 1. Получаем все заказы
    final orderMaps = await db.query('orders', orderBy: 'order_date DESC, id DESC'); 

    // 2. Одним запросом получаем ВСЕ позиции для всех заказов
    final itemMaps = await db.query('order_items');
    
    // Группируем позиции по order_id
    final Map<int, List<OrderItem>> itemsByOrder = {};
    for (var item in itemMaps) {
      final orderId = item['order_id'] as int;
      itemsByOrder.putIfAbsent(orderId, () => []).add(OrderItem.fromMap(item));
    }

    // 3. Склеиваем
    List<Order> orders = [];
    for (var map in orderMaps) {
      final orderId = map['id'] as int;
      orders.add(Order.fromMap(map, itemsByOrder[orderId] ?? []));
    }
    return orders;
  }

  // Вспомогательный метод для получения позиций заказа
  Future<List<OrderItem>> getOrderItems(int orderId) async {
    final db = await database;
    final itemMaps = await db.query(
      'order_items',
      where: 'order_id = ?',
      whereArgs: [orderId],
    );
    return itemMaps.map((e) => OrderItem.fromMap(e)).toList();
  }

  // ==========================================
  // МЕТОДЫ ДЛЯ ИМПОРТА/ЭКСПОРТА ЗАКАЗОВ (BACKUP)
  // ==========================================

  // Очистка всех заказов (для режима "Заменить всё")
  Future<void> deleteAllOrders() async {
    Database db = await database;
    await db.delete('order_items');
    await db.delete('orders');
  }

  // Получить все ID заказов, которые есть в БД
  Future<Set<int>> getAllOrderIds() async {
    final db = await database;
    final rows = await db.query('orders', columns: ['id']);
    return rows.map((r) => r['id'] as int).toSet();
  }

  // Вставка заказа с принудительным ID (для восстановления)
  
  Future<void> insertOrderWithId(Order order, {DatabaseExecutor? executor}) async {
    DatabaseExecutor db = executor ?? await database;
    // Если транзакция передана извне, используем её. Если нет - создаем свою (через await database).
    
    if (executor == null) {
      await (await database).transaction((txn) async {
        await _executeInsertOrderWithId(txn, order);
      });
    } else {
      await _executeInsertOrderWithId(db, order);
    }
  }
  Future<void> _executeInsertOrderWithId(DatabaseExecutor db, Order order) async {
    await db.insert('orders', {
      'id': order.id,
      'client_name': order.clientName,
      'order_date': order.orderDate.toIso8601String(),
      'status': order.status,
      'notes': order.notes,
      'total_amount': order.totalAmount,
    });
    
    for (var item in order.items) {
      await db.insert('order_items', {
        'order_id': order.id,
        'product_id': item.productId,
        'product_name': item.productName,
        'base_price': item.basePrice,
        'discount_percent': item.discountPercent,
        'rate': item.rate,
        'area': item.area,
        'package_unit': item.packageUnit,
      });
    }
  }


  // Получить карту всех препаратов (ID -> Product) для быстрого поиска
  Future<Map<int, Product>> getProductsIdMap() async {
    final products = await getAllProducts();
    return {for (var p in products) p.id!: p};
  }

  // Создать "заглушку" препарата, если его нет в БД
    // ДОБАВИТЬ ВОЗМОЖНОСТЬ ПЕРЕДАВАТЬ ТРАНЗАКЦИЮ (txn)
  Future<int> createStubProduct(String name, {DatabaseExecutor? executor}) async {
    DatabaseExecutor db = executor ?? await database; // Используем транзакцию, если передана

    int catId = await _getOrCreateId(db, 'categories', 'Импортированные (без категории)');
    
    final res = await db.query('products', columns: ['id'], where: 'name = ?', whereArgs: [name]);
    if (res.isNotEmpty) return res.first['id'] as int;

    return await db.insert('products', {
      'name': name,
      'category_id': catId,
    });
  }

  // 1. Очистить ТОЛЬКО заказы (каталог остается)
  Future<void> clearOrdersOnly() async {
    Database db = await database;
    await db.transaction((txn) async {
      await txn.delete('order_items');
      await txn.delete('orders');
    });
  }

  // 2. Очистить ТОЛЬКО препараты (заказы остаются)
  Future<void> clearProductsOnly() async {
    Database db = await database;
    await db.transaction((txn) async {
      // ИСПРАВЛЕНИЕ: используем txn вместо db
      await txn.delete('products'); 
      await txn.delete('categories', where: 'id NOT IN (SELECT DISTINCT category_id FROM products WHERE category_id IS NOT NULL)');
      await txn.delete('manufacturers', where: 'id NOT IN (SELECT DISTINCT manufacturer_id FROM products WHERE manufacturer_id IS NOT NULL)');
      await txn.delete('cultures', where: 'id NOT IN (SELECT DISTINCT culture_id FROM product_cultures)');
      await txn.delete('diseases', where: 'id NOT IN (SELECT DISTINCT disease_id FROM product_diseases)');
    });
  }

  // 3. Полный сброс (удаляет ВООБЩЕ всё)
   // ОБНОВЛЕННАЯ ОЧИСТКА (Сброс автоинкремента)
  Future<void> clearEverything() async {
    Database db = await database;
    await db.transaction((txn) async {
      await txn.delete('order_items');
      await txn.delete('orders');
      await txn.delete('product_cultures');
      await txn.delete('product_diseases');
      await txn.delete('products');
      await txn.delete('categories');
      await txn.delete('manufacturers');
      await txn.delete('cultures');
      await txn.delete('diseases');
      
      // СБРОС СЧЕТЧИКОВ ID (чтобы новые данные начинались с ID = 1)
      await txn.delete('sqlite_sequence'); 
    });
  }

  Future<void> insertSampleData() async {
    Database db = await database;
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM products'));
    if (count != null && count > 0) return; // Если уже есть данные, ничего не делаем

    // Пример препарата
    Product sampleProduct = Product(
      name: 'Абакус Ультра, СЭ',
      category: 'Фунгициды',
      composition: 'Пираклостробин 62,5 г/л + Эпоксиконазол 62,5 г/л',
      manufacturer: 'БАСФ',
      package: '10 л',
      consumptionRate: '1,0-1,5',
      price: 3081.72,
      description: 'Демонстрационный препарат для знакомства с приложением.',
      cultures: ['Пшеница', 'Ячмень'],
      diseases: ['Ржавчина', 'Септориоз'],
    );
    
    await insertProduct(sampleProduct);

    // Пример заказа
    Order sampleOrder = Order(
      id: 1, // Принудительный ID
      clientName: 'Иван Иванов (Пример)',
      orderDate: DateTime.now(),
      status: 'Новый',
      notes: 'Этот заказ создан автоматически для демонстрации.',
      items: [
        OrderItem(
          productId: 1, // ID только что созданного препарата
          productName: 'Абакус Ультра, СЭ',
          basePrice: 3081.72,
          discountPercent: 5.0,
          rate: 1.5,
          area: 10.0,
          packageUnit: 'л',
        )
      ]
    );
    
    await insertOrderWithId(sampleOrder);
  }

}// DatabaseHelper 