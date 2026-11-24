// lib/screens/add_analog_dialog.dart
import 'dart:async';
import '../utils/app_logger.dart';
import '../utils/data_normalizer.dart';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/product.dart';
import 'analog_manager.dart';

class AddAnalogDialog extends StatefulWidget {
  const AddAnalogDialog({super.key});

  @override
  State<AddAnalogDialog> createState() => _AddAnalogDialogState();
}

class _AddAnalogDialogState extends State<AddAnalogDialog> {
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _searchCtrl = TextEditingController();
  List<Product> _searchResults = [];
  
  Timer? _debounce;
  int _ingredientsVersion = 0;

  String? _selectedProductId;
  final TextEditingController _nameCtrl = TextEditingController();
  String _selectedType = 'Фунгицид';
  List<AnalogIngredient> _ingredients = [AnalogIngredient()];
  final TextEditingController _rateCtrl = TextEditingController();
  String _rateUnit = 'л/га';

  // --- Подсказки ДВ ---
  List<String> _knownIngredients = [];
  List<String> _filteredSuggestions = [];
  int _focusedIngredientIndex = 0;

  List<String> _originalIngredientString = [];

    // Контроллеры для полей ДВ и концентрации
  final Map<int, TextEditingController> _nameCtrls = {};
  final Map<int, TextEditingController> _concCtrls = {};

  void _disposeIngredientControllers() {
    for (var c in _nameCtrls.values) { c.dispose(); }
    for (var c in _concCtrls.values) { c.dispose(); }
    _nameCtrls.clear();
    _concCtrls.clear();
  }

  final List<String> _types = ['Гербицид', 'Инсектицид', 'Фунгицид', 'Протравитель', 'Десикант', 'Спецпрепарат', 'Родентицид', 'Фумигант', 'Микроудобрение', 'Другое'];
  final List<String> _ingredientUnits = ['г/л', 'г/кг', '%', 'мл/л'];
  final List<String> _rateUnits = ['л/га', 'кг/га', 'л/т', 'кг/т'];

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  @override
  void dispose() {
    _disposeIngredientControllers();
    _debounce?.cancel();
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    try {
      final products = await DatabaseHelper.instance.getAllProducts();
      final Set<String> uniqueIngredients = {};
      for (var p in products) {
        final parsed = DataNormalizer.parseComposition(p.composition);
        for (var item in parsed) {
          final name = item['substance']?.trim() ?? '';
          if (name.isNotEmpty) uniqueIngredients.add(name);
        }
      }
      if (mounted) {
        setState(() {
          _knownIngredients = uniqueIngredients.toList()..sort();
        });
      }
    } catch (e, st) {
      AppLogger().e('Ошибка загрузки подсказок ДВ', error: e, stackTrace: st);
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      try {
        final all = await DatabaseHelper.instance.getAllProducts();
        if (!mounted) return;
        final q = query.toLowerCase();
        setState(() {
          _searchResults = all
              .where((p) => p.name.toLowerCase().contains(q))
              .take(5)
              .toList();
        });
      } catch (e, st) {
        AppLogger().e('Analog: ошибка поиска "$query"', error: e, stackTrace: st);
      }
    });
  }

  void _selectProduct(Product p) {
    setState(() {
      _disposeIngredientControllers(); // Очищаем старые контроллеры
      _selectedProductId = p.id.toString();
      _nameCtrl.text = p.name;
      
      final normalizedType = DataNormalizer.normalizeProductType(p.category);
      _selectedType = _types.contains(normalizedType) ? normalizedType : 'Другое';
      
      _ingredients.clear();
      if (p.composition != null && p.composition!.isNotEmpty) {
        final parsed = DataNormalizer.parseComposition(p.composition);
        for (var item in parsed) {
          final unit = item['unit'] ?? '';
          _ingredients.add(AnalogIngredient(
            name: item['substance'] ?? '',
            concentration: item['qty'] ?? '',
            unit: _ingredientUnits.contains(unit) ? unit : 'г/л',
          ));
        }
      }
      if (_ingredients.isEmpty) {
        _ingredients.add(AnalogIngredient());
      }

      if (p.consumptionRate != null) {
        final match = RegExp(r'([\d.,-]+)\s*(л/га|кг/га|л/т|кг/т)').firstMatch(p.consumptionRate!);
        if (match != null) {
          _rateCtrl.text = match.group(1) ?? '';
          _rateUnit = match.group(2) ?? 'л/га';
        } else {
           _rateCtrl.text = p.consumptionRate!;
        }
      }
      
      _searchResults = [];
      _searchCtrl.clear();
      _filteredSuggestions = []; // Сбрасываем подсказки

      _originalIngredientString = _ingredients.map((i) => '${i.name}_${i.concentration}_${i.unit}').toList();
      _ingredientsVersion++;
    });
  }

  void _onIngredientNameChanged(int index, String value) {
    _ingredients[index].name = value;
    _onIngredientChanged(); // Общая проверка на изменение состава

    // Фильтруем подсказки на основе введенного текста
    setState(() {
      _focusedIngredientIndex = index;
      if (value.trim().isEmpty) {
        _filteredSuggestions = [];
      } else {
        final q = value.toLowerCase();
        _filteredSuggestions = _knownIngredients
            .where((ing) => ing.toLowerCase().contains(q) && ing.toLowerCase() != q)
            .take(10)
            .toList();
      }
    });
  }

  void _onIngredientChanged() {
    final currentString = _ingredients.map((i) => '${i.name}_${i.concentration}_${i.unit}').toList();
    bool changed = false;
    
    if (currentString.length != _originalIngredientString.length) {
      changed = true;
    } else {
      for (int i = 0; i < currentString.length; i++) {
        if (currentString[i] != _originalIngredientString[i]) {
          changed = true;
          break;
        }
      }
    }

    if (changed && _selectedProductId != null) {
      _selectedProductId = null;
      _nameCtrl.clear(); 
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    String finalName = _nameCtrl.text.trim();
    if (finalName.isEmpty) {
      String baseType = _selectedType;
      if (baseType.endsWith('ы') || baseType.endsWith('и')) {
        baseType = baseType.substring(0, baseType.length - 1);
      }
      final count = AnalogManager.instance.targets.value.length + 1;
      finalName = '$baseType $count';
    }

    final target = AnalogTarget(
      originalProductId: _selectedProductId,
      name: finalName,
      type: _selectedType,
      ingredients: _ingredients.map((i) => i.copy()).toList(),
      rate: _rateCtrl.text.trim(),
      rateUnit: _rateUnit,
    );

    AnalogManager.instance.addTarget(target);
    Navigator.pop(context); 
  }

  @override
  Widget build(BuildContext context) {
    // ДЕЛАЕМ ОКНО ШИРЕ
    final screenWidth = MediaQuery.of(context).size.width;
    
    return AlertDialog(
      title: const Text('Добавить препарат', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      content: SizedBox(
        width: screenWidth * 0.9, // Ширина 90% экрана
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8), 
                
                TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Поиск по каталогу (необязательно)',
                    hintText: 'Введите название...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: _onSearchChanged,
                ),
                
                if (_searchResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      children: _searchResults.map((p) => ListTile(
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.category, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                            if (p.composition != null && p.composition!.isNotEmpty)
                              Text(
                                p.composition!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade400),
                              ),
                          ],
                        ),
                        dense: true,
                        onTap: () => _selectProduct(p),
                      )).toList(),
                    ),
                  ),

                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  value: _selectedType,
                  decoration: const InputDecoration(labelText: 'Тип препарата', border: OutlineInputBorder(), isDense: true),
                  items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setState(() => _selectedType = v!),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Название препарата (необязательно)', 
                    hintText: 'Оставьте пустым для автогенерации',
                    border: OutlineInputBorder(), 
                    isDense: true
                  ),
                ),
                const SizedBox(height: 16),
                
                const Text('Действующие вещества', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),

                // СПИСОК ДВ
                ..._ingredients.asMap().entries.map((entry) {
                  int idx = entry.key;
                  var ing = entry.value;
                  // Инициализируем контроллеры, если их еще нет
                  _nameCtrls.putIfAbsent(idx, () => TextEditingController(text: ing.name));
                  _concCtrls.putIfAbsent(idx, () => TextEditingController(text: ing.concentration));

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.grey.shade400),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // БЕЙДЖИ ПОДСКАЗОК (Показываются только для активного поля)
                          if (idx == _focusedIngredientIndex && _filteredSuggestions.isNotEmpty) ...[
                            SizedBox(
                              height: 36,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _filteredSuggestions.length,
                                itemBuilder: (ctx, i) {
                                  final s = _filteredSuggestions[i];
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: ActionChip(
                                      label: Text(s, style: const TextStyle(fontSize: 12)),
                                      onPressed: () {
                                        setState(() {
                                          _ingredients[idx].name = s;
                                          _nameCtrls[idx]!.text = s; // <-- Вставляем текст в контроллер                                  
                                          _filteredSuggestions = []; // Скрываем после выбора
                                        });
                                        _onIngredientChanged();
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],

                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  // Убрали Key и initialValue, используем controller
                                  controller: _nameCtrls[idx],
                                  decoration: const InputDecoration(
                                    labelText: 'Действующее вещество',
                                    border: UnderlineInputBorder(),
                                    isDense: true,
                                  ),
                                  onTap: () {
                                    setState(() {
                                      _focusedIngredientIndex = idx;
                                      _filteredSuggestions = [];
                                    });
                                  },
                                  onChanged: (v) => _onIngredientNameChanged(idx, v),
                                ),
                              ),
                              if (_ingredients.length > 1)
                                IconButton(
                                  icon: const Icon(Icons.remove_circle, color: Colors.red),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    setState(() {
                                      _ingredients.removeAt(idx);
                                      _disposeIngredientControllers(); // Удаляем контроллеры (сдвиг индексов)
                                      _ingredientsVersion++;
                                      _filteredSuggestions = [];
                                    });
                                    _onIngredientChanged();
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                flex: 1,
                                child: TextFormField(
                                  controller: _concCtrls[idx],
                                  decoration: const InputDecoration(
                                    labelText: 'Кол-во',
                                    border: UnderlineInputBorder(),
                                    isDense: true,
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  onChanged: (v) {
                                    ing.concentration = v;
                                    _onIngredientChanged();
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 1,
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey('ing_unit_${idx}_$_ingredientsVersion'),
                                  value: ing.unit,
                                  decoration: const InputDecoration(
                                    labelText: 'Ед. изм.',
                                    border: UnderlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: _ingredientUnits
                                      .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                                      .toList(),
                                  onChanged: (v) {
                                    ing.unit = v!;
                                    _onIngredientChanged();
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _ingredients.add(AnalogIngredient());
                      _ingredientsVersion++;
                      _focusedIngredientIndex = _ingredients.length - 1; // Фокус на новое поле
                      _filteredSuggestions = [];
                    });
                    _onIngredientChanged();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить вещество'),
                ),

                const SizedBox(height: 16),
                
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _rateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Норма расхода',
                          hintText: '0,5-1,0',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Укажите норму' : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: DropdownButtonFormField<String>(
                        value: _rateUnit,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        ),
                        items: _rateUnits.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                        onChanged: (v) => setState(() => _rateUnit = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 28),
              tooltip: 'Очистить',
              onPressed: () {
                setState(() {
                  _selectedProductId = null;
                  _searchCtrl.clear();
                  _searchResults = [];
                  _nameCtrl.clear();
                  _ingredients = [AnalogIngredient()];
                  _rateCtrl.clear();
                  _originalIngredientString = [];
                  _ingredientsVersion++;
                  _filteredSuggestions = [];
                });
              },
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey, size: 28),
                  tooltip: 'Отмена',
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.check_circle, color: Colors.green, size: 32),
                  tooltip: 'Подтвердить',
                  onPressed: _submit,
                ),
              ],
            )
          ],
        )
      ],
    );
  }
}