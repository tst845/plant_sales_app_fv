// lib/screens/orders_screen.dart
import 'package:flutter/material.dart';
import '../models/order.dart';
import '../database/database_helper.dart';
import 'order_edit_screen.dart';
import 'order_manager.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<Order> _orders = [];
  bool _isLoading = true;
  String _sortBy = 'status_date'; // По умолчанию: Статус + Дата
  bool _sortAscending = true;
  // ВРЕМЕННЫЙ ФЛАГ ДЛЯ ДЕМО-ДАННЫХ
  // Когда заказы будут готовы, просто поменяйте на false
  final bool _useDemoData = false; 

  @override
  void initState() {
    super.initState();
    _loadOrders();
    // Слушаем изменения черновика
    OrderManager.instance.activeOrder.addListener(_onDraftChanged);
  }
  @override
  void dispose() {
    OrderManager.instance.activeOrder.removeListener(_onDraftChanged);
    super.dispose();
  }

  void _onDraftChanged() {
    if (mounted) setState(() {}); // Перерисовываем экран при изменении черновика
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    
    if (_useDemoData) {
      // Демо-данные с новыми полями
      await Future.delayed(const Duration(milliseconds: 300)); // Имитация загрузки
      setState(() {
        _orders = [
          Order(
            id: 1, 
            clientName: 'ООО "АгроПром"', 
            orderDate: DateTime(2026, 11, 1), 
            status: 'Новый', 
            items: [
              OrderItem(
                productId: 1, 
                productName: 'Абакус Ультра', 
                basePrice: 3000.0,
                discountPercent: 10.0,
                rate: 1.5,
                area: 10.0,
                packageVolume: 5.0,
                packageUnit: 'л',
              )
            ]
          ),
          Order(
            id: 2, 
            clientName: 'Иванов И.И.', 
            orderDate: DateTime(2026, 10, 28), 
            status: 'Выполнен', 
            items: [
              OrderItem(
                productId: 2, 
                productName: 'Абига-Пик', 
                basePrice: 1180.0,
                discountPercent: 5.0,
                rate: 2.0,
                area: 5.0,
                packageVolume: 5.0,
                packageUnit: 'л',
              )
            ]
          ),
        ];
        _isLoading = false;
      });
    } else {
      // Загрузка из БД
      final loaded = await DatabaseHelper.instance.getAllOrders();
      setState(() {
        _orders = loaded;
        _isLoading = false;
      });
    }
  }
  
  Color _getStatusColor(String status) {
    switch (status) {
      case 'Новый': return Colors.green.shade600;
      case 'В работе': return Colors.blue.shade600;
      case 'Выполнен': return  Colors.orange.shade700;
      case 'Отменен': return Colors.red.shade600;
      default: return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'Новый': return Icons.fiber_new; // Или Icons.receipt_long
      case 'В работе': return Icons.hourglass_top;
      case 'Выполнен': return Icons.check_circle;
      case 'Отменен': return Icons.cancel;
      default: return Icons.receipt_long;
    }
  }

    List<Order> get _sortedOrders {
    var list = List<Order>.from(_orders);
    
    // Функция для присвоения веса статусу
    int getStatusWeight(String status) {
      switch (status) {
        case 'Новый': return 1;
        case 'В работе': return 2;
        case 'Выполнен': return 3;
        case 'Отменен': return 4;
        default: return 5;
      }
    }

    list.sort((a, b) {
      int cmp = 0;
      if (_sortBy == 'name') {
        cmp = a.clientName.toLowerCase().compareTo(b.clientName.toLowerCase());
      } else if (_sortBy == 'price') {
        cmp = a.totalAmount.compareTo(b.totalAmount);
      } else if (_sortBy == 'date') {
        cmp = a.orderDate.compareTo(b.orderDate);
      } else if (_sortBy == 'status_date') {
        // 1. Сначала сортируем по статусу
        cmp = getStatusWeight(a.status).compareTo(getStatusWeight(b.status));
        // 2. Если статусы одинаковые, сортируем по дате
        if (cmp == 0) {
          cmp = a.orderDate.compareTo(b.orderDate);
        }
      }
      
      // Если сортировка по убыванию, инвертируем результат
      return _sortAscending ? cmp : -cmp;
    });
    
    return list;
  }
   
  void _showSortSheet() {
    String tempSortBy = _sortBy;
    bool tempAscending = _sortAscending;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Сортировка', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              
              const Text('Критерий:', style: TextStyle(color: Colors.grey)),
              
              RadioListTile<String>(
                title: const Text('По статусу и дате (по умолчанию)'),
                value: 'status_date',
                groupValue: tempSortBy,
                onChanged: (v) => setModalState(() => tempSortBy = v!),
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<String>(
                title: const Text('По дате (независимо от статуса)'),
                value: 'date',
                groupValue: tempSortBy,
                onChanged: (v) => setModalState(() => tempSortBy = v!),
                contentPadding: EdgeInsets.zero,
              ),
              const Divider(),
              RadioListTile<String>(
                title: const Text('По наименованию клиента'),
                value: 'name',
                groupValue: tempSortBy,
                onChanged: (v) => setModalState(() => tempSortBy = v!),
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<String>(
                title: const Text('По сумме заказа'),
                value: 'price',
                groupValue: tempSortBy,
                onChanged: (v) => setModalState(() => tempSortBy = v!),
                contentPadding: EdgeInsets.zero,
              ),
              
              const Divider(),
              SwitchListTile(
                title: Text(tempAscending ? 'По возрастанию (А-Я, 0-9)' : 'По убыванию (Я-А, 9-0)'),
                value: tempAscending, 
                onChanged: (v) => setModalState(() => tempAscending = v),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white),
                  onPressed: () {
                    setState(() {
                      _sortBy = tempSortBy;
                      _sortAscending = tempAscending;
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('Применить'),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Заказы'),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
          IconButton(icon: const Icon(Icons.filter_list), onPressed: () {}),
          IconButton(icon: const Icon(Icons.sort), onPressed: _showSortSheet),
          IconButton(icon: const Icon(Icons.download), onPressed: () {}),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ValueListenableBuilder(
              valueListenable: OrderManager.instance.activeOrder,
              builder: (context, activeOrder, child) {
                final hasDraft = activeOrder != null && activeOrder.id == null;

                if (_orders.isEmpty && !hasDraft) {
                  return const Center(
                    child: Text('Нет заказов.\nНажмите + чтобы создать.'),
                  );
                }

                final displayList = [
                  if (hasDraft) activeOrder,
                  ..._sortedOrders,
                ];

                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: displayList.length,
                  itemBuilder: (context, index) {
                    final order = displayList[index];
                    return _buildOrderCard(order, activeOrder);
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final res = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const OrderEditScreen()),
          );
          if (res == true) _loadOrders();
        },
        icon: const Icon(Icons.add),
        label: const Text('Новый заказ'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildOrderCard(Order order, Order? activeOrder) {
    final bool isDraft = order.id == null;
    // Активным считается заказ, который сейчас редактируется (совпадает ID)
    final bool isActive = activeOrder != null && activeOrder.id == order.id;
    // Подсвечиваем черновик или активный заказ
    final bool highlight = isDraft || isActive;

    final dateStr =
        '${order.orderDate.day}.${order.orderDate.month}.${order.orderDate.year}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: highlight ? Colors.blue.shade50 : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: highlight
            ? BorderSide(color: Colors.blue.shade300, width: 1.5)
            : BorderSide.none,
      ),
      child: ExpansionTile(
        // Заголовок карточки
        leading: CircleAvatar(
          backgroundColor: isDraft ? Colors.blue : _getStatusColor(order.status),
          child: Icon(
            isDraft ? Icons.edit_document : _getStatusIcon(order.status),
            color: Colors.white,
          ),
        ),
        title: Text(
          isDraft
              ? 'Черновик (${order.clientName.isEmpty ? "Без имени" : order.clientName})'
              : order.clientName,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDraft ? Colors.blue.shade900 : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('от $dateStr'),
            Text('Позиций: ${order.items.length}'),
          ],
        ),
        // Содержимое при раскрытии
        children: [
          const Divider(height: 1),
          // Список позиций заказа
          if (order.items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Заказ пуст'),
            )
          else
            ...order.items.map((item) => ListTile(
                  dense: true,
                  title: Text(item.productName),
                  subtitle: Text(
                    'Норма: ${item.rate} | Площадь: ${item.area} га',
                  ),
                  trailing: Text(
                    '${item.totalPrice.toStringAsFixed(2)} ₽',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                )),
          // Кнопки действий
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Кнопка удаления (доступна для черновика и для сохранённых)
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  tooltip: 'Удалить',
                  onPressed: () => _confirmDeleteOrder(order),
                ),
                const SizedBox(width: 8),
                // Кнопка редактирования
                ElevatedButton.icon(
                  icon: const Icon(Icons.edit),
                  label: const Text('Редактировать'),
                  onPressed: () async {
                    // Устанавливаем заказ как активный, чтобы он подсветился
                    OrderManager.instance.setActiveOrder(order);
                    final res = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => OrderEditScreen(order: isDraft ? null : order),
                      ),
                    );
                    if (res == true) _loadOrders();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Метод подтверждения удаления
  Future<void> _confirmDeleteOrder(Order order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удаление заказа'),
        content: Text(
          order.id == null
              ? 'Удалить черновик?'
              : 'Вы уверены, что хотите удалить заказ №${order.id}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (order.id == null) {
      // Удаление черновика
      OrderManager.instance.clearActiveOrder();
    } else {
      // Удаление сохранённого заказа
      await DatabaseHelper.instance.deleteOrder(order.id!);
    }
    _loadOrders();
  }
}