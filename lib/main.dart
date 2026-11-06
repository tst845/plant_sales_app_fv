import 'package:flutter/material.dart';
import 'screens/catalog_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/calculator_screen.dart';
import 'screens/calculator_manager.dart';
import 'screens/order_manager.dart';
import 'models/order.dart'; 
import 'screens/orders_screen.dart';



final ValueNotifier<int> mainScreenTabNotifier = ValueNotifier<int>(0);

void main() {
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
    mainScreenTabNotifier.addListener(_tabListener);
    _widgetOptions = <Widget>[
      const CatalogScreen(),    // Индекс 0
      const CalculatorScreen(), // Индекс 1
      const OrdersScreen(),     // Индекс 2
      const SettingsScreen(),   // Индекс 3
    ];
  }

  @override
  void dispose() {
    mainScreenTabNotifier.removeListener(_tabListener);
    super.dispose();
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
          // Вкладка "Заказы" с индикатором
          BottomNavigationBarItem(
            icon: ValueListenableBuilder<Order?>(
              valueListenable: OrderManager.instance.activeOrder,
              builder: (context, activeOrder, child) {
                return Badge(
                  isLabelVisible: activeOrder != null,
                  smallSize: 10, // Размер точки
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