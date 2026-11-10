import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'calculator_manager.dart';
import '../main.dart';
import '../models/order.dart';
import 'order_manager.dart';
import 'sync_dialog.dart';
import 'order_edit_screen.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});
  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  bool _isOrderMode = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Калькулятор скидок'),
        actions: [
          // Кнопка "Синхронизация / В заказ"
          ValueListenableBuilder<bool>(
            valueListenable: OrderManager.instance.isSyncedWithCalculator,
            builder: (context, isSynced, child) {
              if (isSynced) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: ActionChip(
                    avatar: const Icon(Icons.link, color: Colors.white, size: 16),
                    label: const Text('Заказ', style: TextStyle(color: Colors.white)),
                    backgroundColor: Colors.blue,
                    onPressed: () {
                      _syncCalcToOrder(); 
                      mainScreenTabNotifier.value = 2; 
                      
                      // --- ДОБАВИТЬ ПЕРЕХОД ---
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const OrderEditScreen()),
                      );
                    },
                  ),
                );
              }
              return IconButton(
                icon: Icon(
                  Icons.receipt_long,
                  color: _isOrderMode ? Colors.orange : Colors.blueGrey,
                ),
                tooltip: 'В заказ',
                onPressed: () => setState(() => _isOrderMode = !_isOrderMode),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.red),
            tooltip: 'Очистить всё',
            onPressed: () async {
              if (OrderManager.instance.isSyncedWithCalculator.value) {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Очистить всё?'),
                    content: const Text('Синхронизация с заказом будет разорвана, и все препараты будут удалены из заказа и калькулятора.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                      ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Очистить', style: TextStyle(color: Colors.red))),
                    ]
                  )
                );
                if (confirm == true) {
                   CalculatorManager.instance.clearAll();
                   OrderManager.instance.clearActiveOrder();
                }
              } else {
                CalculatorManager.instance.clearAll();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ValueListenableBuilder<List<CalcItem>>(
              valueListenable: CalculatorManager.instance.items,
              builder: (context, items, child) {
                if (items.isEmpty) {
                  return const Center(child: Text('Список пуст.\nДобавьте препараты из каталога.', textAlign: TextAlign.center));
                }

                double totalCost = 0;
                for (var item in items) {
                  totalCost += item.totalCost;
                }

                return Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          return _CalculatorItemCard(
                            key: ValueKey(items[index].productId), 
                            item: items[index],
                          );
                        },
                      ),
                    ),
                    _buildTotalPanel(totalCost),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _isOrderMode && CalculatorManager.instance.items.value.isNotEmpty
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.extended(
                heroTag: 'new_order',
                onPressed: () => _transferToOrder(context, isNew: true),
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('В новый заказ'),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              
              const SizedBox(height: 12),
              FloatingActionButton(
                heroTag: 'cancel',
                onPressed: () => setState(() => _isOrderMode = false),
                child: const Icon(Icons.close),
              ),
            ],
          )
        : null,
    );
  }

  Widget _buildTotalPanel(double totalCost) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: const Border(top: BorderSide(color: Colors.grey, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Итого к оплате:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text(
            '${totalCost.toStringAsFixed(2)} ₽',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.green.shade700),
          ),
        ],
      ),
    );
  }

  Future<void> _transferToOrder(BuildContext context, {required bool isNew}) async {
    final calcItems = CalculatorManager.instance.items.value;
    if (calcItems.isEmpty) return;

    if (isNew) {
      if (OrderManager.instance.activeOrder.value != null) {
        final replace = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Внимание'),
            content: const Text('У вас есть активный заказ. Заменить его новым?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Заменить')),
            ],
          )
        );
        if (replace != true) return;
      }
      
      OrderManager.instance.startNewOrder();
      OrderManager.instance.isSyncedWithCalculator.value = true;
      
      final newItems = calcItems.map((c) => OrderItem(
        productId: c.productId,
        productName: c.name,
        basePrice: c.basePrice,
        discountPercent: c.percent ?? 0.0,
        rate: c.rate,
        area: c.area,
        // packageVolume: 1.0,
        packageUnit: c.packageUnit,
      )).toList();
      
      OrderManager.instance.updateItems(newItems);
      CalculatorManager.instance.syncWithOrderItems(newItems);
      
      mainScreenTabNotifier.value = 2;
      setState(() => _isOrderMode = false);
      // --- ДОБАВИТЬ ПЕРЕХОД ---
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const OrderEditScreen()),
      );
    } else {
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
        mainScreenTabNotifier.value = 2;
        setState(() => _isOrderMode = false);
        // --- ДОБАВИТЬ ПЕРЕХОД ---
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const OrderEditScreen()),
        );
      }
    }
  }

  void _syncCalcToOrder() {
    if (!OrderManager.instance.isSyncedWithCalculator.value) return;
    
    final calcItems = CalculatorManager.instance.items.value;
    final order = OrderManager.instance.activeOrder.value;
    if (order == null) return;

    final List<OrderItem> newItems = calcItems.map((c) => OrderItem(
      productId: c.productId,
      productName: c.name,
      basePrice: c.basePrice,
      discountPercent: c.percent ?? 0.0,
      rate: c.rate,
      area: c.area,
      // packageVolume: 1.0,
      packageUnit: c.packageUnit,
    )).toList();

    OrderManager.instance.updateItems(newItems);
  }
}

class _CalculatorItemCard extends StatefulWidget {
  final CalcItem item;

  const _CalculatorItemCard({super.key, required this.item});

  @override
  State<_CalculatorItemCard> createState() => _CalculatorItemCardState();
}

class _CalculatorItemCardState extends State<_CalculatorItemCard> {
  late TextEditingController _percentCtrl, _rubCtrl, _finalCtrl, _rateCtrl, _areaCtrl;
  final FocusNode _percentFocus = FocusNode(), _rubFocus = FocusNode(), _finalFocus = FocusNode(), _rateFocus = FocusNode(), _areaFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    _percentCtrl = TextEditingController(text: _formatVal(widget.item.percent));
    _rubCtrl = TextEditingController(text: _formatVal(widget.item.rub));
    _finalCtrl = TextEditingController(text: _formatVal(widget.item.finalPrice));
    _rateCtrl = TextEditingController(text: _formatVal(widget.item.rate));
    _areaCtrl = TextEditingController(text: _formatVal(widget.item.area));
  }

  @override
  void didUpdateWidget(covariant _CalculatorItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_percentFocus.hasFocus) _percentCtrl.text = _formatVal(widget.item.percent);
    if (!_rubFocus.hasFocus) _rubCtrl.text = _formatVal(widget.item.rub);
    if (!_finalFocus.hasFocus) _finalCtrl.text = _formatVal(widget.item.finalPrice);
    if (!_rateFocus.hasFocus) _rateCtrl.text = _formatVal(widget.item.rate);
    if (!_areaFocus.hasFocus) _areaCtrl.text = _formatVal(widget.item.area);
  }

  String _formatVal(double? val) {
    if (val == null) return '';
    if (val == val.roundToDouble()) return val.toInt().toString();
    return val.toStringAsFixed(2).replaceAll('.', ',');
  }

  @override
  void dispose() {
    _percentCtrl.dispose(); _rubCtrl.dispose(); _finalCtrl.dispose(); _rateCtrl.dispose(); _areaCtrl.dispose();
    _percentFocus.dispose(); _rubFocus.dispose(); _finalFocus.dispose(); _rateFocus.dispose(); _areaFocus.dispose();
    super.dispose();
  }

    @override
    Widget build(BuildContext context) {
      final unit = widget.item.packageUnit;
      final base = widget.item.basePrice;
      final pricePerHaBase = base * widget.item.rate;

      // Проверяем, есть ли скидка, чтобы показать расчет за Га
      final hasDiscount = widget.item.percent != null && widget.item.percent! > 0;
      final finalUnitPrice = widget.item.finalPrice ?? base;
      final pricePerHaFinal = finalUnitPrice * widget.item.rate;

      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // СТРОКА 1: Название и Крестик (удалить)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.item.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => CalculatorManager.instance.removeItem(widget.item.productId),
                    padding: EdgeInsets.zero, constraints: const BoxConstraints(), visualDensity: VisualDensity.compact,
                  ),
                ],
              ),

              // СТРОКА 2: Базовая цена и Кнопка сброса
              Row(
                children: [
                  Text(
                    '${base.toStringAsFixed(2)} ₽/$unit',
                    style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.blueGrey),
                    tooltip: 'Сбросить',
                    onPressed: () => CalculatorManager.instance.resetItem(widget.item.productId),
                    padding: EdgeInsets.zero, constraints: const BoxConstraints(), visualDensity: VisualDensity.compact,
                  ),
                ],
              ),

              // СТРОКА 3: Цена за га (с учетом скидки)
              Text(
                hasDiscount
                    ? 'Цена за га: ${pricePerHaBase.toStringAsFixed(2)} ₽ ~ ${pricePerHaFinal.toStringAsFixed(2)} ₽'
                    : 'Цена за га: ${pricePerHaBase.toStringAsFixed(2)} ₽',
                style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
              ),

              const SizedBox(height: 12),

              // СТРОКА 4: Скидка (%, Руб, Итого) - без кнопки сброса
              Row(
                children: [
                  Expanded(child: TextField(controller: _percentCtrl, focusNode: _percentFocus, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))], decoration: const InputDecoration(labelText: '%', isDense: true, border: OutlineInputBorder()), onChanged: (v) => CalculatorManager.instance.updatePercent(widget.item.productId, v))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _rubCtrl, focusNode: _rubFocus, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))], decoration: const InputDecoration(labelText: 'Руб.', isDense: true, border: OutlineInputBorder()), onChanged: (v) => CalculatorManager.instance.updateRub(widget.item.productId, v))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _finalCtrl, focusNode: _finalFocus, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))], decoration: const InputDecoration(labelText: 'Итого', isDense: true, border: OutlineInputBorder()), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold), onChanged: (v) => CalculatorManager.instance.updateFinal(widget.item.productId, v))),
                ],
              ),

              const SizedBox(height: 12),

              // СТРОКА 5: Площадь и Норма
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _areaCtrl,
                      focusNode: _areaFocus,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      decoration: const InputDecoration(labelText: 'Площадь, га', isDense: true, border: OutlineInputBorder()),
                      onChanged: (v) => CalculatorManager.instance.updateArea(widget.item.productId, v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _rateCtrl,
                      focusNode: _rateFocus,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      decoration: InputDecoration(labelText: 'Норма, $unit/га', isDense: true, border: const OutlineInputBorder()),
                      onChanged: (v) => CalculatorManager.instance.updateRate(widget.item.productId, v),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // СТРОКА 6: Итоговый расчет
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Требуется: ${widget.item.requiredVolume.toStringAsFixed(2)} $unit',
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                  Text(
                    '${widget.item.totalCost.toStringAsFixed(2)} ₽',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
  }
}