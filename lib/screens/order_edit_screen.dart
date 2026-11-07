// lib/screens/order_edit_screen.dart
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../main.dart';
import 'order_manager.dart';
import 'calculator_manager.dart';
import 'sync_dialog.dart';
import 'catalog_screen.dart';

class OrderEditScreen extends StatefulWidget {
  final Order? order;

  const OrderEditScreen({super.key, this.order});

  @override
  State<OrderEditScreen> createState() => _OrderEditScreenState();
}

class _OrderEditScreenState extends State<OrderEditScreen> {
  final _clientCtrl = TextEditingController();
  final _shipmentCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  
  DateTime _orderDate = DateTime.now();
  String _status = 'Новый';

  // Геттер для быстрого доступа к текущим препаратам из менеджера
  List<OrderItem> get currentItems => OrderManager.instance.activeOrder.value?.items ?? [];

  @override
  void initState() {
    super.initState();
    
    // Если мы редактируем существующий заказ (передали из списка)
    if (widget.order != null) {
      final orderToEdit = widget.order!;
      _clientCtrl.text = orderToEdit.clientName;
      _orderDate = orderToEdit.orderDate;
      _status = orderToEdit.status;
      _notesCtrl.text = orderToEdit.notes ?? '';
      _shipmentCtrl.text = '${_orderDate.day}.${_orderDate.month}.${_orderDate.year}';
      OrderManager.instance.setActiveOrder(orderToEdit);
    } 
    // Если создаем НОВЫЙ заказ
    else {
      final draft = OrderManager.instance.activeOrder.value;
      
      // Если есть сохраненный черновик (у него нет ID), загружаем его. 
      if (draft != null && draft.id == null) {
        _clientCtrl.text = draft.clientName;
        _orderDate = draft.orderDate;
        _status = draft.status;
        _notesCtrl.text = draft.notes ?? '';
        _shipmentCtrl.text = '${_orderDate.day}.${_orderDate.month}.${_orderDate.year}';
      } else {
        OrderManager.instance.startNewOrder();
        _shipmentCtrl.text = '${_orderDate.day}.${_orderDate.month}.${_orderDate.year}';
      }
    }

    OrderManager.instance.activeOrder.addListener(_onOrderUpdated);
  }

  void _onOrderUpdated() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    OrderManager.instance.activeOrder.removeListener(_onOrderUpdated);
    _clientCtrl.dispose();
    _shipmentCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_clientCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Укажите имя или компанию')));
      return;
    }

    final newOrder = Order(
      id: widget.order?.id ?? OrderManager.instance.activeOrder.value?.id,
      clientName: _clientCtrl.text.trim(),
      orderDate: _orderDate,
      status: _status,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      items: currentItems, // Берем данные напрямую из менеджера
    );

    try {
      if (newOrder.id == null) {
        await DatabaseHelper.instance.insertOrder(newOrder);
      } else {
        await DatabaseHelper.instance.updateOrder(newOrder);
      }

      final wasSynced = OrderManager.instance.isSyncedWithCalculator.value;
      OrderManager.instance.clearActiveOrder();
      if (wasSynced) CalculatorManager.instance.clearAll(); // Очищаем черновик
      
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
    }
  }

  final List<String> _statuses = ['Новый', 'В работе', 'Выполнен', 'Отменен'];

  void _toggleStatus() {
    setState(() {
      int currentIndex = _statuses.indexOf(_status);
      if (currentIndex == -1) currentIndex = 0;
      _status = _statuses[(currentIndex + 1) % _statuses.length];
    });
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Новый': return Colors.blue.shade700;
      case 'В работе': return Colors.orange.shade800;
      case 'Выполнен': return Colors.green.shade700;
      case 'Отменен': return Colors.red.shade700;
      default: return Colors.grey;
    }
  }

  Future<void> _addFromCatalog() async {
    // 1. Открываем каталог в режиме выбора. Он вернет List<Product>
    final List<Product>? selectedProducts = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CatalogScreen(isOrderSelectionMode: true),
      ),
    );

    if (selectedProducts == null || selectedProducts.isEmpty) return;

    final currentList = currentItems;
    final List<OrderItem> newList = List.from(currentList);
    final List<String> skippedNames = [];

    // 2. Проходим по выбранным продуктам
    for (var p in selectedProducts) {
      final exists = currentList.any((item) => item.productId == p.id);
      
      if (exists) {
        // Вариант А: Препарат уже есть, запоминаем имя для уведомления
        skippedNames.add(p.name);
      } else {
        // Парсим норму расхода
        double rate = 1.0;
        if (p.consumptionRate != null && p.consumptionRate!.isNotEmpty) {
          final match = RegExp(r'(\d+[.,]?\d*)').firstMatch(p.consumptionRate!);
          if (match != null) {
            rate = double.tryParse(match.group(1)!.replaceAll(',', '.')) ?? 1.0;
          }
        }

        // Парсим упаковку
        double packageVolume = 1.0;
        String packageUnit = 'ед.';
        if (p.package != null && p.package!.isNotEmpty) {
          final matchVol = RegExp(r'(\d+([.,]\d+)?)').firstMatch(p.package!);
          if (matchVol != null) {
            packageVolume = double.tryParse(matchVol.group(1)!.replaceAll(',', '.')) ?? 1.0;
          }
          final lower = p.package!.toLowerCase();
          if (lower.contains('мл')) {
            packageUnit = 'мл';
          } else if (lower.contains('кг')) {
            packageUnit = 'кг';
          } else if (lower.contains('г')) {
            packageUnit = 'г';
          } else if (lower.contains('л')) {
            packageUnit = 'л';
          }
        }

        // Создаем новый OrderItem и добавляем
        newList.add(OrderItem(
          productId: p.id,
          productName: p.name,
          basePrice: p.price ?? 0.0,
          discountPercent: 0.0,
          rate: rate,
          area: 1.0, // По умолчанию 1 га
          packageVolume: packageVolume,
          packageUnit: packageUnit,
        ));
      }
    }

    // 3. Обновляем данные в менеджере
    if (newList.length > currentList.length) {
      OrderManager.instance.updateItems(newList);
      
      // Синхронизируем с калькулятором, если включено
      if (OrderManager.instance.isSyncedWithCalculator.value) {
        CalculatorManager.instance.syncWithOrderItems(newList);
      }
      setState(() {}); // Перерисовываем экран
    }

    // 4. Выводим сообщение, если были пропущены дубликаты
    if (skippedNames.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Уже есть в заказе: ${skippedNames.join(", ")}'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _addFromCalculator() async {
    final calcItems = CalculatorManager.instance.items.value;
    if (calcItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('В калькуляторе нет препаратов')));
      return;
    }

    final order = OrderManager.instance.activeOrder.value;
    if (order == null) return;

    final mergedItems = await showDialog<List<OrderItem>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SyncDialog(calcItems: calcItems, orderItems: order.items),
    );

    if (mergedItems != null) {
      OrderManager.instance.updateItems(mergedItems);
      CalculatorManager.instance.syncWithOrderItems(mergedItems);
      OrderManager.instance.isSyncedWithCalculator.value = true;
      setState(() {}); // Обновляем UI
    }
  }

  Future<void> _loadToCalculator() async {
    if (currentItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Список препаратов заказа пуст')));
      return;
    }

    CalculatorManager.instance.syncWithOrderItems(currentItems);
    OrderManager.instance.isSyncedWithCalculator.value = true;
    
    if (mounted) {
      // 1. Переключаем вкладку (убедитесь, что индекс верный)
      mainScreenTabNotifier.value = 1; // Переход на вкладку калькулятора
      // 2. Закрываем экран редактирования заказа, чтобы показать главный экран
      Navigator.popUntil(context, (route) => route.isFirst); 
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.order == null ? 'Новый заказ' : 'Редактирование'),
        actions: [
          if (widget.order != null || OrderManager.instance.activeOrder.value?.id != null)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                showDialog(context: context, builder: (ctx) => AlertDialog(
                  title: const Text('Удалить заказ?'),
                  content: const Text('Все позиции этого заказа также будут удалены.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final orderId = widget.order?.id ?? OrderManager.instance.activeOrder.value?.id;
                        if (orderId != null) {
                          await DatabaseHelper.instance.deleteOrder(orderId);
                        }
                        OrderManager.instance.clearActiveOrder();
                        if (mounted) Navigator.pop(context, true);
                      },
                      child: const Text('Удалить', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ));
              },
            ),
          IconButton(icon: const Icon(Icons.check), onPressed: _save),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8.0),
                child: Text('Информация о клиенте', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
              ),
              ActionChip(
                label: Text(_status, style: TextStyle(color: _getStatusColor(_status), fontWeight: FontWeight.bold, fontSize: 13)),
                backgroundColor: _getStatusColor(_status).withOpacity(0.1),
                side: BorderSide(color: _getStatusColor(_status)),
                onPressed: _toggleStatus,
              ),
            ],
          ),
          TextFormField(
            controller: _clientCtrl,
            decoration: const InputDecoration(labelText: 'Имя или Название компании *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _shipmentCtrl,
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'Дата заказа',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.calendar_today),
              hintText: '${_orderDate.day}.${_orderDate.month}.${_orderDate.year}',
            ),
            onTap: () async {
              final date = await showDatePicker(context: context, initialDate: _orderDate, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
              if (date != null) {
                setState(() {
                  _orderDate = date;
                  _shipmentCtrl.text = '${date.day}.${date.month}.${date.year}';
                });
              }
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notesCtrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Примечание', border: OutlineInputBorder(), alignLabelWithHint: true),
          ),
          
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionTitle('Препараты (${currentItems.length})'),
              ValueListenableBuilder<bool>(
                valueListenable: OrderManager.instance.isSyncedWithCalculator,
                builder: (context, isSynced, child) {
                  if (!isSynced) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200)
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.link, size: 14, color: Colors.blue.shade700),
                        const SizedBox(width: 4),
                        Text('Синхр. с калькулятором', style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                      ],
                    ),
                  );
                }
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: _addFromCatalog,
                icon: const Icon(Icons.list_alt),
                label: const Text('Из каталога'),
              ),
              ElevatedButton.icon(
                onPressed: _addFromCalculator,
                icon: const Icon(Icons.calculate),
                label: const Text('Из калькулятора'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              ),
              ElevatedButton.icon(
                onPressed: _loadToCalculator,
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('Рассчитать'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          if (currentItems.isEmpty)
            const Center(child: Text('Список препаратов пуст', style: TextStyle(color: Colors.grey)))
          else
            ...currentItems.asMap().entries.map((entry) {
              int idx = entry.key;
              var orderItem = entry.value;
              return _OrderItemCard(
                key: ValueKey('${orderItem.productId}_$idx'),
                item: orderItem,
                onChanged: (updatedItem) {
                   var newList = List<OrderItem>.from(currentItems);
                   newList[idx] = updatedItem;
                   OrderManager.instance.updateItems(newList);
                   if (OrderManager.instance.isSyncedWithCalculator.value) {
                      CalculatorManager.instance.syncWithOrderItems(newList);
                    }
                },
                onDelete: () {
                   var newList = List<OrderItem>.from(currentItems);
                   newList.removeAt(idx);
                   OrderManager.instance.updateItems(newList);
                   if (OrderManager.instance.isSyncedWithCalculator.value) {
                      CalculatorManager.instance.syncWithOrderItems(newList);
                    }
                },
              );
            }),
        ],
      ),
      bottomNavigationBar: _buildBottomPanel(),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
    );
  }

  Widget _buildBottomPanel() {
    double total = 0;
    for (var item in currentItems) {
      total += item.totalPrice; // Используем геттер из модели
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.grey.shade100, border: const Border(top: BorderSide(color: Colors.grey, width: 1))),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Итого к оплате:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text('${total.toStringAsFixed(2)} ₽', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
          ],
        ),
      ),
    );
  }
}

// --- КАРТОЧКА ПРЕПАРАТА ---
class _OrderItemCard extends StatefulWidget {
  final OrderItem item;
  final Function(OrderItem) onChanged;
  final VoidCallback onDelete;

  const _OrderItemCard({super.key, required this.item, required this.onChanged, required this.onDelete});

  @override
  State<_OrderItemCard> createState() => _OrderItemCardState();
}

class _OrderItemCardState extends State<_OrderItemCard> {
    late TextEditingController _areaCtrl;
  late TextEditingController _rateCtrl;
  
  final FocusNode _areaFocus = FocusNode();
  final FocusNode _rateFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Инициализируем только контроллеры площади и нормы
    _areaCtrl = TextEditingController(text: widget.item.area.toString().replaceAll('.', ','));
    _rateCtrl = TextEditingController(text: widget.item.rate.toString().replaceAll('.', ','));
  }
  
  @override
  void didUpdateWidget(covariant _OrderItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_areaFocus.hasFocus) {
      _areaCtrl.text = widget.item.area.toString().replaceAll('.', ',');
    }
    if (!_rateFocus.hasFocus) {
      _rateCtrl.text = widget.item.rate.toString().replaceAll('.', ',');
    }
  }

  @override
  void dispose() {
    _areaCtrl.dispose();
    _rateCtrl.dispose();
    _areaFocus.dispose();
    _rateFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double discountedPrice = widget.item.discountedPrice;
    final double requiredVolume = widget.item.requiredVolume;
    final int packagesCount = widget.item.packagesCount;
    final double totalCost = widget.item.totalPrice;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(widget.item.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green))),
                IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: widget.onDelete, visualDensity: VisualDensity.compact),
              ],
            ),
            const Divider(),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text('Цена: ${widget.item.basePrice.toStringAsFixed(2)} ₽', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                if (widget.item.discountPercent > 0) 
                  Text('Скидка: -${widget.item.discountPercent.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 13, color: Colors.red)),
                Text('Со скидкой: ${discountedPrice.toStringAsFixed(2)} ₽', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _areaCtrl,
                    focusNode: _areaFocus,
                    decoration: const InputDecoration(labelText: 'Площадь, га', isDense: true, border: OutlineInputBorder()),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (val) {
                      final newArea = double.tryParse(val.replaceAll(',', '.')) ?? 0.0;
                      // Создаем НОВЫЙ объект, так как поля final
                      widget.onChanged(OrderItem(
                         id: widget.item.id,
                         productId: widget.item.productId,
                         productName: widget.item.productName,
                         basePrice: widget.item.basePrice,
                         discountPercent: widget.item.discountPercent,
                         rate: widget.item.rate,
                         area: newArea,
                         packageVolume: widget.item.packageVolume,
                         packageUnit: widget.item.packageUnit,
                      ));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _rateCtrl,
                    focusNode: _rateFocus,
                    decoration: const InputDecoration(labelText: 'Норма, на га', isDense: true, border: OutlineInputBorder()),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (val) {
                      final newRate = double.tryParse(val.replaceAll(',', '.')) ?? 0.0;
                      widget.onChanged(OrderItem(
                         id: widget.item.id,
                         productId: widget.item.productId,
                         productName: widget.item.productName,
                         basePrice: widget.item.basePrice,
                         discountPercent: widget.item.discountPercent,
                         rate: newRate,
                         area: widget.item.area,
                         packageVolume: widget.item.packageVolume,
                         packageUnit: widget.item.packageUnit,
                      ));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Требуется:', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                      Text('${requiredVolume.toStringAsFixed(2)} ${widget.item.packageUnit}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text('($packagesCount упак.)', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Стоимость:', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                      Text('${totalCost.toStringAsFixed(2)} ₽', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}