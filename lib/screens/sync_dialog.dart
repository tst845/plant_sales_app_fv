import 'package:flutter/material.dart';
import '../models/order.dart';
import 'calculator_manager.dart';

class SyncDialog extends StatefulWidget {
  final List<CalcItem> calcItems;
  final List<OrderItem> orderItems;

  const SyncDialog({super.key, required this.calcItems, required this.orderItems});

  @override
  State<SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<SyncDialog> {
  // productId -> true (взять из калькулятора), false (взять из заказа)
  Map<int, bool> conflictChoices = {};
  // ID новых препаратов, которые пользователь хочет добавить
  Set<int> newItemsSelected = {};

  List<CalcItem> conflictsCalc = [];
  List<OrderItem> conflictsOrder = [];
  List<CalcItem> newCalcItems = [];

  @override
  void initState() {
    super.initState();
    
    final calcMap = {for (var c in widget.calcItems) c.productId: c};
    final orderMap = {for (var o in widget.orderItems) o.productId: o};

    for (var c in widget.calcItems) {
      if (orderMap.containsKey(c.productId)) {
        final o = orderMap[c.productId]!;
        // Проверяем, есть ли расхождения в площади, норме или скидке (допуск 0.01)
        bool isDifferent = (c.area - o.area).abs() > 0.01 ||
                           (c.rate - o.rate).abs() > 0.01 ||
                           ((c.percent ?? 0.0) - o.discountPercent).abs() > 0.01;
        if (isDifferent) {
          conflictsCalc.add(c);
          conflictsOrder.add(o);
          conflictChoices[c.productId] = true; // По умолчанию берем из калькулятора
        }
      } else {
        // Препарата нет в заказе (новый)
        newCalcItems.add(c);
        newItemsSelected.add(c.productId); // По умолчанию добавляем
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Синхронизация данных'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (conflictsCalc.isNotEmpty) ...[
                const Text('Найдены различия (Выберите приоритет):', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                const SizedBox(height: 8),
                ...List.generate(conflictsCalc.length, (index) {
                  final c = conflictsCalc[index];
                  final o = conflictsOrder[index];
                  final useCalc = conflictChoices[c.productId]!;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Калькулятор', style: TextStyle(fontWeight: useCalc ? FontWeight.bold : FontWeight.normal, color: useCalc ? Colors.green : Colors.grey)),
                              Switch(
                                value: useCalc,
                                activeColor: Colors.green,
                                onChanged: (val) => setState(() => conflictChoices[c.productId] = val),
                              ),
                              Text('Заказ', style: TextStyle(fontWeight: !useCalc ? FontWeight.bold : FontWeight.normal, color: !useCalc ? Colors.blue : Colors.grey)),
                            ],
                          ),
                          Text(
                            useCalc 
                              ? 'Площадь: ${c.area} га, Норма: ${c.rate}, Скидка: ${c.percent ?? 0}%'
                              : 'Площадь: ${o.area} га, Норма: ${o.rate}, Скидка: ${o.discountPercent}%',
                            style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                          )
                        ],
                      ),
                    ),
                  );
                }),
                const Divider(),
              ],
              if (newCalcItems.isNotEmpty) ...[
                const Text('Новые препараты (из калькулятора):', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                ...newCalcItems.map((c) => CheckboxListTile(
                  title: Text(c.name),
                  value: newItemsSelected.contains(c.productId),
                  onChanged: (val) {
                    setState(() {
                      if (val == true) newItemsSelected.add(c.productId);
                      else newItemsSelected.remove(c.productId);
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                )),
              ],
              if (conflictsCalc.isEmpty && newCalcItems.isEmpty)
                const Text('Списки уже идентичны.')
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () {
            List<OrderItem> merged = [];
            
            final calcIds = widget.calcItems.map((c) => c.productId).toSet();
            final conflictIds = conflictsCalc.map((c) => c.productId).toSet();
            
            // 1. Оставляем позиции из заказа, которых нет в калькуляторе
            for (var o in widget.orderItems) {
              if (!calcIds.contains(o.productId)) {
                merged.add(o);
              } else if (!conflictIds.contains(o.productId)) {
                merged.add(o); // Позиции без конфликтов оставляем как есть
              }
            }
            
            // 2. Применяем решения по конфликтам
            for (var c in conflictsCalc) {
              final o = conflictsOrder.firstWhere((el) => el.productId == c.productId);
              final useCalc = conflictChoices[c.productId]!;
              if (useCalc) {
                merged.add(_toOrderItem(c));
              } else {
                merged.add(o);
              }
            }
            
            // 3. Добавляем новые (отмеченные) позиции из калькулятора
            for (var c in newCalcItems) {
               if (newItemsSelected.contains(c.productId)) {
                 merged.add(_toOrderItem(c));
               }
            }
            
            Navigator.pop(context, merged);
          },
          child: const Text('Принять'),
        ),
      ],
    );
  }

  OrderItem _toOrderItem(CalcItem c) {
    return OrderItem(
      productId: c.productId,
      productName: c.name,
      basePrice: c.basePrice,
      discountPercent: c.percent ?? 0.0,
      rate: c.rate,
      area: c.area,
      packageVolume: c.packageVolume,
      packageUnit: c.packageUnit,
    );
  }
}