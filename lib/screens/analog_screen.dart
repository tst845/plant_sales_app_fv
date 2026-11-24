// lib\screens\analog_screen.dart
import 'package:flutter/material.dart';
import 'analog_manager.dart';
import 'add_analog_dialog.dart';
import '../services/analog_service.dart';
import '../utils/app_logger.dart';
import '../database/database_helper.dart';
import '../models/order.dart';
import 'calculator_manager.dart';
import 'order_manager.dart';
import '../main.dart';
import '../models/product.dart';

class AnalogScreen extends StatefulWidget {
  const AnalogScreen({super.key});
  @override
  State<AnalogScreen> createState() => _AnalogScreenState();
}

class _AnalogScreenState extends State<AnalogScreen> {
  bool _isSearching = false;
  final List<AnalogSearchResult> _searchResults = [];

  // --- Состояние для множественного выбора ---
  bool _isSelectionMode = false;
  final Set<int> _selectedProductIds = {};
  // Храним измененные нормы (ID продукта -> Рекомендуемая норма)
  final Map<int, double> _customRates = {};

  void _toggleSelection(int? productId, {double? recommendedRate}) {
    if (productId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введенный вручную препарат нельзя добавить в заказ или калькулятор'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      if (_selectedProductIds.contains(productId)) {
        _selectedProductIds.remove(productId);
        _customRates.remove(productId);
        if (_selectedProductIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedProductIds.add(productId);
        if (recommendedRate != null) {
          _customRates[productId] = recommendedRate;
        }
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedProductIds.clear();
      _customRates.clear();
    });
  }

    Future<void> _addToCalculator() async {
    if (_selectedProductIds.isEmpty) return;
    
    final allProducts = await DatabaseHelper.instance.getAllProducts();
    if (!mounted) return; // <-- Защита от использования context после async

    int added = 0;
    int failed = 0;

    for (var id in _selectedProductIds) {
      final p = allProducts.firstWhere((element) => element.id == id, orElse: () => throw Exception('not found'));
      
      Product productToAdd = p;
      if (_customRates.containsKey(id)) {
        productToAdd = p.copyWith(consumptionRate: _customRates[id].toString());
      }

      if (CalculatorManager.instance.addProduct(productToAdd)) {
        added++;
      } else {
        failed++;
      }
    }

    _exitSelectionMode();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Добавлено в калькулятор: $added${failed > 0 ? ", пропущено: $failed" : ""}'),
        backgroundColor: added > 0 ? Colors.green : Colors.orange,
      ),
    );
  }

  Future<void> _addToOrder() async {
    if (_selectedProductIds.isEmpty) return;

    final allProducts = await DatabaseHelper.instance.getAllProducts();
    if (!mounted) return; // <-- Защита от использования context после async

    if (OrderManager.instance.activeOrder.value == null) {
      OrderManager.instance.startNewOrder();
    }
    final currentOrder = OrderManager.instance.activeOrder.value!;
    List<OrderItem> newItems = List.from(currentOrder.items);
    int added = 0;

    for (var id in _selectedProductIds) {
      final p = allProducts.firstWhere((element) => element.id == id);
      if (!newItems.any((item) => item.productId == id)) {
        
        double finalRate = 1.0;
        if (_customRates.containsKey(id)) {
          finalRate = _customRates[id]!;
        } else if (p.consumptionRate != null) {
          final match = RegExp(r'(\d+[.,]?\d*)').firstMatch(p.consumptionRate!);
          if (match != null) finalRate = double.tryParse(match.group(1)!.replaceAll(',', '.')) ?? 1.0;
        }

        String unit = 'л';
        if (p.package != null && p.package!.toLowerCase().contains('кг')) unit = 'кг';

        newItems.add(OrderItem(
          productId: p.id,
          productName: p.name,
          basePrice: p.price ?? 0.0,
          discountPercent: 0.0,
          rate: finalRate,
          area: 1.0,
          packageUnit: unit,
        ));
        added++;
      }
    }

    OrderManager.instance.updateItems(newItems);
    if (OrderManager.instance.isSyncedWithCalculator.value) {
      CalculatorManager.instance.syncWithOrderItems(newItems);
    }

    _exitSelectionMode();
    
    mainScreenTabNotifier.value = 2;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Добавлено в заказ: $added препаратов'), backgroundColor: Colors.green),
    );
  }

  Widget _buildResultCard(AnalogResult res) {
    final p = res.product;
    final isSelected = _selectedProductIds.contains(p.id);
    Color color;
    IconData icon;
    String title;

    switch (res.level) {
      case AnalogMatchLevel.full:
        color = Colors.green; icon = Icons.check_circle; title = 'Полный аналог';
        break;
      case AnalogMatchLevel.recalculate:
        color = Colors.orange; icon = Icons.sync_alt; title = 'Пересчёт нормы';
        break;
      case AnalogMatchLevel.partial:
        color = Colors.grey; icon = Icons.warning_amber_rounded; title = 'Частичное совпадение';
        break;
    }

    return GestureDetector(
      onLongPress: () {
        if (!_isSelectionMode) setState(() => _isSelectionMode = true);
        _toggleSelection(p.id, recommendedRate: res.recommendedRate);
      },
      onTap: _isSelectionMode ? () => _toggleSelection(p.id, recommendedRate: res.recommendedRate) : null,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        color: isSelected ? Colors.blue.shade50 : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isSelected ? BorderSide(color: Colors.blue.shade400, width: 2) : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_isSelectionMode && p.id != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Icon(isSelected ? Icons.check_circle : Icons.radio_button_unchecked, color: Colors.blue),
                    ),
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                  // Название препарата (слева)
                  Expanded(
                    child: Text(p.name, style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                  // Тип совпадения (справа)
                  Expanded(
                    child: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.right),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(p.manufacturer ?? 'Производитель не указан', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const Divider(),
              Text(p.composition ?? 'Состав не указан', style: const TextStyle(fontSize: 13)),
              
              // БЛОК ДЛЯ ПЕРЕСЧЁТА НОРМЫ (Пестициды)
              if (res.level == AnalogMatchLevel.recalculate && res.recommendedRate != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('📌 Рекомендуемая норма: ${res.recommendedRate!.toStringAsFixed(2).replaceAll('.', ',')} ${res.targetRateUnit}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                      if (res.rateMultiplier != null && res.rateMultiplier! != 1.0)
                        Text(
                          res.rateMultiplier! > 1 
                              ? 'Увеличить в ${res.rateMultiplier!.toStringAsFixed(1)} раза'
                              : 'Уменьшить в ${(1 / res.rateMultiplier!).toStringAsFixed(1)} раза',
                          style: const TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                    ],
                  ),
                ),
              ],

              // НОВЫЙ БЛОК ДЛЯ ЧАСТИЧНОГО СОВПАДЕНИЯ (Микроудобрения)
              if (res.level == AnalogMatchLevel.partial) ...[
                const SizedBox(height: 10),
                Text(
                  'Совпадают ДВ: ${res.matchingIngredients.join(", ")}',
                  style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
                ),
                // Если для этого частичного совпадения удалось рассчитать норму
                if (res.recommendedRate != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '📌 Норма для сохранения дозы "${res.matchingIngredients.first}": ${res.recommendedRate!.toStringAsFixed(2).replaceAll('.', ',')} ${res.targetRateUnit}',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13),
                        ),
                        if (res.rateMultiplier != null && res.rateMultiplier! != 1.0)
                          Text(
                            res.rateMultiplier! > 1 
                                ? 'Увеличить в ${res.rateMultiplier!.toStringAsFixed(1)} раза'
                                : 'Уменьшить в ${(1 / res.rateMultiplier!).toStringAsFixed(1)} раза',
                            style: const TextStyle(fontSize: 12, color: Colors.orange),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
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
        title: const Text('Подбор аналогов'),
        backgroundColor: Colors.white, // <-- Убедиться, что фон белый
        foregroundColor: Colors.black,
        titleTextStyle: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.w500),
        toolbarHeight: 56,
        leading: _isSelectionMode 
           ? IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: _exitSelectionMode,
          )
          : null,
      ),
      body: ValueListenableBuilder<List<AnalogTarget>>(
        valueListenable: AnalogManager.instance.targets,
        builder: (context, targets, child) {
          return Column(
            children: [
              if (!_isSelectionMode)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: targets.isEmpty ? null : () => _onPickAnalog(context),
                          icon: const Icon(Icons.search),
                          label: const Text('Подобрать'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 44)
                          )
                        )
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _showAddDialog(context), 
                          icon: const Icon(Icons.add), 
                          label: const Text('Добавить'), 
                          style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44))
                        )
                      ),
                      const SizedBox(width: 8),
                      // Кнопка "Очистить" стала квадратной иконкой
                      IconButton.filledTonal(
                        onPressed: targets.isEmpty ? null : () { 
                          AnalogManager.instance.clearAll(); 
                          setState(() => _searchResults.clear()); 
                        }, 
                        icon: const Icon(Icons.delete_sweep, color: Colors.red),
                        tooltip: 'Очистить всё',
                        style: IconButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          backgroundColor: Colors.red.withValues(alpha: 0.1),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!_isSelectionMode) const Divider(height: 1),
              
              Expanded(
                child: targets.isEmpty
                    ? _buildEmptyState()
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 100),
                        children: [
                          const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text('Добавленные препараты', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green))),
                          ...targets.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final t = entry.value;
                            final isSelected = t.originalProductId != null && _selectedProductIds.contains(int.tryParse(t.originalProductId!));
                            
                            return GestureDetector(
                              onLongPress: () {
                                if (!_isSelectionMode) setState(() => _isSelectionMode = true);
                                _toggleSelection(int.tryParse(t.originalProductId ?? ''));
                              },
                              onTap: _isSelectionMode ? () => _toggleSelection(int.tryParse(t.originalProductId ?? '')) : null,
                              child: Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                color: isSelected ? Colors.blue.shade50 : null,
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          if (_isSelectionMode && t.originalProductId != null)
                                            Padding(padding: const EdgeInsets.only(right: 8.0), child: Icon(isSelected ? Icons.check_circle : Icons.radio_button_unchecked, color: Colors.blue)),
                                          Expanded(child: Text(t.name.isEmpty ? 'Без названия' : t.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                                          if (!_isSelectionMode)
                                            IconButton(
                                              icon: const Icon(Icons.close, color: Colors.red), 
                                              visualDensity: VisualDensity.compact, 
                                              onPressed: () { 
                                                AnalogManager.instance.removeTarget(idx); 
                                                setState(() => _searchResults.clear()); // <-- ИСПРАВЛЕНО
                                              }
                                            ),
                                        ],
                                      ),
                                      Text('${t.type} | Норма: ${t.rate} ${t.rateUnit}', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                                      const SizedBox(height: 8),
                                      const Divider(height: 1),
                                      const SizedBox(height: 8),
                                      const Text('Состав:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                      const SizedBox(height: 4),
                                      ...t.ingredients.map((i) => Padding(padding: const EdgeInsets.only(bottom: 2.0), child: Text('• ${i.name} — ${i.concentration} ${i.unit}', style: const TextStyle(fontSize: 13)))),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),

                          if (_isSearching)
                            const Padding(padding: EdgeInsets.all(32.0), child: Center(child: CircularProgressIndicator()))
                                                    else if (_searchResults.isNotEmpty)
                            ..._searchResults.map((r) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                                    child: Text(
                                      'Аналоги для: ${r.target.name.isEmpty ? "Без названия" : r.target.name}',
                                      style: TextStyle(
                                        fontSize: 16, 
                                        fontWeight: FontWeight.bold, 
                                        color: Colors.blue.shade800
                                      ),
                                    ),
                                  ),
                                  if (r.hasMatches)
                                    ...r.matches.map((res) => _buildResultCard(res))
                                  else
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade50,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.orange.shade200),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                r.emptyReason ?? 'Аналогов не найдено',
                                                style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            }),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: _isSelectionMode 
        ? BottomAppBar(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(onPressed: _exitSelectionMode, child: const Text('Отмена')),
                ElevatedButton.icon(
                  onPressed: _selectedProductIds.isEmpty ? null : _addToCalculator,
                  icon: const Icon(Icons.calculate),
                  label: const Text('В калькулятор'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white),
                ),
                ElevatedButton.icon(
                  onPressed: _selectedProductIds.isEmpty ? null : _addToOrder,
                  icon: const Icon(Icons.shopping_cart),
                  label: const Text('В заказ'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                ),
              ],
            ),
          )
        : null,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_horiz, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('Нет препаратов для подбора', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Нажмите «Добавить», чтобы выбрать препарат из каталога или ввести его вручную.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => const AddAnalogDialog())
    .then((_) => setState(() => _searchResults.clear()));
  }

  Future<void> _onPickAnalog(BuildContext context) async {
    final targets = AnalogManager.instance.targets.value;
    if (targets.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchResults.clear();
    });

    try {
      final newResults = <AnalogSearchResult>[];
      for (var target in targets) {
        final result = await AnalogService.findAnalogs(target);
        newResults.add(result);
      }
      if (mounted) {
        setState(() {
          _searchResults.addAll(newResults);
          _isSearching = false;
        });
      }
    } catch (e, st) {
      AppLogger().e('Ошибка поиска аналогов', error: e, stackTrace: st);
      if (mounted) {
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }
}