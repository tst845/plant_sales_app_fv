// lib\widgets\import_wizard_dialog.dart
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'dart:io';

import '../models/product.dart';
import '../models/import_state.dart';
import '../services/import_service.dart';
import '../database/database_helper.dart';

class ImportWizardDialog extends StatefulWidget {
  final String? initialFilePath;

  const ImportWizardDialog({super.key, this.initialFilePath});

  @override
  State<ImportWizardDialog> createState() => _ImportWizardDialogState();
}

class _ImportWizardDialogState extends State<ImportWizardDialog> {
  ImportStep _currentStep = ImportStep.sheets;
  ImportState? _state;
  Excel? _excel;
  String? _sheetsError; // сообщение об ошибке анализа выбранного листа
  
  bool _isBusy = false;
  String _busyMessage = '';

  // Данные для парсинга
  List<String> _knownCultures = [];
  List<String> _knownDiseases = [];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    setState(() {
      _isBusy = true;
      _busyMessage = 'Загрузка файла...';
    });

    try {
      String? filePath = widget.initialFilePath;
      if (filePath == null) {
        final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls']);
        if (result == null || result.isEmpty) {
          if (mounted) Navigator.pop(context);
          return;
        }
        filePath = result.first.path; 
      }

      final bytes = await File(filePath!).readAsBytes();
      _excel = Excel.decodeBytes(bytes);

      final dbData = await DatabaseHelper.instance.getUniqueCulturesAndDiseases();
      _knownCultures = dbData['cultures'] ?? [];
      _knownDiseases = dbData['diseases'] ?? [];

      _state = ImportState(
        filePath: filePath,
        availableSheets: _excel!.tables.keys.where((n) => !n.startsWith('_')).toList(),
      );

      setState(() => _isBusy = false);
    } catch (e) {
      setState(() => _isBusy = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
        Navigator.pop(context);
      }
    }
  }

  // === НАВИГАЦИЯ ===
  void _nextStep() {
    if (_currentStep == ImportStep.columns) {
      _processSheets(); // Парсинг данных и поиск дублей
      return;
    }

    setState(() {
      switch (_currentStep) {
        case ImportStep.sheets:
          _currentStep = ImportStep.columns;
          break;
        case ImportStep.columns:
          _currentStep = ImportStep.emptyCells;
          break;
        case ImportStep.emptyCells:
          _currentStep = _state!.duplicates.isNotEmpty && !_state!.duplicatesIgnored
              ? ImportStep.duplicates
              : ImportStep.mode;
          break;
        case ImportStep.duplicates:
          _currentStep = ImportStep.mode;
          break;
        case ImportStep.mode:
          _processImport(); // Финальное сохранение
          break;
        default:
          break;
      }
    });
  }

  void _prevStep() {
    setState(() {
      switch (_currentStep) {
        case ImportStep.columns:
          _currentStep = ImportStep.sheets;
          break;
        case ImportStep.emptyCells:
          _currentStep = ImportStep.columns;
          break;
        case ImportStep.duplicates:
          _currentStep = ImportStep.emptyCells;
          break;
        case ImportStep.mode:
          _currentStep = _state!.duplicates.isNotEmpty && !_state!.duplicatesIgnored
              ? ImportStep.duplicates
              : ImportStep.emptyCells;
          break;
        default:
          break;
      }
    });
  }

  bool _canGoNext() {
    if (_state == null) return false;
    if (_currentStep == ImportStep.sheets) {
      return _state!.selectedSheets.isNotEmpty;
    }
    if (_currentStep == ImportStep.columns) {
      for (var sheet in _state!.selectedSheets) {
        final config = _state!.configs[sheet];
        if (config == null || !config.hasName) return false;  
      }
      return true;
    }
    return true;
  }

  // === ЛОГИКА ПАРСИНГА И ДУБЛЕЙ ===
  Future<void> _processSheets() async {
    setState(() {
      _isBusy = true;
      _busyMessage = 'Анализ данных и поиск дублей...';
    });

    try {
      _state!.parsedProducts.clear();
      _state!.sheetStats.clear();
      final Map<Product, String> productSourceSheet = {}; // Для поиска дублей

      for (var sheetName in _state!.selectedSheets) {
        final config = _state!.configs[sheetName];
        if (config == null) {
          _state!.sheetStats[sheetName] = SheetStats(); // пустая статистика
          continue;
        }
        final stats = SheetStats();
        
        final products = ImportService.parseSheet(
          config,
          stats,
          knownCultures: _knownCultures,
          knownDiseases: _knownDiseases,
          ignoreEmptyCells: _state!.ignoreEmptyCells,
        );

        _state!.parsedProducts.addAll(products);
        _state!.sheetStats[sheetName] = stats;
        
        for (var p in products) {
          productSourceSheet[p] = sheetName;
        }
      }

      // Поиск дублей
      _state!.duplicates = ImportService.findDuplicates(_state!.parsedProducts, productSourceSheet);

      // Применяем слияние к общему списку
      final List<Product> finalProducts = [];
      final Map<String, DuplicateGroup> dupMap = {for (var d in _state!.duplicates) d.normalizedName: d};
      
      final Set<String> processedDups = {};

      for (var p in _state!.parsedProducts) {
        final normName = p.name.trim().toLowerCase();
        if (dupMap.containsKey(normName)) {
          if (!processedDups.contains(normName)) {
            // Приоритет по умолчанию — лист, где препарат встретился впервые
            final prioritySheet = productSourceSheet[p]!;
            _state!.duplicatePriorities[normName] = prioritySheet;
            
            final merged = ImportService.mergeDuplicates(dupMap[normName]!, prioritySheet);
            finalProducts.add(merged);
            processedDups.add(normName);
          }
        } else {
          finalProducts.add(p);
        }
      }
      _state!.parsedProducts = finalProducts;

      setState(() {
        _isBusy = false;
        _currentStep = ImportStep.emptyCells;
      });
    } catch (e) {
      setState(() => _isBusy = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка анализа: $e')));
    }
  }

  Future<void> _processImport() async {
    setState(() {
      _isBusy = true;
      _busyMessage = 'Сохранение в базу данных...';
    });

    try {
      final result = await ImportService.applyImport(_state!);
      _state!.result = result;
      DatabaseHelper.dbUpdateTrigger.value++; // Обновляем UI каталога

      setState(() {
        _isBusy = false;
        _currentStep = ImportStep.report;
      });
    } catch (e) {
      setState(() => _isBusy = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
    }
  }

  // === UI ===
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isBusy && _currentStep == ImportStep.sheets,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _isBusy) return;
        if (_currentStep == ImportStep.report) {
          Navigator.pop(context);
        } else {
          _prevStep();
        }
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(8),
        child: Container(
          width: double.maxFinite,
          height: MediaQuery.of(context).size.height * 0.9,
          padding: const EdgeInsets.all(16),
          child: _isBusy
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Text(_busyMessage, style: const TextStyle(fontSize: 16)),
                  ],
                )
              : Column(
                  children: [
                    Text(
                      _getStepTitle(),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    if (_state?.filePath != null && _state!.filePath.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 16), // Увеличен отступ сверху и снизу
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.insert_drive_file, size: 18, color: Colors.blue.shade700), // Иконка тоже синяя
                            const SizedBox(width: 8),
                            Flexible(
                              child: Tooltip(
                                message: _state!.filePath,
                                child: Text(
                                  'Файл: ${_basename(_state!.filePath)}',
                                  style: TextStyle(
                                    fontSize: 14, // Увеличен шрифт (было 12)
                                    fontWeight: FontWeight.w500,
                                    color: Colors.blue.shade700, // Изменен цвет на синий
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      const SizedBox(height: 16),
                    Expanded(child: _buildStepContent()),
                    if (_currentStep != ImportStep.report) _buildBottomNav(),
                  ],
                ),
        ),
      ),
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case ImportStep.sheets: return 'Шаг 1: Выбор листов';
      case ImportStep.columns: return 'Шаг 2: Настройка колонок';
      case ImportStep.emptyCells: return 'Шаг 3: Пустые ячейки';
      case ImportStep.duplicates: return 'Шаг 4: Дубликаты';
      case ImportStep.mode: return 'Шаг 5: Режим импорта';
      case ImportStep.report: return 'Импорт завершен';
    }
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case ImportStep.sheets: return _buildSheetsStep();
      case ImportStep.columns: return _buildColumnsStep();
      case ImportStep.emptyCells: return _buildEmptyCellsStep();
      case ImportStep.duplicates: return _buildDuplicatesStep();
      case ImportStep.mode: return _buildModeStep();
      case ImportStep.report: return _buildReportStep();
    }
  }

  Widget _buildBottomNav() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton(
          onPressed: () {
            if (_currentStep == ImportStep.sheets) Navigator.pop(context);
            else _prevStep();
          },
          child: const Text('Назад / Отмена'),
        ),
        ElevatedButton(
          onPressed: _canGoNext() ? _nextStep : null,
          child: Text(_currentStep == ImportStep.mode ? 'Импортировать' : 'Далее'),
        ),
      ],
    );
  }


    // --- ШАГ 1: ЛИСТЫ ---
  Widget _buildSheetsStep() {
    if (_state == null) {
      return const Center(child: Text('Файл не загружен'));
    }

    return Column(
      children: [
        if (_sheetsError != null)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              border: Border.all(color: Colors.red.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _sheetsError!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            children: _state!.availableSheets.map((sheet) {
              final isSelected = _state!.selectedSheets.contains(sheet);
              final hasConfig = _state!.configs.containsKey(sheet);
              final broken = isSelected && !hasConfig;

              return CheckboxListTile(
                key: ValueKey('sheet_$sheet'),
                title: Text(sheet),
                subtitle: broken
                    ? const Text(
                        'Лист не распознан как каталог или прайс-лист',
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      )
                    : null,
                value: isSelected,
                onChanged: (val) => _onSheetToggled(sheet, val == true),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  void _onSheetToggled(String sheet, bool selected) {
    // Снятие галочки — просто убираем из списка
    if (!selected) {
      setState(() {
        _state!.selectedSheets.remove(sheet);
        _sheetsError = null;
      });
      return;
    }

    final sheetObj = _excel?.tables[sheet];
    if (sheetObj == null) {
      setState(() => _sheetsError = 'Не удалось прочитать лист "$sheet"');
      return;
    }

    SheetConfig? config;
    try {
      config = ImportService.analyzeSheet(sheetObj, sheet);
    } catch (e, st) {
      debugPrint('analyzeSheet("$sheet") error: $e\n$st');
      setState(() => _sheetsError = 'Ошибка анализа листа "$sheet": $e');
      return;
    }

    if (config == null) {
      setState(() => _sheetsError =
          'Лист "$sheet" не похож на каталог или прайс-лист '
          '(не найдены колонки «Название» и «Тип» / «Препарат»).');
      return;
    }

    setState(() {
      _state!.selectedSheets.add(sheet);
      _state!.configs[sheet] = config!;
      _sheetsError = null;
    });
  }

  // --- ШАГ 2: КОЛОНКИ ---
  Widget _buildColumnsStep() {
    final missingCategorySheets = _state!.selectedSheets
    .where((s) => _state!.configs[s]?.hasCategory == false)
    .toList();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (missingCategorySheets.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade100,
              border: Border.all(color: Colors.red),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'На листах ${missingCategorySheets.join(", ")} не выбрана колонка "Категория". Новые препараты с этих листов не смогут добавиться в БД.',
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: DefaultTabController(
            length: _state!.selectedSheets.length,
            child: Column(
              children: [
                TabBar(
                  isScrollable: true,
                  tabs: _state!.selectedSheets.map((s) => Tab(text: s)).toList(),
                ),
                Expanded(
                  child: TabBarView(
                    children: _state!.selectedSheets.map((sheetName) {
                      final config = _state!.configs[sheetName];
                      if (config == null) {
                        return const Center(
                          child: Text(
                            'Лист не распознан',
                            style: TextStyle(color: Colors.red),
                          ),
                        );
                      }
                      return _buildSheetConfig(config);
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSheetConfig(SheetConfig config) {
    final labels = {
      'name': 'Название', 
      'category': 'Категория', 
      'composition': 'Состав', 
      'manufacturer': 'Производитель', 
      'package': 'Упаковка', 
      'rate': 'Норма расхода', 
      'price': 'Цена', 
      'description': 'Описание', 
      'cultures': 'Культуры', 
      'diseases': 'Болезни'
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: config.availableColumns.keys.map((field) {
        
        // ОСОБЫЙ БЛОК ДЛЯ КАТЕГОРИИ
        if (field == 'category') {
          if (config.categorySource == CategorySource.column) {
            // Формат A: обычный выпадающий список (как было)
            final indices = config.availableColumns['category']!;
            if (indices.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Категория (Колонка)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int?>(
                    value: config.selectedColumns['category'],
                    isExpanded: true,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Не импортировать')),
                      ...indices.map((idx) => DropdownMenuItem(value: idx, child: Text(config.headerLabels[idx], overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (val) => setState(() => config.selectedColumns['category'] = val),
                  ),
                ],
              ),
            );
          } else {
            // Формат B/C: Категории из разделителей + поле дефолта
            return Padding(
              padding: const EdgeInsets.only(bottom: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Категория (из разделителей)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (config.detectedCategories.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      children: config.detectedCategories.map((c) => Chip(label: Text(c))).toList(),
                    )
                  else
                    const Text('Разделители не найдены. Будет использована категория по умолчанию.', style: TextStyle(fontSize: 12, color: Colors.orange)),
                  
                  const SizedBox(height: 12),
                  TextFormField(
                    key: ValueKey('fallback_${config.sheetName}'), // Важно для сохранения ввода
                    initialValue: config.fallbackCategory,
                    decoration: const InputDecoration(
                      labelText: 'Категория по умолчанию',
                      hintText: 'Другое',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (val) => config.fallbackCategory = val.isEmpty ? 'Другое' : val,
                  ),
                ],
              ),
            );
          }
        }

        // ОСТАЛЬНЫЕ ПОЛЯ (Название, Цена и т.д.)
        final indices = config.availableColumns[field]!;
        if (indices.isEmpty && field != 'name') return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(labels[field] ?? field, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int?>(
                value: config.selectedColumns[field],
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Не импортировать')),
                  ...indices.map((idx) => DropdownMenuItem(value: idx, child: Text(config.headerLabels[idx], overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (val) => setState(() => config.selectedColumns[field] = val),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // --- ШАГ 3: ПУСТЫЕ ЯЧЕЙКИ ---
  Widget _buildEmptyCellsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text('Игнорировать пустые ячейки', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('Если ячейка в Excel пуста, старое значение в базе данных сохранится. Если выключить — пустые ячейки будут СТИРАТЬ данные.'),
          value: _state!.ignoreEmptyCells,
          onChanged: (val) {
            setState(() => _state!.ignoreEmptyCells = val);
          },
        ),
        const SizedBox(height: 16),
        const Text('Рекомендуется оставить эту опцию включенной, чтобы случайно не удалить существующие данные.', style: TextStyle(color: Colors.grey)),
      ],
    );
  }

  // --- ШАГ 4: ДУБЛИ ---
  Widget _buildDuplicatesStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Найдено дублей: ${_state!.duplicates.length}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const Text('Выберите, из какого листа брать приоритетные данные (остальные дополнят пустые поля).'),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.builder(
            itemCount: _state!.duplicates.take(10).length,
            itemBuilder: (context, index) {
              final group = _state!.duplicates[index];
              return ExpansionTile(
                title: Text(group.variants.first.product.name),
                subtitle: Text('Встречается на ${group.variants.length} листах'),
                children: group.variants.map((v) {
                  return RadioListTile<String>(
                    title: Text('Лист: ${v.sheetName}'),
                    subtitle: Text('Цена: ${v.product.price ?? "нет"}'),
                    value: v.sheetName,
                    groupValue: _state!.duplicatePriorities[group.normalizedName],
                    onChanged: (val) {
                      setState(() {
                        _state!.duplicatePriorities[group.normalizedName] = val!;
                        // Пересчитываем слияние для этого дубля
                        final merged = ImportService.mergeDuplicates(group, val);
                        // Обновляем в общем списке
                        final idx = _state!.parsedProducts.indexWhere((p) => p.name.trim().toLowerCase() == group.normalizedName);
                        if (idx != -1) _state!.parsedProducts[idx] = merged;
                      });
                    },
                  );
                }).toList(),
              );
            },
          ),
        ),
        if (_state!.duplicates.length > 10)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text('... и ещё ${_state!.duplicates.length - 10} дублей'),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Сохранить в Excel'),
              onPressed: () => ImportService.exportDuplicatesToExcel(_state!.duplicates),
            ),
            TextButton.icon(
              icon: const Icon(Icons.clear_all),
              label: const Text('Игнорировать дубли'),
              onPressed: () {
                setState(() {
                  _state!.duplicatesIgnored = true;
                  _nextStep();
                });
              },
            ),
          ],
        )
      ],
    );
  }

  // --- ШАГ 5: РЕЖИМ ---
  Widget _buildModeStep() {
    final total = _state!.parsedProducts.length;
    
    return ListView(
      children: [
        Text('К импорту подготовлено: $total препаратов.', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        RadioListTile<ImportMode>(
          title: const Text('Добавить новые'),
          subtitle: const Text('Существующие препараты будут пропущены'),
          value: ImportMode.addOnly,
          groupValue: _state!.mode,
          onChanged: (val) => setState(() => _state!.mode = val!),
        ),
        RadioListTile<ImportMode>(
          title: const Text('Обновить существующие'),
          subtitle: const Text('Новые препараты будут пропущены'),
          value: ImportMode.updateOnly,
          groupValue: _state!.mode,
          onChanged: (val) => setState(() => _state!.mode = val!),
        ),
        RadioListTile<ImportMode>(
          title: const Text('Обновить и добавить'),
          subtitle: const Text('Самый безопасный вариант: обновит старые и добавит новые'),
          value: ImportMode.updateAndAdd,
          groupValue: _state!.mode,
          onChanged: (val) => setState(() => _state!.mode = val!),
        ),
      ],
    );
  }

  // --- ШАГ 6: ОТЧЕТ ---
  Widget _buildReportStep() {
    final res = _state!.result!;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 60),
          const SizedBox(height: 16),
          if (_state!.filePath.isNotEmpty)
            Text(
              'Файл: ${_basename(_state!.filePath)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
          const SizedBox(height: 16),
          Text('Добавлено: ${res.added}', style: const TextStyle(fontSize: 16)),
          Text('Обновлено: ${res.updated}', style: const TextStyle(fontSize: 16)),
          Text('Пропущено: ${res.skipped}', style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 16),
          if (res.newCultures > 0 || res.newDiseases > 0)
            Text('В справочники добавлено: ${res.newCultures} культур, ${res.newDiseases} болезней.', style: const TextStyle(color: Colors.blue)),
          if (res.errors.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Ошибки:', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ...res.errors.take(10).map((e) => Text('• $e', style: const TextStyle(color: Colors.red))),
            if (res.errors.length > 10) Text('... и ещё ${res.errors.length - 10} ошибок', style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 30),
          Center(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть'),
            ),
          )
        ],
      ),
    );
  }

  String _basename(String path) {
    // Универсально для Android (/), iOS (/), Windows (\).
    final idx = path.lastIndexOf(RegExp(r'[/\\]'));
    return idx >= 0 ? path.substring(idx + 1) : path;
  }

}