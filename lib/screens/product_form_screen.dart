// lib/screens/product_form_screen.dart
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/product.dart';
import '../utils/data_normalizer.dart';

class ProductFormScreen extends StatefulWidget {
  final Product? product; // Если null - создание, иначе - редактирование

  const ProductFormScreen({super.key, this.product});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _manufacturerCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _descriptionCtrl;
  
  // Поля с единицами
  late TextEditingController _packageValueCtrl;
  String _packageUnit = 'л';
  
  late TextEditingController _rateValueCtrl;
  String _rateUnit = 'л/га';

  String _selectedCategory = 'Гербициды';
  
  // Списки для составных полей
  List<Map<String, String>> _compositionList = [];
  List<String> _culturesList = [];
  List<String> _diseasesList = [];

  final List<String> _categories = [
    'Гербициды', 'Инсектициды', 'Фунгициды', 'Протравители',
    'Десиканты', 'Спецпрепараты', 'Родентициды', 'Фумиганты',
    'Микроудобрения', 'Другое'
  ];

  final List<String> _packageUnits = ['л', 'мл', 'кг', 'г', 'шт', 'м'];
  final List<String> _rateUnits = ['л/га', 'кг/га', 'г/га', 'мл/га'];

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _manufacturerCtrl = TextEditingController(text: p?.manufacturer ?? '');
    _priceCtrl = TextEditingController(text: p?.price?.toString() ?? '');
    _descriptionCtrl = TextEditingController(text: p?.description ?? '');
    
    // Парсим упаковку (например, "10 л")
    _packageValueCtrl = TextEditingController();
    if (p?.package != null) {
      final parts = p!.package!.split(' ');
      if (parts.length >= 2) {
        _packageValueCtrl.text = parts[0];
        _packageUnit = parts[1];
      } else {
        _packageValueCtrl.text = p.package!;
      }
    }

    // Парсим норму расхода (например, "0,7-1,0 л/га")
    _rateValueCtrl = TextEditingController();
    if (p?.consumptionRate != null) {
      final rateStr = p!.consumptionRate!;
      // Ищем, есть ли в конце единица
      for (var unit in _rateUnits) {
        if (rateStr.endsWith(unit)) {
          _rateUnit = unit;
          _rateValueCtrl.text = rateStr.replaceAll(unit, '').trim();
          break;
        }
      }
      if (_rateValueCtrl.text.isEmpty) {
        _rateValueCtrl.text = rateStr;
      }
    }

    if (p?.category != null && _categories.contains(p!.category)) {
      _selectedCategory = p.category;
    }

    _compositionList = DataNormalizer.parseComposition(p?.composition);
    
    if (p?.cultures != null) {
      _culturesList = List<String>.from(p!.cultures);
    }
    if (p?.diseases != null) {
      _diseasesList = List<String>.from(p!.diseases);
    }
  }

  Future<void> _save() async {
    if (!mounted) return;

    // Мягкая проверка формы
    if (_formKey.currentState != null) {
      if (!_formKey.currentState!.validate()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Заполните обязательные поля'), backgroundColor: Colors.orange),
        );
        return;
      }
    } else {
      // Если форма не успела инициализироваться, проверяем хотя бы Название вручную
      debugPrint('[_save] WARNING: _formKey.currentState is null');
      if (_nameCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Введите название препарата'), backgroundColor: Colors.orange),
        );
        return;
      }
    }

    final compositionStr = DataNormalizer.normalizeComposition(_compositionList);
    final packageStr = '${_packageValueCtrl.text.trim()} $_packageUnit'.trim();
    final rateStr = DataNormalizer.normalizeRate(_rateValueCtrl.text, _rateUnit);

    final product = Product(
      id: widget.product?.id,
      name: _nameCtrl.text.trim(),
      category: _selectedCategory,
      composition: compositionStr.isEmpty ? null : compositionStr,
      manufacturer: _manufacturerCtrl.text.trim().isEmpty
          ? null
          : _manufacturerCtrl.text.trim(),
      package: _packageValueCtrl.text.trim().isEmpty ? null : packageStr,
      consumptionRate: _rateValueCtrl.text.trim().isEmpty ? null : rateStr,
      price: _priceCtrl.text.trim().isEmpty
          ? null
          : double.tryParse(_priceCtrl.text.replaceAll(',', '.')),
      description:
          _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim(),
      cultures: _culturesList,
      diseases: _diseasesList,
    );

    debugPrint('[_save] calling DB. isNew=${widget.product == null}');

    try {
      if (widget.product == null) {
        await DatabaseHelper.instance.insertProduct(product);
      } else {
        await DatabaseHelper.instance.updateProduct(product);
      }
      debugPrint('[_save] DB ok');
      if (mounted) Navigator.pop(context, true);
    } catch (e, st) {
      debugPrint('[_save] ERROR: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.product == null ? 'Новый препарат' : 'Редактирование'),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _save),
        ],
      ),
      body: SafeArea(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Название *', border: OutlineInputBorder()),
              validator: (v) => v == null || v.trim().isEmpty ? 'Обязательное поле' : null,
            ),
            const SizedBox(height: 16),
            
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: const InputDecoration(labelText: 'Категория *', border: OutlineInputBorder()),
              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => _selectedCategory = v!),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _manufacturerCtrl,
              decoration: const InputDecoration(labelText: 'Производитель', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),

            // Упаковка (Число + Единица)
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _packageValueCtrl,
                    decoration: const InputDecoration(labelText: 'Упаковка', border: OutlineInputBorder()),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String>(
                    value: _packageUnit,
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8)),
                    items: _packageUnits.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                    onChanged: (v) => setState(() => _packageUnit = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Норма расхода (Число + Единица)
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _rateValueCtrl,
                    decoration: const InputDecoration(labelText: 'Норма расхода', border: OutlineInputBorder(), hintText: '0,5-1,0'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String>(
                    value: _rateUnit,
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8)),
                    items: _rateUnits.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                    onChanged: (v) => setState(() => _rateUnit = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _priceCtrl,
              decoration: const InputDecoration(labelText: 'Цена, руб.', border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _descriptionCtrl,
              decoration: const InputDecoration(labelText: 'Описание', border: OutlineInputBorder()),
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // Кнопки открытия модальных окон
            _buildModalButton(
              label: 'Состав (${_compositionList.length})',
              icon: Icons.science,
              onTap: () async {
                final res = await _showCompositionDialog(context, _compositionList);
                if (res != null) setState(() => _compositionList = res);
              },
            ),
            const SizedBox(height: 8),
            _buildModalButton(
              label: 'Культуры (${_culturesList.length})',
              icon: Icons.grass,
              onTap: () async {
                final res = await _showTagsDialog(context, _culturesList, isCulture: true);
                if (res != null) setState(() => _culturesList = res);
              },
            ),
            const SizedBox(height: 8),
            _buildModalButton(
              label: 'Болезни (${_diseasesList.length})',
              icon: Icons.bug_report,
              onTap: () async {
                final res = await _showTagsDialog(context, _diseasesList, isCulture: false);
                if (res != null) setState(() => _diseasesList = res);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModalButton({required String label, required IconData icon, required VoidCallback onTap}) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.centerLeft,
      ),
    );
  }

  // ==========================================
  // ДИАЛОГ 1: СОСТАВ
  // ==========================================
  Future<List<Map<String, String>>?> _showCompositionDialog(BuildContext context, List<Map<String, String>> current) async {
    final List<Map<String, String>> tempList = current.map((e) => Map<String, String>.from(e)).toList();
    
    return showDialog<List<Map<String, String>>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('Состав препарата'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: tempList.length,
                itemBuilder: (ctx, i) {
                  final item = tempList[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          // 1-я строка: Вещество и кнопка удаления
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  initialValue: item['substance'],
                                  decoration: const InputDecoration(
                                    labelText: 'Действующее вещество',
                                    isDense: true,
                                  ),
                                  onChanged: (v) => item['substance'] = v,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle, color: Colors.red),
                                onPressed: () => setState(() => tempList.removeAt(i)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // 2-я строка: Количество и Единица
                          Row(
                            children: [
                              Expanded(
                                flex: 1,
                                child: TextFormField(
                                  initialValue: item['qty'],
                                  decoration: const InputDecoration(
                                    labelText: 'Кол-во',
                                    isDense: true,
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  onChanged: (v) => item['qty'] = v,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 1,
                                child: TextFormField(
                                  initialValue: item['unit'],
                                  decoration: const InputDecoration(
                                    labelText: 'Ед. изм.',
                                    hintText: 'г/л, г/кг...',
                                    isDense: true,
                                  ),
                                  onChanged: (v) => item['unit'] = v,
                                ),
                              ),
                              const SizedBox(width: 48), // Отступ, чтобы выровнять с верхней строкой
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => setState(() {
                  tempList.add({'substance': '', 'qty': '', 'unit': 'г/л'}); // Дефолтная единица
                }),
                child: const Text('+ Добавить строку'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, tempList),
                child: const Text('Сохранить'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ==========================================
  // ДИАЛОГ 2: ТЕГИ (Культуры и Болезни) с автодополнением
  // ==========================================
  Future<List<String>?> _showTagsDialog(
    BuildContext context,
    List<String> current, {
    required bool isCulture,
  }) async {
    final List<String> tempList = List.from(current);
    final TextEditingController inputCtrl = TextEditingController();

    // Загружаем справочники ОДИН РАЗ до показа диалога.
    final dbData = await DatabaseHelper.instance.getUniqueCulturesAndDiseases();
    final knownCultures = dbData['cultures'] ?? [];
    final knownDiseases = dbData['diseases'] ?? [];
    final suggestions = isCulture ? knownCultures : knownDiseases;

    if (!context.mounted) return null;

    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          String? feedback;   // текст-подсказка под полем ввода

          void addTag() {
            final text = inputCtrl.text.trim();
            if (text.isEmpty) {
              setState(() => feedback = 'Введите название');
              return;
            }

            final norm = DataNormalizer.normalizeCategoryNameSync(
              text,
              isCulture: isCulture,
              knownCultures: knownCultures,
              knownDiseases: knownDiseases,
            );

            if (norm.isEmpty) {
              setState(() =>
                  feedback = '«$text» не распознано как '
                      '${isCulture ? "культура" : "болезнь"}');
              return;
            }
            if (tempList.contains(norm)) {
              setState(() => feedback = '«$norm» уже есть в списке');
              return;
            }

            setState(() {
              tempList.add(norm);
              feedback = null;
            });
            inputCtrl.clear();
          }

          return AlertDialog(
            title: Text(isCulture ? 'Культуры' : 'Болезни'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: inputCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Введите название...',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => addTag(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        icon: const Icon(Icons.add),
                        onPressed: addTag,
                      ),
                    ],
                  ),
                  if (feedback != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        feedback!,
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                        ),
                      ),
                    ),

                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Подсказки из базы:',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 36,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: suggestions.length,
                        itemBuilder: (_, i) {
                          final s = suggestions[i];
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              label: Text(s, style: const TextStyle(fontSize: 12)),
                              onPressed: () {
                                inputCtrl.text = s;
                                addTag();
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('Добавленные:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),

                  if (tempList.isEmpty)
                    const Text('Пока ничего не добавлено',
                        style: TextStyle(color: Colors.grey))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: tempList
                          .map((tag) => Chip(
                                label: Text(tag),
                                onDeleted: () =>
                                    setState(() => tempList.remove(tag)),
                              ))
                          .toList(),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, tempList),
                child: const Text('Готово'),
              ),
            ],
          );
        },
      ),
    );
  }

}