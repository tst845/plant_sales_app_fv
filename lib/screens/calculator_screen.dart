import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'calculator_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:typed_data';
import '../models/product.dart';
import '../database/database_helper.dart';
import '../main.dart';
import '../models/order.dart';
import 'order_manager.dart';
import 'order_edit_screen.dart';
import 'sync_dialog.dart';


class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});
  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  // const CalculatorScreen({super.key});
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
                      // Просто переводим на вкладку заказов
                      mainScreenTabNotifier.value = 2; 
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
            icon: const Icon(Icons.download, color: Colors.green),
            tooltip: 'Экспорт в Excel',
            onPressed: () async {
              // (Код экспорта оставляем без изменений)
              // ... 
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16),
            child: ValueListenableBuilder<bool>(
              valueListenable: CalculatorManager.instance.isAreaMode,
              builder: (context, isArea, child) {
                return SegmentedButton<bool>(
                  segments: [
                    const ButtonSegment(
                      value: false, 
                      label: Text('За упаковку', style: TextStyle(fontSize: 13)), 
                      icon: Icon(Icons.inventory_2, size: 18)
                    ),
                    ButtonSegment(
                      value: true, 
                      label: const Text('На площадь', style: TextStyle(fontSize: 13)), 
                      icon: const Icon(Icons.grid_4x4, size: 18) // Иконка поля/сетки
                    ),
                  ],
                  selected: {isArea},
                  onSelectionChanged: (Set<bool> newSelection) {
                    CalculatorManager.instance.toggleMode(newSelection.first);
                  },
                );
              },
            ),
          ),

          Expanded(
            child: ValueListenableBuilder<List<CalcItem>>(
              valueListenable: CalculatorManager.instance.items,
              builder: (context, items, child) {
                if (items.isEmpty) {
                  return const Center(child: Text('Список пуст.\nДобавьте препараты из каталога.', textAlign: TextAlign.center));
                }

                return ValueListenableBuilder<bool>(
                  valueListenable: CalculatorManager.instance.isAreaMode,
                  builder: (context, isArea, child) {
                    double totalL = 0;
                    double totalKg = 0;
                    double totalCost = 0;

                    for (var item in items) {
                      if (isArea) {
                        // Считаем расход отдельно для Л и Кг
                        final vol = item.requiredVolume;
                        if (item.packageUnit == 'л') totalL += vol;
                        if (item.packageUnit == 'кг') totalKg += vol;
                        
                        totalCost += item.totalCost;
                      } else {
                        totalCost += item.finalPrice ?? item.basePrice;
                      }
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
                                isAreaMode: isArea,
                              );
                            },
                          ),
                        ),
                        _buildTotalPanel(totalL, totalKg, totalCost, isArea),
                      ],
                    );
                  },
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
              FloatingActionButton.extended(
                heroTag: 'active_order',
                onPressed: () => _transferToOrder(context, isNew: false),
                icon: const Icon(Icons.receipt_long),
                label: const Text('В активный заказ'),
                backgroundColor: Colors.blue,
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

  Widget _buildTotalPanel(double totalL, double totalKg, double totalCost, bool isArea) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: const Border(top: BorderSide(color: Colors.grey, width: 1)),
      ),
      child: Column(
        children: [
          if (isArea && (totalL > 0 || totalKg > 0)) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Общий расход:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(
                  [
                    if (totalL > 0) '${totalL.toStringAsFixed(2)} л',
                    if (totalKg > 0) '${totalKg.toStringAsFixed(2)} кг'
                  ].join(', '),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Итого к оплате:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(
                '${totalCost.toStringAsFixed(2)} ₽',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.green.shade700),
              ),
            ],
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
        packageVolume: c.packageVolume,
        packageUnit: c.packageUnit,
      )).toList();
      
      OrderManager.instance.updateItems(newItems);
      CalculatorManager.instance.syncWithOrderItems(newItems);
      
      mainScreenTabNotifier.value = 2; // Заказы
      setState(() => _isOrderMode = false);
    } else {
      // Синхронизация с активным заказом
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
        mainScreenTabNotifier.value = 2; // Заказы
        setState(() => _isOrderMode = false);
      }
    }
  }

  void _syncCalcToOrder() {
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
      packageVolume: c.packageVolume,
      packageUnit: c.packageUnit,
    )).toList();

    OrderManager.instance.updateItems(newItems);
  }

}

class _CalculatorItemCard extends StatefulWidget {
  final CalcItem item;
  final bool isAreaMode;

  const _CalculatorItemCard({super.key, required this.item, required this.isAreaMode});

  @override
  State<_CalculatorItemCard> createState() => _CalculatorItemCardState();
}

class _CalculatorItemCardState extends State<_CalculatorItemCard> {
  late TextEditingController _percentCtrl;
  late TextEditingController _rubCtrl;
  late TextEditingController _finalCtrl;
  late TextEditingController _rateCtrl;
  late TextEditingController _areaCtrl;

  final FocusNode _percentFocus = FocusNode();
  final FocusNode _rubFocus = FocusNode();
  final FocusNode _finalFocus = FocusNode();
  final FocusNode _rateFocus = FocusNode();
  final FocusNode _areaFocus = FocusNode();

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
    final effectiveBase = widget.item.getEffectiveBasePrice(widget.isAreaMode);
    final secondaryBase = widget.item.basePrice * widget.item.rate;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- СТРОКА 1: Название, Базовая цена, Крестик ---
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.item.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Text(
                  '${widget.item.basePrice.toStringAsFixed(2)} ₽', // Цена за упаковку без скидки
                  style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () => CalculatorManager.instance.removeItem(widget.item.productId),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(), visualDensity: VisualDensity.compact,
                ),
              ],
            ),

            // --- СТРОКА 2: Скидка, Цена со скидкой, Цена за Га ---
            Row(
              children: [
                if (widget.item.percent != null && widget.item.percent! > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Text(
                      'Скидка ${widget.item.percent!.toStringAsFixed(1)}%',
                      style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.normal),
                    ),
                  ),
                Text(
                  '~ ${effectiveBase.toStringAsFixed(2)} ₽', // Цена со скидкой
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.isAreaMode) ...[
                  const SizedBox(width: 8),
                  Text(
                    '(${secondaryBase.toStringAsFixed(2)} ₽/га)', // Цена за Га
                    style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
                  ),
                ],
              ],
            ),

            // --- СТРОКА 3: Поля ввода (Площадь и Норма) ---
            if (widget.isAreaMode) ...[
              const SizedBox(height: 12),
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
                      decoration: const InputDecoration(labelText: 'Норма, на га', isDense: true, border: OutlineInputBorder()),
                      onChanged: (v) => CalculatorManager.instance.updateRate(widget.item.productId, v),
                    ),
                  ),
                ],
              ),
            ],

            // --- СТРОКА 4: Итоговый расчет ---
            const SizedBox(height: 12),
            if (widget.isAreaMode)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Требуется: ${widget.item.requiredVolume.toStringAsFixed(2)} ${widget.item.packageUnit} (${widget.item.packagesCount} уп.)',
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                  Text(
                    '${widget.item.totalCost.toStringAsFixed(2)} ₽',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green),
                  ),
                ],
              )
            else
              // Поля ввода скидки (как было)
              Row(
                children: [
                  Expanded(child: TextField(controller: _percentCtrl, focusNode: _percentFocus, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))], decoration: const InputDecoration(labelText: '%', isDense: true, border: OutlineInputBorder()), onChanged: (v) => CalculatorManager.instance.updatePercent(widget.item.productId, v))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _rubCtrl, focusNode: _rubFocus, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))], decoration: const InputDecoration(labelText: 'Руб.', isDense: true, border: OutlineInputBorder()), onChanged: (v) => CalculatorManager.instance.updateRub(widget.item.productId, v))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _finalCtrl, focusNode: _finalFocus, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))], decoration: const InputDecoration(labelText: 'Итого', isDense: true, border: OutlineInputBorder()), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold), onChanged: (v) => CalculatorManager.instance.updateFinal(widget.item.productId, v))),
                  IconButton(icon: const Icon(Icons.refresh), onPressed: () => CalculatorManager.instance.resetItem(widget.item.productId), visualDensity: VisualDensity.compact),
                ],
              ),
          ],
        ),
      ),
    );
  }
}