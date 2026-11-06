// lib/database/database_helper.dart
import 'package:sqflite/sqflite.dart';
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
    String path = join(await getDatabasesPath(), 'plant_sales.db');
    return await openDatabase(
      path,
      version: 6, 
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON'); 
      },
    );
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
    // НОВАЯ ТАБЛИЦА order_items
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
        package_volume REAL NOT NULL,
        package_unit TEXT NOT NULL,
        FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE SET NULL
      )
    ''');
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
    if (oldVersion < 6) {
      // Пересоздаем таблицу order_items под новые поля
      await db.execute('DROP TABLE IF EXISTS order_items');
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
          package_volume REAL NOT NULL,
          package_unit TEXT NOT NULL,
          FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE,
          FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE SET NULL
        )
      ''');
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
    final query = '''
      SELECT p.*, c.name as category, m.name as manufacturer 
      FROM products p
      LEFT JOIN categories c ON p.category_id = c.id
      LEFT JOIN manufacturers m ON p.manufacturer_id = m.id
    ''';
    
    final maps = await db.rawQuery(query);
    List<Product> products = [];

    for (var map in maps) {
      int productId = map['id'] as int;
      
      final culturesData = await db.rawQuery('''
        SELECT c.name FROM cultures c
        JOIN product_cultures pc ON c.id = pc.culture_id
        WHERE pc.product_id = ?
      ''', [productId]);
      final cultures = culturesData.map((e) => e['name'] as String).toList();

      final diseasesData = await db.rawQuery('''
        SELECT d.name FROM diseases d
        JOIN product_diseases pd ON d.id = pd.disease_id
        WHERE pd.product_id = ?
      ''', [productId]);
      final diseases = diseasesData.map((e) => e['name'] as String).toList();

      products.add(Product.fromMap(map, cultures: cultures, diseases: diseases));
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

  // 1. Очистка "мусора" из справочников (например, "4-Д" и т.п.)
  Future<void> cleanDatabaseReferences() async {
    final db = await database;
    // Удаляем пустые или нерелевантные записи (можно добавить свои условия)
    await db.delete('cultures', where: "name = '' OR name IS NULL");
    await db.delete('diseases', where: "name = '' OR name IS NULL OR name LIKE '%4-Д%' OR name LIKE '%МЦПА%'");
    // Связующие таблицы очистятся автоматически благодаря ON DELETE CASCADE
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

  // СОЗДАНИЕ (Insert)
  Future<int> insertOrder(Order order) async {
    final db = await database;
    return await db.transaction((txn) async {
      // 1. Вставляем шапку заказа
      final orderId = await txn.insert('orders', order.toMap());
      
      // 2. Вставляем позиции
      for (var item in order.items) {
        final itemMap = item.toMap();
        itemMap['order_id'] = orderId; // Привязываем к созданному заказу
        await txn.insert('order_items', itemMap);
      }
      return orderId;
    });
  }

  // ОБНОВЛЕНИЕ (Update)
  Future<void> updateOrder(Order order) async {
    final db = await database;
    if (order.id == null) throw Exception('Невозможно обновить заказ без ID');
    
    await db.transaction((txn) async {
      // 1. Обновляем шапку
      await txn.update(
        'orders',
        order.toMap(),
        where: 'id = ?',
        whereArgs: [order.id],
      );

      // 2. Удаляем все старые позиции этого заказа
      await txn.delete(
        'order_items',
        where: 'order_id = ?',
        whereArgs: [order.id],
      );

      // 3. Вставляем новые позиции
      for (var item in order.items) {
        final itemMap = item.toMap();
        itemMap['order_id'] = order.id;
        await txn.insert('order_items', itemMap);
      }
    });
  }

  // УДАЛЕНИЕ (Delete)
  Future<void> deleteOrder(int orderId) async {
    final db = await database;
    // Благодаря ON DELETE CASCADE, позиции (order_items) удалятся автоматически
    await db.delete(
      'orders',
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  // ПОЛУЧЕНИЕ ВСЕХ ЗАКАЗОВ (Read)
  Future<List<Order>> getAllOrders() async {
    final db = await database;
    final orderMaps = await db.query('orders', orderBy: 'order_date DESC');
    
    List<Order> orders = [];
    for (var map in orderMaps) {
      final items = await getOrderItems(map['id'] as int);
      orders.add(Order.fromMap(map, items));
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




}// DatabaseHelper 