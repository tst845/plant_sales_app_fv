// lib/screens/catalog_screen.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/services.dart';
import '../database/database_helper.dart';
import 'product_form_screen.dart';
import 'calculator_manager.dart';
import 'order_manager.dart';
import 'order_edit_screen.dart';
import '../services/filter_manager.dart';
import '../models/product.dart';
import '../models/order.dart';
import '../main.dart';

class CatalogFilter {
  Set<String> categories = {};
  Set<String> cultures = {};
  Set<String> diseases = {};
  double? minPrice;
  double? maxPrice;
  String sortBy = 'name';
  bool sortAscending = true;
  bool sortByCalculator = false; // НОВОЕ: Сортировка по калькулятору

  bool get hasActiveFilters =>
      categories.isNotEmpty || cultures.isNotEmpty || diseases.isNotEmpty || minPrice != null || maxPrice != null;

  void reset() {
    categories.clear();
    cultures.clear();
    diseases.clear();
    minPrice = null;
    maxPrice = null;
    sortBy = 'name';
    sortAscending = true;
    sortByCalculator = false;
  }

    List<Product> apply(List<Product> input, String query) {
    var result = input;

    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      result = result.where((p) =>
        p.name.toLowerCase().contains(q) ||
        (p.composition?.toLowerCase().contains(q) ?? false) ||
        p.cultures.any((c) => c.toLowerCase().contains(q)) || // <-- Ищем в списке
        p.diseases.any((d) => d.toLowerCase().contains(q))    // <-- Ищем в списке
      ).toList();
    }

    if (categories.isNotEmpty) result = result.where((p) => categories.contains(p.category)).toList();
    
    if (cultures.isNotEmpty) {
      result = result.where((p) {
        // Больше не нужен split, просто проверяем пересечение множеств
        return p.cultures.map((e) => e.trim()).toSet().intersection(cultures).isNotEmpty;
      }).toList();
    }

    if (diseases.isNotEmpty) {
      result = result.where((p) {
        return p.diseases.map((e) => e.trim()).toSet().intersection(diseases).isNotEmpty;
      }).toList();
    }

    if (minPrice != null) result = result.where((p) => p.price != null && p.price! >= minPrice!).toList();
    if (maxPrice != null) result = result.where((p) => p.price != null && p.price! <= maxPrice!).toList();

    result.sort((a, b) {
      // 1. Сначала сортируем по калькулятору (если включено)
      if (sortByCalculator) {
        final inA = CalculatorManager.instance.items.value.any((e) => e.productId == a.id);
        final inB = CalculatorManager.instance.items.value.any((e) => e.productId == b.id);
        if (inA && !inB) return -1;
        if (!inA && inB) return 1;
      }

      // 2. Затем стандартная сортировка (по имени или цене)
      int cmp = 0;
      if (sortBy == 'name') {
        cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      } else if (sortBy == 'price') {
        cmp = (a.price ?? 0.0).compareTo(b.price ?? 0.0);
      }
      return sortAscending ? cmp : -cmp;
    });

    return result;
  }
}

class CatalogScreen extends StatefulWidget {
  final bool isOrderSelectionMode; // Флаг режима выбора для заказа

  const CatalogScreen({super.key, this.isOrderSelectionMode = false});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}


class _CatalogScreenState extends State<CatalogScreen> {
  List<Product> _products = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedCategory;
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();
  final CatalogFilter _filter = CatalogFilter();
    // Множество для хранения ID выбранных препаратов
  final Set<int> _selectedProductIds = {};
  List<String> _categories = [];
  List<String> _availableCultures = [];
  List<String> _availableDiseases = [];

  bool _isSelectionMode = false;
  bool _isSelectionConfirmed = false; // <-- НОВАЯ ПЕРЕМЕННАЯ (Фаза 2)
 
  Set<int> _selectedIds = {};

  // Этот метод вызывается, когда в БД что-то изменилось (очистка/импорт)
  void _onDbUpdate() {
    _loadData(clearFilters: true);
  }
   // Метод, который вызывается, когда пользователь нажал "Подобрать препарат"
  void _onApplyExternalFilters() {
    setState(() {
      // 1. Сбрасываем старые фильтры
      _filter.reset();
      _searchController.clear();
      _searchQuery = '';

      // 2. Применяем новые
      _filter.cultures = FilterManager.instance.speciesToFilter;
      _filter.diseases = FilterManager.instance.diseasesToFilter;
    });
  }
  @override
  void initState() {
    super.initState();
    DatabaseHelper.dbUpdateTrigger.addListener(_onDbUpdate); // <-- Добавляем слушатель
    FilterManager.instance.applyTrigger.addListener(_onApplyExternalFilters);
    // Если пришли из заказа с флагом, сразу включаем режим выбора
    if (widget.isOrderSelectionMode) {
      _isSelectionMode = true;
      _isSelectionConfirmed = false;
    }
    _loadData();
  }

  @override
  void dispose() {
    DatabaseHelper.dbUpdateTrigger.removeListener(_onDbUpdate); // <-- Удаляем слушатель
    FilterManager.instance.applyTrigger.removeListener(_onApplyExternalFilters);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // Обновляем _loadData, чтобы она умела сбрасывать фильтры
  Future<void> _loadData({bool clearFilters = false}) async {
    setState(() => _isLoading = true);
    try {
      final products = await DatabaseHelper.instance.getAllProducts();
      final dbData = await DatabaseHelper.instance.getUniqueCulturesAndDiseases();
      
      setState(() {
        _products = products;
        _categories = products.map((p) => p.category).toSet().toList()..sort();
        _availableCultures = dbData['cultures'] ?? [];
        _availableDiseases = dbData['diseases'] ?? [];
        
        if (clearFilters) {
          // Полный сброс фильтров и поиска
          _filter.reset();
          _searchController.clear();
          _searchQuery = '';
        } else {
          // На всякий случай удаляем "мертвые" фильтры, которых больше нет в базе
          _filter.categories.removeWhere((c) => !_categories.contains(c));
          _filter.cultures.removeWhere((c) => !_availableCultures.contains(c));
          _filter.diseases.removeWhere((d) => !_availableDiseases.contains(d));
        }
        
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e')));
    }
  }

  List<Product> get _filteredProducts {
    if (_isSelectionConfirmed) {
      return _products.where((p) => _selectedIds.contains(p.id)).toList();
    }

    // Возвращаем результат фильтрации без принудительной сортировки выбранных наверх
    return _filter.apply(_products, _searchQuery);
  }

  void _hideKeyboard() => _searchFocusNode.unfocus();

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) _selectedIds.clear();
    });
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  // ============================================================
  // ЭКСПОРТ (С ДИАЛОГОВЫМ ОКНОМ)
  // ============================================================
    // --- ВЫНЕСЕННЫЙ МЕТОД ЭКСПОРТА ---
    Future<void> _exportProductsToExcel(List<Product> productsToExport, String title) async {
    if (productsToExport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет данных для экспорта (список пуст)')));
      return;
    }

    // Проверяем, есть ли среди выбранных препаратов те, что есть в калькуляторе
    final calcItems = CalculatorManager.instance.items.value;
    final hasCalcItems = productsToExport.any((p) => calcItems.any((c) => c.productId == p.id));

    bool exportCalcData = false;
    bool expPercent = true;
    bool expRub = true;
    bool expFinalPack = true;
    bool expCalcRate = true;
    bool expFinalHa = true;

    if (hasCalcItems) {
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Экспорт с расчётами'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('В выбранном списке есть препараты из калькулятора. Хотите добавить колонки с расчётами?'),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        title: const Text('Выгружать расчёты из калькулятора'),
                        value: exportCalcData,
                        onChanged: (v) => setModalState(() => exportCalcData = v!),
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (exportCalcData) ...[
                        const Divider(),
                        const Text('Какие колонки добавить?', style: TextStyle(fontWeight: FontWeight.bold)),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            'Внимание: расчёты появятся только у препаратов, активных в калькуляторе. У остальных ячейки будут пустыми.',
                            style: TextStyle(color: Colors.orange, fontSize: 12),
                          ),
                        ),
                        CheckboxListTile(
                          title: const Text('Скидка (%)'),
                          value: expPercent,
                          onChanged: (v) => setModalState(() => expPercent = v!),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        CheckboxListTile(
                          title: const Text('Скидка (руб.)'),
                          value: expRub,
                          onChanged: (v) => setModalState(() => expRub = v!),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        CheckboxListTile(
                          title: const Text('Норма расхода (из калькулятора)'),
                          value: expCalcRate,
                          onChanged: (v) => setModalState(() => expCalcRate = v!),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        CheckboxListTile(
                          title: const Text('Итоговая цена за упаковку'),
                          value: expFinalPack,
                          onChanged: (v) => setModalState(() => expFinalPack = v!),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        CheckboxListTile(
                          title: const Text('Итоговая цена за гектар'),
                          value: expFinalHa,
                          onChanged: (v) => setModalState(() => expFinalHa = v!),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Экспортировать')),
              ],
            );
          }
        ),
      );

      if (result != true) return;
    }

    // Собираем инфу о фильтрах
    final activeFilters = <String>[];
    if (title == 'Отфильтрованные препараты') {
      if (_filter.categories.isNotEmpty) activeFilters.add('Тип: ${_filter.categories.join(", ")}');
      if (_filter.cultures.isNotEmpty) activeFilters.add('Культуры: ${_filter.cultures.join(", ")}');
      if (_filter.diseases.isNotEmpty) activeFilters.add('Болезни: ${_filter.diseases.join(", ")}');
      if (_filter.minPrice != null || _filter.maxPrice != null) activeFilters.add('Цена: ${_filter.minPrice ?? 0} - ${_filter.maxPrice ?? '∞'}');
      if (_searchQuery.isNotEmpty) activeFilters.add('Поиск: "$_searchQuery"');
    }
    final filterText = activeFilters.isEmpty ? 'Нет' : activeFilters.join('\n');

    // Диалог подтверждения базовый
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Экспорт: $title'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Количество записей: ${productsToExport.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (title == 'Отфильтрованные препараты') ...[
              const Text('Применённые фильтры:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(filterText, style: const TextStyle(color: Colors.grey)),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Экспортировать')),
        ],
      ),
    );

    if (confirm != true) return;

    showDialog(context: context, barrierDismissible: false, builder: (ctx) => const AlertDialog(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text('Генерация Excel...')])));

    try {
      final excel = Excel.createExcel();
      final Sheet sheet = excel['Каталог'];
      if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

      // Формируем заголовки
      List<TextCellValue> headers = [
        TextCellValue('Название'), TextCellValue('Тип'), TextCellValue('Действующие вещества'), 
        TextCellValue('Описание'), TextCellValue('Норма расхода'), TextCellValue('Фасовка'), 
        TextCellValue('Цена, руб.'), TextCellValue('Производитель'), TextCellValue('Культуры'), TextCellValue('Болезни'),
      ];
      
      if (exportCalcData) {
        if (expPercent) headers.add(TextCellValue('Скидка, %'));
        if (expRub) headers.add(TextCellValue('Скидка, руб.'));
        if (expCalcRate) headers.add(TextCellValue('Норма (калькулятор)'));
        if (expFinalPack) headers.add(TextCellValue('Итоговая цена за упак.'));
        if (expFinalHa) headers.add(TextCellValue('Итоговая цена за га'));
      }
      sheet.appendRow(headers);

      for (final p in productsToExport) {
        List<CellValue?> rowData = [
          TextCellValue(p.name), TextCellValue(p.category), TextCellValue(p.composition ?? ''), 
          TextCellValue(p.description ?? ''), TextCellValue(p.consumptionRate ?? ''), TextCellValue(p.package ?? ''), 
          p.price != null ? DoubleCellValue(p.price!) : TextCellValue(''), TextCellValue(p.manufacturer ?? ''), 
          TextCellValue(p.cultures.join(', ')), 
          TextCellValue(p.diseases.join(', ')),
        ];

        if (exportCalcData) {
          CalcItem? calcItem;
          try { calcItem = calcItems.firstWhere((e) => e.productId == p.id); } catch (_) {}

          if (expPercent) rowData.add(TextCellValue(calcItem?.percent != null ? (calcItem!.percent! / 100).toStringAsFixed(4) : ''));
          if (expRub) rowData.add(calcItem?.rub != null ? DoubleCellValue(calcItem!.rub!) : TextCellValue(''));
          if (expCalcRate) rowData.add(calcItem != null ? DoubleCellValue(calcItem.rate) : TextCellValue(''));
          
          double? finalPack;
          double? finalHa;
          if (calcItem != null && calcItem.percent != null) {
            finalPack = calcItem.basePrice * (1 - calcItem.percent! / 100);
            finalHa = finalPack * calcItem.rate;
          }
          
          if (expFinalPack) rowData.add(finalPack != null ? DoubleCellValue(finalPack) : TextCellValue(''));
          if (expFinalHa) rowData.add(finalHa != null ? DoubleCellValue(finalHa) : TextCellValue(''));
        }

        sheet.appendRow(rowData);
      }

      final bytes = excel.save();
      if (bytes == null) throw Exception('Ошибка генерации');
      final uint8Bytes = Uint8List.fromList(bytes);

      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final timeStr = '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}';
      final defaultFileName = 'catalog_export_$dateStr-$timeStr.xlsx';

      final Uri? outputUri = await FilePicker.saveFile(dialogTitle: 'Сохранить Excel', fileName: defaultFileName, bytes: uint8Bytes, type: FileType.custom, allowedExtensions: ['xlsx']);

      if (outputUri != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Сохранено ${productsToExport.length} записей'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  // Обертка для вызова из AppBar
  void _exportFilteredToExcel() {
    _exportProductsToExcel(_filteredProducts, 'Отфильтрованные препараты');
  }
  // ============================================================
  // ШТОРКА ФИЛЬТРОВ (НОВЫЙ ДИЗАЙН)
  // ============================================================
  void _showFilterSheet() {
    Set<String> tempCategories = Set.from(_filter.categories);
    Set<String> tempCultures = Set.from(_filter.cultures);
    Set<String> tempDiseases = Set.from(_filter.diseases);
    final minCtrl = TextEditingController(text: _filter.minPrice?.toString() ?? '');
    final maxCtrl = TextEditingController(text: _filter.maxPrice?.toString() ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Фильтры', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      TextButton(
                        onPressed: () {
                          setModalState(() {
                            tempCategories.clear(); tempCultures.clear(); tempDiseases.clear(); minCtrl.clear(); maxCtrl.clear();
                          });
                        },
                        child: const Text('Сбросить', style: TextStyle(color: Colors.red, fontSize: 16)),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // Строка "Тип препарата"
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Тип препарата', style: TextStyle(fontSize: 16)),
                    subtitle: Text(tempCategories.isEmpty ? 'Любой' : tempCategories.join(', '), style: const TextStyle(color: Colors.grey)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final res = await _showMultiSelectDialog(context, 'Тип препарата', _categories, tempCategories);
                      if (res != null) setModalState(() { tempCategories = res; });
                    },
                  ),
                  const Divider(),

                  // Строка "Культуры"
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Культуры', style: TextStyle(fontSize: 16)),
                    subtitle: Text(tempCultures.isEmpty ? 'Любые' : tempCultures.join(', '), style: const TextStyle(color: Colors.grey)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final res = await _showMultiSelectDialog(context, 'Выберите культуры', _availableCultures, tempCultures);
                      if (res != null) setModalState(() { tempCultures = res; });
                    },
                  ),
                  const Divider(),

                  // Строка "Болезни"
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Болезни', style: TextStyle(fontSize: 16)),
                    subtitle: Text(tempDiseases.isEmpty ? 'Любые' : tempDiseases.join(', '), style: const TextStyle(color: Colors.grey)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final res = await _showMultiSelectDialog(context, 'Выберите болезни', _availableDiseases, tempDiseases);
                      if (res != null) setModalState(() { tempDiseases = res; });
                    },
                  ),
                  const Divider(),
                  
                  const SizedBox(height: 16),
                  const Text('Цена, ₽', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: minCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'От', border: OutlineInputBorder()))),
                      const SizedBox(width: 12),
                      Expanded(child: TextField(controller: maxCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'До', border: OutlineInputBorder()))),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity, height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white),
                      onPressed: () {
                        setState(() {
                          _filter.categories = tempCategories;
                          _filter.cultures = tempCultures;
                          _filter.diseases = tempDiseases;
                          _filter.minPrice = double.tryParse(minCtrl.text);
                          _filter.maxPrice = double.tryParse(maxCtrl.text);
                        });
                        Navigator.pop(ctx);
                      },
                      child: const Text('Применить', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Универсальный диалог мультивыбора (используется и для категорий)
  Future<Set<String>?> _showMultiSelectDialog(BuildContext context, String title, List<String> options, Set<String> initial) async {
    final selected = Set<String>.from(initial);
    String search = '';
    return showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite, height: 400,
            child: Column(
              children: [
                TextField(decoration: const InputDecoration(hintText: 'Поиск...', prefixIcon: Icon(Icons.search)), onChanged: (v) => setModalState(() => search = v.toLowerCase())),
                Expanded(
                  child: ListView(
                    children: options.where((o) => o.toLowerCase().contains(search)).map((o) {
                      return CheckboxListTile(title: Text(o), value: selected.contains(o), onChanged: (v) => setModalState(() => v! ? selected.add(o) : selected.remove(o)));
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Отмена')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, selected), child: const Text('Выбрать')),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ШТОРКА СОРТИРОВКИ
  // ============================================================
  void _showSortSheet() {
    String tempSortBy = _filter.sortBy;
    bool tempAscending = _filter.sortAscending;
    bool tempSortByCalculator = _filter.sortByCalculator;

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
              
              // НОВОЕ: Сортировка по калькулятору
              CheckboxListTile(
                title: const Text('Сначала из калькулятора', style: TextStyle(fontSize: 16)),
                value: tempSortByCalculator,
                onChanged: (v) => setModalState(() => tempSortByCalculator = v!),
                contentPadding: EdgeInsets.zero,
              ),
              const Divider(),
              
              const Text('Критерий:', style: TextStyle(color: Colors.grey)),
              RadioListTile<String>(title: const Text('По названию'), value: 'name', groupValue: tempSortBy, onChanged: (v) => setModalState(() => tempSortBy = v!), contentPadding: EdgeInsets.zero),
              RadioListTile<String>(title: const Text('По цене'), value: 'price', groupValue: tempSortBy, onChanged: (v) => setModalState(() => tempSortBy = v!), contentPadding: EdgeInsets.zero),
              
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
                      _filter.sortBy = tempSortBy;
                      _filter.sortAscending = tempAscending;
                      _filter.sortByCalculator = tempSortByCalculator;
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

  // --- Метод конвертации Product в OrderItem ---
  OrderItem _createOrderItem(Product p) {
    double rate = 1.0;
    if (p.consumptionRate != null && p.consumptionRate!.isNotEmpty) {
      final match = RegExp(r'(\d+[.,]?\d*)').firstMatch(p.consumptionRate!);
      if (match != null) rate = double.tryParse(match.group(1)!.replaceAll(',', '.')) ?? 1.0;
    }

    String unit = 'л';
    if (p.package != null && p.package!.isNotEmpty) {
      final lower = p.package!.toLowerCase();
      if (lower.contains('кг')) unit = 'кг';
      else if (lower.contains('г')) unit = 'г';
      else if (lower.contains('мл')) unit = 'мл';
      else if (lower.contains('л')) unit = 'л';
    }

    return OrderItem(
      productId: p.id,
      productName: p.name,
      basePrice: p.price ?? 0.0,
      discountPercent: 0.0,
      rate: rate,
      area: 1.0,
      // packageVolume: 1.0, // Больше не используется, но оставляем для совместимости
      packageUnit: unit,
    );
  }

  // ============================================================
  // ОСНОВНОЙ BUILD
  // ============================================================
    @override
  Widget build(BuildContext context) {
    final filtered = _filteredProducts;

    return Scaffold(
      appBar: AppBar(
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Выйти из выбора',
                onPressed: () {
                  setState(() {
                    _isSelectionMode = false;
                    _isSelectionConfirmed = false;
                    _selectedIds.clear();
                  });
                },
              )
            : null,
        title: _isSelectionMode
            ? Text('Выбрано: ${_selectedIds.length}')
            : null,
        actions: _isSelectionMode
            ? [
                // ПЕРЕКЛЮЧАТЕЛЬ (Фаза 1 -> Фаза 2)
                Row(
                  children: [
                    Text(
                      _isSelectionConfirmed ? 'Подтверждено' : 'Выбор',
                      style: TextStyle(
                        fontSize: 12,
                        color: _isSelectionConfirmed ? Colors.green : Colors.grey.shade700,
                      ),
                    ),
                    Switch(
                      value: _isSelectionConfirmed,
                      activeColor: Colors.green,
                      onChanged: (val) {
                        if (val && _selectedIds.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Сначала выберите хотя бы один препарат')),
                          );
                          return; // Не даем включить переключатель
                        }
                        setState(() {
                          _isSelectionConfirmed = val;
                          // Если снимаем подтверждение, но ничего не выбрано, выходим из режима
                          if (!val && _selectedIds.isEmpty) {
                            _isSelectionMode = false;
                          }
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(width: 8),
              ]
            : [
                // Обычные кнопки (доступны только вне режима выбора)
                IconButton(
                  icon: const Icon(Icons.filter_list),
                  tooltip: 'Фильтр',
                  onPressed: _showFilterSheet,
                ),
                IconButton(
                  icon: const Icon(Icons.sort),
                  tooltip: 'Сортировка',
                  onPressed: _showSortSheet,
                ),
                IconButton(
                  icon: const Icon(Icons.download, color: Colors.blue),
                  tooltip: 'Экспорт',
                  onPressed: _exportFilteredToExcel,
                ),
                IconButton(
                  icon: const Icon(Icons.checklist, color: Colors.green),
                  tooltip: 'Мультивыбор',
                  onPressed: () {
                    setState(() {
                      _isSelectionMode = true;
                      _isSelectionConfirmed = false;
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadData,
                ),
              ],
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(_isSelectionConfirmed ? 0 : (_filter.hasActiveFilters ? 110 : 60)),
            child: _isSelectionConfirmed 
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0), // Уменьшили отступы
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          decoration: InputDecoration(
                            hintText: 'Поиск...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                      _hideKeyboard();
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12), // Стало компактнее
                            isDense: true, // Убирает лишние внутренние отступы
                          ),
                          onChanged: (v) => setState(() => _searchQuery = v),
                          onSubmitted: (_) => _hideKeyboard(),
                        ),
                        if (_filter.hasActiveFilters) ...[
                          const SizedBox(height: 4), // Уменьшили отступ
                          SizedBox(
                            height: 36,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                ..._filter.categories.map((e) => _buildActiveFilterChip(e, () => setState(() => _filter.categories.remove(e)))),
                                ..._filter.cultures.map((e) => _buildActiveFilterChip(e, () => setState(() => _filter.cultures.remove(e)))),
                                ..._filter.diseases.map((e) => _buildActiveFilterChip(e, () => setState(() => _filter.diseases.remove(e)))),
                                if (_filter.minPrice != null || _filter.maxPrice != null)
                                  _buildActiveFilterChip('Цена: ${_filter.minPrice ?? 0} - ${_filter.maxPrice ?? '∞'}', () => setState(() { _filter.minPrice = null; _filter.maxPrice = null; })),
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: ActionChip(label: const Text('Сбросить все', style: TextStyle(color: Colors.red, fontSize: 12)), onPressed: () => setState(() => _filter.reset())),
                                )
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
            ),
      ),
      body: ValueListenableBuilder<List<CalcItem>>(
        valueListenable: CalculatorManager.instance.items,
        builder: (context, calcItems, child) {
          return GestureDetector(
            onTap: _hideKeyboard,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? const Center(child: Text('Нет препаратов, соответствующих фильтру'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          // Убрали передачу isAreaMode
                          return _buildProductCard(filtered[index], calcItems); 
                        },
                      ),
          );
        },
      ),
            floatingActionButton: _isSelectionConfirmed && _selectedIds.isNotEmpty
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Скрываем экспорт, если мы в режиме выбора для заказа
                if (!widget.isOrderSelectionMode) ...[
                  FloatingActionButton.extended(
                    heroTag: 'export_fab',
                    onPressed: () {
                      final selectedProducts = _products.where((p) => _selectedIds.contains(p.id)).toList();
                      _exportProductsToExcel(selectedProducts, 'Выбранные препараты');
                    },
                    icon: const Icon(Icons.download),
                    label: Text('Экспорт (${_selectedIds.length})'),
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                  ),
                  const SizedBox(height: 12),
                  FloatingActionButton.extended(
                    heroTag: 'calc_fab',
                    onPressed: () {
                      int added = 0;
                      int failed = 0;
                      for (var id in _selectedIds) {
                        final p = _products.firstWhere((element) => element.id == id);
                        if (p.price != null) {
                          if (CalculatorManager.instance.addProduct(p)) {
                            added++;
                          }
                        } else {
                          failed++;
                        }
                      }
                      setState(() {
                        _isSelectionMode = false;
                        _isSelectionConfirmed = false;
                        _selectedIds.clear();
                      });
                      
                      String msg = 'Добавлено в калькулятор: $added';
                      if (failed > 0) msg += '. Пропущено (нет цены): $failed';
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(msg), backgroundColor: failed > 0 ? Colors.orange : Colors.green)
                      );
                    },
                    icon: const Icon(Icons.calculate),
                    label: Text('В калькулятор (${_selectedIds.length})'),
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                  ),
                  const SizedBox(height: 12),
                ],

                // Кнопка подтверждения (В заказ / Добавить)
                                // Кнопка подтверждения (В заказ / Добавить)
                FloatingActionButton.extended(
                  heroTag: 'order_fab',
                  onPressed: () {
                    final selectedProducts = _products.where((p) => _selectedIds.contains(p.id)).toList();
                    if (selectedProducts.isEmpty) return;

                    if (widget.isOrderSelectionMode) {
                      // Если каталог открыт ИЗ ОКНА РЕДАКТИРОВАНИЯ заказа — просто возвращаем список
                      Navigator.pop(context, selectedProducts);
                    } else {
                      // Если каталог открыт как обычная вкладка — добавляем в глобальный активный заказ
                      if (OrderManager.instance.activeOrder.value == null) {
                        OrderManager.instance.startNewOrder();
                      }

                      final currentOrder = OrderManager.instance.activeOrder.value!;
                      List<OrderItem> newItems = List.from(currentOrder.items);
                      int addedCount = 0;

                      for (var p in selectedProducts) {
                        // Проверяем, нет ли уже такого препарата в заказе
                        if (!newItems.any((item) => item.productId == p.id)) {
                          newItems.add(_createOrderItem(p));
                          addedCount++;
                        }
                      }

                      // Обновляем заказ в менеджере
                      OrderManager.instance.updateItems(newItems);
                      
                      // Если калькулятор синхронизирован, обновляем и его
                      if (OrderManager.instance.isSyncedWithCalculator.value) {
                        CalculatorManager.instance.syncWithOrderItems(newItems);
                      }

                      // Сбрасываем режим выбора
                      setState(() {
                        _isSelectionMode = false;
                        _isSelectionConfirmed = false;
                        _selectedIds.clear();
                      });

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(addedCount > 0 
                            ? 'Добавлено в заказ: $addedCount препаратов' 
                            : 'Все выбранные препараты уже есть в заказе'),
                          backgroundColor: addedCount > 0 ? Colors.green : Colors.orange,
                        ),
                      );
                      // 1. Переключаем вкладку на "Заказы" в фоне
                        mainScreenTabNotifier.value = 2;
                        // 2. Открываем окно редактирования
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const OrderEditScreen()),
                        );
                      }
                  },
                  icon: const Icon(Icons.check),
                  label: Text(widget.isOrderSelectionMode ? 'Добавить (${_selectedIds.length})' : 'Новый заказ (${_selectedIds.length})'),
                  backgroundColor: widget.isOrderSelectionMode ? Colors.green.shade600 : Colors.orange.shade800,
                  foregroundColor: Colors.white,
                ),
              ],
            )
          : (!_isSelectionMode
              ? FloatingActionButton(
                  onPressed: () async {
                    final res = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProductFormScreen(),  
                        ),
                    );
                    if (res  == true) _loadData();
                  },
                  backgroundColor: const Color.fromARGB(255, 157, 236, 93),
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.add),
                  tooltip: 'Добавить препарат',
                )
              : null), // В Фазе 1 (активный выбор) FAB скрыты
    );
  }

  Widget _buildActiveFilterChip(String label, VoidCallback onDeleted) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InputChip(label: Text(label, style: const TextStyle(fontSize: 12)), onDeleted: onDeleted, deleteIconColor: Colors.red),
    );
  }

  Widget _buildProductCard(Product product, List<CalcItem> calcItems) {
    String consumptionWithUnit = _formatConsumptionRate(product.consumptionRate, product.package);

    CalcItem? calcItem;
    try {
      calcItem = calcItems.firstWhere((item) => item.productId == product.id);
    } catch (_) {}

    // Определяем единицу для отображения (л или кг)
    String unitStr = 'л';
    if (product.package != null && product.package!.toLowerCase().contains('кг')) {
      unitStr = 'кг';
    }

    final isInCalc = calcItem != null;

    // Виджет с ценами (выносим отдельно для чистоты)
    Widget? priceWidget;
    if (product.price != null) {
      if (isInCalc && calcItem.finalPrice != null) {
        // Если есть скидка в калькуляторе
        priceWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${product.price!.toStringAsFixed(2)} ₽/$unitStr', 
                  style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey, fontSize: 13)),
                const SizedBox(width: 4),
                Text('- ${calcItem.percent!.toStringAsFixed(0)}%', 
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(width: 4),
                Text('= ${calcItem.finalPrice!.toStringAsFixed(2)} ₽/$unitStr', 
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 2),
            // Цена за гектар (только если в калькуляторе)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('(${(calcItem.basePrice * calcItem.rate).toStringAsFixed(2)} ₽/га)', 
                  style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey, fontSize: 12)),
                const SizedBox(width: 4),
                Text('- ${calcItem.percent!.toStringAsFixed(0)}%', 
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
                const SizedBox(width: 4),
                Text('= ${(calcItem.finalPrice! * calcItem.rate).toStringAsFixed(2)} ₽/га', 
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 13)),
              ],
            ),
          ],
        );
      } else if (isInCalc) {
        // В калькуляторе, но без скидки
        priceWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${product.price!.toStringAsFixed(2)} ₽/$unitStr', 
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 15)),
            const SizedBox(height: 2),
            Text('(${(calcItem.basePrice * calcItem.rate).toStringAsFixed(2)} ₽/га)', 
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.green, fontSize: 13)),
          ],
        );
      } else {
        // Не в калькуляторе
        priceWidget = Text('${product.price!.toStringAsFixed(2)} ₽/$unitStr', 
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 15));
      }
    }

    return Dismissible(
      key: Key('product_${product.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: Colors.red.shade400, borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_forever, color: Colors.white, size: 32),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Удалить препарат?'),
            content: Text('Вы уверены, что хотите удалить "${product.name}"?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Удалить', style: TextStyle(color: Colors.white))),
            ],
          ),
        );
      },
      onDismissed: (direction) async {
        if (product.id != null) {
          await DatabaseHelper.instance.deleteProduct(product.id!);
          _loadData();
        }
      },
      child: Card( 
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        // Оборачиваем в GestureDetector для долгого нажатия
        child: GestureDetector(
          onLongPress: () {
            HapticFeedback.vibrate(); // Легкая вибрация
            // Переходим в режим редактирования
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => ProductFormScreen(product: product)),
            ).then((result) {
              if (result == true) _loadData();
            });
          },
          child: InkWell(
            onTap: (_isSelectionMode && !_isSelectionConfirmed) 
                ? () => _toggleSelection(product.id!) 
                : null, 
            child: ExpansionTile(
              onExpansionChanged: _isSelectionMode ? (_) {} : null,
              // Заголовок с названием (кнопка редактирования удалена)
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isSelectionMode)
                    Checkbox(
                      value: _selectedIds.contains(product.id),
                      onChanged: _isSelectionConfirmed 
                          ? null 
                          : (_) => _toggleSelection(product.id!),
                    ),
                  
                  // Название (растягивается и переносит текст)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        product.name, 
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        softWrap: true,
                      ),
                    ),
                  ),
                  
                  // Кнопка "В калькулятор" (остается)
                  if (!_isSelectionMode)
                    IconButton(
                      icon: Icon(isInCalc ? Icons.remove_shopping_cart : Icons.calculate, size: 22),
                      color: isInCalc ? Colors.red.shade700 : Colors.grey.shade700,
                      onPressed: () {
                        if (!isInCalc) {
                          final added = CalculatorManager.instance.addProduct(product);
                          if (!added) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Достигнут лимит (50) или нет цены.')));
                        } else {
                          CalculatorManager.instance.removeItem(product.id!);
                        }
                      },
                      tooltip: isInCalc ? 'Убрать из калькулятора' : 'В калькулятор',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              
              // Подзаголовок (категория и цены)
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(product.category, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                  if (priceWidget != null) ...[
                    const SizedBox(height: 6),
                    priceWidget,
                  ],
                ],
              ),
              
              trailing: _isSelectionMode ? null : const Icon(Icons.keyboard_arrow_down),
              
              // Детали препарата при разворачивании
              children: _isSelectionMode ? [] : [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(),
                      if (product.composition != null && product.composition!.isNotEmpty) _buildDetailRow('Состав', product.composition!),
                      if (product.manufacturer != null && product.manufacturer!.isNotEmpty) _buildDetailRow('Производитель', product.manufacturer!),
                      if (product.package != null && product.package!.isNotEmpty) _buildDetailRow('Упаковка', product.package!),
                      if (consumptionWithUnit.isNotEmpty) _buildDetailRow('Норма расхода', consumptionWithUnit),
                      if (product.description != null && product.description!.isNotEmpty) _buildDetailRow('Описание', product.description!),
                      
                      if (product.cultures.isNotEmpty) 
                        _buildDetailRow('Культуры', product.cultures.join(', ')),
                      if (product.diseases.isNotEmpty) 
                        _buildDetailRow('Болезни', product.diseases.join(', ')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatConsumptionRate(String? rate, String? package) {
    if (rate == null || rate.isEmpty) return '';
    return rate;
  }

  Widget _buildInfoRow(String label, String value, {bool isPrice = false}) {
    return Row(
      children: [
        Text('$label: ', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontWeight: isPrice ? FontWeight.bold : FontWeight.normal, color: isPrice ? Colors.green.shade700 : Colors.black87, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade700, fontSize: 13)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 14)),
          const Divider(height: 12),
        ],
      ),
    );
  }
}