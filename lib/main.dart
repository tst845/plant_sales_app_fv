import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/order.dart'; 
import 'database/database_helper.dart';
import 'screens/catalog_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/calculator_screen.dart';
import 'screens/calculator_manager.dart';
import 'screens/order_manager.dart';
import 'screens/orders_screen.dart';
import 'services/share_intent_service.dart';
import 'services/file_format_detector.dart';
import 'services/order_import_service.dart';
import 'widgets/import_wizard_dialog.dart';

final ValueNotifier<int> mainScreenTabNotifier = ValueNotifier<int>(0);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Инициализация приема файлов
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
      setState(() {
        _selectedIndex = mainScreenTabNotifier.value;
      });
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
    
    // ПОДПИСКА НА ФАЙЛЫ
    _fileSubscription = ShareIntentService.instance.fileStream.listen((path) {
      _handleIncomingFile(path);
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
    
    String title = 'Получен файл';
    String description = 'Что вы хотите сделать с файлом?';
    
    if (format == FileFormat.catalog) {
      description = 'Файл похож на каталог препаратов. Импортировать его?';
    } else if (format == FileFormat.orders) {
      description = 'Файл похож на выгрузку заказов. Импортировать его?';
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: const Text('Отмена')
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              OrderImportService.importOrders(context, filePath: path); // Теперь работает
            },
            child: const Text('Заказы')
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => ImportWizardDialog(initialFilePath: path),
              );
            },
            child: const Text('Каталог препаратов')
          ),
        ],
      ),
    );
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