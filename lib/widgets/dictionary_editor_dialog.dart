// lib/widgets/dictionary_editor_dialog.dart
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/editable_dict_item.dart';
import '../utils/data_normalizer.dart';

class DictionaryEditorDialog extends StatefulWidget {
  const DictionaryEditorDialog({super.key});

  @override
  State<DictionaryEditorDialog> createState() => _DictionaryEditorDialogState();
}

class _DictionaryEditorDialogState extends State<DictionaryEditorDialog> {
  int _currentTab = 0; // 0 - Типы, 1 - Культуры, 2 - Болезни
  bool _isLoading = true;

  // Данные для каждой вкладки
  final Map<String, List<EditableDictItem>> _data = {
    'categories': [],
    'cultures': [],
    'diseases': [],
  };

  String _getTableName(int tab) {
    if (tab == 0) return 'categories';
    if (tab == 1) return 'cultures';
    return 'diseases';
  }

  String _getTabTitle(int tab) {
    if (tab == 0) return 'Типы препаратов';
    if (tab == 1) return 'Культуры';
    return 'Болезни';
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final db = await DatabaseHelper.instance.database;

    for (var table in ['categories', 'cultures', 'diseases']) {
      final rows = await db.query(table, orderBy: 'name ASC');
      _data[table] = rows.map((r) => EditableDictItem(
        id: r['id'] as int,
        originalName: r['name'] as String,
      )).toList();
    }
    setState(() => _isLoading = false);
  }

  bool _hasUnsavedChanges(int tab) {
    final table = _getTableName(tab);
    return _data[table]!.any((item) => item.isModified || item.isDeleted);
  }

  // --- ЛОГИКА ПЕРЕКЛЮЧЕНИЯ ВКЛАДОК ---
  Future<void> _onTabSelected(int newTab) async {
    if (_currentTab == newTab) return;

    if (_hasUnsavedChanges(_currentTab)) {
      final action = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Несохраненные изменения'),
          content: Text('В таблице "${_getTabTitle(_currentTab)}" есть несохраненные изменения. Что сделать?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Сбросить')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Сохранить')),
          ],
        ),
      );

      if (action == 'cancel') return; // Остаемся на текущей
      if (action == 'discard') {
        _resetCurrentTab();
        setState(() => _currentTab = newTab);
      }
      if (action == 'save') {
        final success = await _saveCurrentTab();
        if (success) setState(() => _currentTab = newTab);
      }
    } else {
      setState(() => _currentTab = newTab);
    }
  }

  void _resetCurrentTab() {
    final table = _getTableName(_currentTab);
    setState(() {
      for (var item in _data[table]!) {
        item.reset();
      }
    });
  }

  // --- СОХРАНЕНИЕ ТЕКУЩЕЙ ВКЛАДКИ ---
  Future<bool> _saveCurrentTab() async {
    final table = _getTableName(_currentTab);
    final changedItems = _data[table]!.where((i) => i.isModified || i.isDeleted).toList();

    if (changedItems.isEmpty) return true;

    // 1. Валидация (пустые имена, нормализация)
    int totalAffectedProducts = 0;
    int mergesCount = 0;
    int deletesCount = 0;
    int renamesCount = 0;
    
    final dbHelper = DatabaseHelper.instance;
    final db = await dbHelper.database;

    for (var item in changedItems) {
      if (item.isModified) {
        item.newName = DataNormalizer.capitalize(item.newName);
        if (item.newName.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Название не может быть пустым')));
          return false;
        }

        // Проверка на слияние
        final existing = await db.query(table, columns: ['id'], where: 'name = ?', whereArgs: [item.newName]);
        if (existing.isNotEmpty) {
          mergesCount++;
          totalAffectedProducts += await dbHelper.getDictItemUsage(table, item.id!);
        } else {
          renamesCount++;
        }
      } else if (item.isDeleted) {
        deletesCount++;
        totalAffectedProducts += await dbHelper.getDictItemUsage(table, item.id!);
      }
    }

    if (!mounted) return false;

    // 2. Диалог подтверждения
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Подтверждение изменений'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (renamesCount > 0) Text('• Будет переименовано: $renamesCount'),
            if (mergesCount > 0) Text('• Будет объединено (дубли): $mergesCount', style: const TextStyle(color: Colors.orange)),
            if (deletesCount > 0) Text('• Будет удалено: $deletesCount', style: const TextStyle(color: Colors.red)),
            if (totalAffectedProducts > 0) ...[
              const SizedBox(height: 8),
              Text('⚠️ Это затронет $totalAffectedProducts препаратов в каталоге.', style: const TextStyle(fontWeight: FontWeight.bold)),
            ]
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Принять')),
        ],
      ),
    );

    if (confirm != true) return false;

    // 3. Сохранение в БД
    try {
      await dbHelper.saveDictChanges(table, changedItems);
      
      // 4. Обновляем локальные данные после успеха
      setState(() {
        for (var item in changedItems) {
          item.reset();
        }
        // Если были слияния, нужно перезагрузить данные, так как структура изменилась
        if (mergesCount > 0 || deletesCount > 0) {
          _loadData(); 
        }
      });
      
      if (mounted) {
        DatabaseHelper.dbUpdateTrigger.value++; // Обновляем каталог
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Изменения сохранены'), backgroundColor: Colors.green));
      }
      return true;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final table = _getTableName(_currentTab);
    final items = _data[table]!;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_hasUnsavedChanges(_currentTab)) {
          final action = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Выйти без сохранения?'),
              content: const Text('В текущей вкладке есть несохраненные изменения.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Отмена')),
                TextButton(onPressed: () => Navigator.pop(ctx, 'exit'), child: const Text('Выйти', style: TextStyle(color: Colors.red))),
              ],
            ),
          );
          if (action == 'exit' && mounted) Navigator.pop(context);
        } else {
          if (mounted) Navigator.pop(context);
        }
      },
      child: Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Справочники'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () async {
                if (_hasUnsavedChanges(_currentTab)) {
                   final action = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Выйти без сохранения?'),
                      content: const Text('В текущей вкладке есть несохраненные изменения.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Отмена')),
                        TextButton(onPressed: () => Navigator.pop(ctx, 'exit'), child: const Text('Выйти', style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  );
                  if (action == 'exit' && mounted) Navigator.pop(context);
                } else {
                  Navigator.pop(context);
                }
              },
            ),
          ),
          body: Column(
            children: [
              // --- ВЕРХНЕЕ МЕНЮ (ВКЛАДКИ) ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildTabButton(0, 'Типы'),
                    _buildTabButton(1, 'Культуры'),
                    _buildTabButton(2, 'Болезни'),
                  ],
                ),
              ),
              const Divider(height: 1),
              
              // --- СПИСОК ЭЛЕМЕНТОВ ---
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : items.isEmpty
                        ? const Center(child: Text('Список пуст'))
                        : ListView.builder(
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return _DictionaryItemTile(
                                item: item,
                                onChanged: () => setState(() {}),
                              );
                            },
                          ),
              ),
            ],
          ),
          
          // --- НИЖНЯЯ ПАНЕЛЬ ---
          bottomNavigationBar: BottomAppBar(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.restore),
                  label: const Text('Сбросить'),
                  onPressed: _hasUnsavedChanges(_currentTab) ? _resetCurrentTab : null,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Принять'),
                  onPressed: _hasUnsavedChanges(_currentTab) ? () => _saveCurrentTab() : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton(int index, String title) {
    final isSelected = _currentTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onTabSelected(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: isSelected ? Colors.green : Colors.transparent, width: 3)),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.green : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }
}

// --- КАРТОЧКА ЭЛЕМЕНТА СЛОВАРЯ ---
class _DictionaryItemTile extends StatefulWidget {
  final EditableDictItem item;
  final VoidCallback onChanged;

  const _DictionaryItemTile({super.key, required this.item, required this.onChanged});

  @override
  State<_DictionaryItemTile> createState() => _DictionaryItemTileState();
}

class _DictionaryItemTileState extends State<_DictionaryItemTile> {
  bool _isEditing = false;
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.item.newName);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _saveEdit() {
    final text = _ctrl.text.trim();
    if (text.isNotEmpty) {
      widget.item.newName = text;
      widget.item.isModified = text != widget.item.originalName;
    }
    setState(() => _isEditing = false);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.item.isDeleted) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            Expanded(child: Text(widget.item.originalName, style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.red))),
            TextButton(
              onPressed: () {
                widget.item.isDeleted = false;
                widget.onChanged();
              },
              child: const Text('Отменить'),
            )
          ],
        ),
      );
    }

    return Dismissible(
      key: Key('dict_${widget.item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) {
        widget.item.isDeleted = true;
        widget.onChanged();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: widget.item.isModified ? Colors.amber.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: ListTile(
          title: _isEditing
              ? TextField(
                  controller: _ctrl,
                  autofocus: true,
                  decoration: const InputDecoration(isDense: true),
                  onSubmitted: (_) => _saveEdit(),
                )
              : Text(
                  widget.item.newName,
                  style: TextStyle(fontWeight: widget.item.isModified ? FontWeight.bold : FontWeight.normal),
                ),
          trailing: IconButton(
            icon: Icon(_isEditing ? Icons.check : Icons.edit, color: _isEditing ? Colors.green : Colors.blueGrey),
            onPressed: () {
              if (_isEditing) {
                _saveEdit();
              } else {
                setState(() => _isEditing = true);
              }
            },
          ),
        ),
      ),
    );
  }
}