// lib/main.dart
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'dart:async';
import 'dart:io';                          

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database/database_helper.dart';
import 'models/order.dart';
import 'screens/calculator_manager.dart';
import 'screens/calculator_screen.dart';
import 'screens/catalog_screen.dart';
import 'screens/order_manager.dart';
import 'screens/orders_screen.dart';
import 'screens/settings_screen.dart';
import 'services/file_format_detector.dart';
import 'services/order_import_service.dart';
import 'services/share_intent_service.dart';
import 'widgets/import_wizard_dialog.dart';

final ValueNotifier<int> mainScreenTabNotifier = ValueNotifier<int>(0);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await ShareIntentService.instance.initialize();

  final prefs = await SharedPreferences.getInstance();
  bool isFirstRun = prefs.getBool('isFirstRun') ?? true;
  if (isFirstRun) {
    await DatabaseHelper.instance.insertSampleData();
    await prefs.setBool('isFirstRun', false);
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Plant Sales',
      builder: (context, child) {
        return MediaQuery.withClampedTextScaling(
          minScaleFactor: 1.0,
          maxScaleFactor: 1.3,
          child: child!,
        );
      },
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  StreamSubscription? _fileSubscription;
  int _selectedIndex = 0;
  late final List<Widget> _widgetOptions;

  void _tabListener() {
    if (mounted) {
      setState(() => _selectedIndex = mainScreenTabNotifier.value);
    }
  }

  @override
  void initState() {
    super.initState();
    _tabListener();
    mainScreenTabNotifier.addListener(_tabListener);
    _widgetOptions = <Widget>[
      const CatalogScreen(),
      const CalculatorScreen(),
      const OrdersScreen(),
      const SettingsScreen(),
    ];

    // 1) ГОРЯЧИЙ СТАРТ: приложение уже было открыто.
    _fileSubscription = ShareIntentService.instance.fileStream.listen(
      (path) {
        if (mounted) _handleIncomingFile(path);
      },
    );

    // 2) ХОЛОДНЫЙ СТАРТ: файл, полученный до старта приложения.
    //    Забираем его после первого кадра, чтобы был готов Navigator.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initial = ShareIntentService.instance.consumeInitialFile();
      if (initial != null && mounted) {
        _handleIncomingFile(initial);
      }
    });
  }

  @override
  void dispose() {
    mainScreenTabNotifier.removeListener(_tabListener);
    _fileSubscription?.cancel();
    super.dispose();
  }

  Future<void> _handleIncomingFile(String path) async {
    final format = await FileFormatDetector.detectFormat(path);
    if (!mounted) return;

    final fileName = path.split(Platform.pathSeparator).last;

    // Показываем пользователю только те варианты, которые соответствуют
    // распознанному формату. Это защищает и от путаницы,
    // и от попытки «импортировать заказы как каталог» (см. ниже).
    final canImportAsCatalog = format != FileFormat.orders;
    final canImportAsOrders  = format != FileFormat.catalog;

    String description;
    switch (format) {
      case FileFormat.catalog:
        description = 'Файл «$fileName» похож на каталог препаратов.';
        break;
      case FileFormat.orders:
        description = 'Файл «$fileName» похож на выгрузку заказов.';
        break;
      case FileFormat.unknown:
        description = 'Тип файла «$fileName» не удалось определить автоматически.';
        break;
    }

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Получен файл'),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Отмена'),
          ),
          if (canImportAsOrders)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'orders'),
              child: const Text('Импорт как заказы'),
            ),
          if (canImportAsCatalog)
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'catalog'),
              child: const Text('Импорт как каталог'),
            ),
        ],
      ),
    );

    if (!mounted || action == null) return;

    if (action == 'orders') {
      await OrderImportService.importOrders(context, filePath: path);
    } else if (action == 'catalog') {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => ImportWizardDialog(initialFilePath: path),
      );
    }
  }


  void _onItemTapped(int index) {
    mainScreenTabNotifier.value = index;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _widgetOptions,
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: <BottomNavigationBarItem>[
          const BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: 'Каталог',
          ),
          BottomNavigationBarItem(
            icon: ValueListenableBuilder<List<CalcItem>>(
              valueListenable: CalculatorManager.instance.items,
              builder: (context, items, child) {
                return Badge(
                  isLabelVisible: items.isNotEmpty,
                  label: Text('${items.length}'),
                  child: const Icon(Icons.calculate),
                );
              },
            ),
            label: 'Расчет',
          ),
          BottomNavigationBarItem(
            icon: ValueListenableBuilder<Order?>(
              valueListenable: OrderManager.instance.activeOrder,
              builder: (context, activeOrder, child) {
                return Badge(
                  isLabelVisible: activeOrder != null,
                  smallSize: 10,
                  backgroundColor: Colors.orange,
                  child: const Icon(Icons.receipt_long),
                );
              },
            ),
            label: 'Заказы',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Настройки',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.green.shade600,
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
      ),
    );
  }
}