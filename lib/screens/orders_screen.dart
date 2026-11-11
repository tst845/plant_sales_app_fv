import 'package:flutter/material.dart';
import '../models/order.dart';
import '../database/database_helper.dart';
import 'order_edit_screen.dart';
import 'order_manager.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:io';
import 'package:flutter/services.dart'; // Для HapticFeedback
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<Order> _orders = [];
  bool _isLoading = true;
  // --- НОВЫЕ ПЕРЕМЕННЫЕ ДЛЯ ПОИСКА ---
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  // Новые настройки сортировки
  bool _sortByStatus = false;
  bool _sortByDate = true;
  bool _statusAscending = true; // true: Новый -> Отменен, false: Отменен -> Новый
  bool _dateAscending = false;  // true: Старые -> Новые, false: Новые -> Старые

  final bool _useDemoData = false; 

  @override
  void initState() {
    super.initState();
    _loadOrders();
    OrderManager.instance.activeOrder.addListener(_onDraftChanged);
    DatabaseHelper.dbUpdateTrigger.addListener(_onDbUpdate);
  }
  
  @override
  void dispose() {
    OrderManager.instance.activeOrder.removeListener(_onDraftChanged);
    DatabaseHelper.dbUpdateTrigger.removeListener(_onDbUpdate);
    _searchController.dispose(); 
    _searchFocusNode.dispose();
    super.dispose();
  }
  void _onDbUpdate() {
    if (mounted) _loadOrders();
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    
    if (_useDemoData) {
      // ... (оставляем демо-данные как было) ...
      await Future.delayed(const Duration(milliseconds: 300));
      setState(() {
        _orders = [
          Order(id: 1, clientName: 'ООО "АгроПром"', orderDate: DateTime(2026, 11, 1), status: 'Новый', items: []),
          Order(id: 2, clientName: 'Иванов И.И.', orderDate: DateTime(2026, 10, 28), status: 'Выполнен', items: []),
        ];
        _isLoading = false;
      });
    } else {
      final loaded = await DatabaseHelper.instance.getAllOrders();
      setState(() {
        _orders = loaded;
        _isLoading = false;
      });
    }
  }
  
  Color _getStatusColor(String status) {
    switch (status) {
      case 'Новый': return Colors.green.shade600;
      case 'В работе': return Colors.blue.shade600;
      case 'Выполнен': return  Colors.orange.shade700;
      case 'Отменен': return Colors.red.shade600;
      default: return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'Новый': return Icons.fiber_new;
      case 'В работе': return Icons.hourglass_top;
      case 'Выполнен': return Icons.check_circle;
      case 'Отменен': return Icons.cancel;
      default: return Icons.receipt_long;
    }
  }

  List<Order> get _sortedOrders {
    var list = List<Order>.from(_orders);

    // --- ФИЛЬТРАЦИЯ ПО ПОИСКУ ---
    if (_searchQuery.isNotEmpty) {
      list = list.where((o) => 
        o.clientName.toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
    }
    
    int getStatusWeight(String status) {
      switch (status) {
        case 'Новый': return 1;
        case 'В работе': return 2;
        case 'Выполнен': return 3;
        case 'Отменен': return 4;
        default: return 5;
      }
    }

    list.sort((a, b) {
      int cmp = 0;

      // 1. Сначала сортируем по статусу (если включено)
      if (_sortByStatus) {
        cmp = getStatusWeight(a.status).compareTo(getStatusWeight(b.status));
        if (!_statusAscending) cmp = -cmp;
      }

      // 2. Если статусы равны (или сортировка по статусу выключена) - сортируем по дате
      if (cmp == 0 && _sortByDate) {
        cmp = a.orderDate.compareTo(b.orderDate);
        if (!_dateAscending) cmp = -cmp;
      }
      
      // 3. Если обе сортировки выключены, применяем дефолт: сначала новые
      if (cmp == 0 && !_sortByStatus && !_sortByDate) {
        cmp = a.orderDate.compareTo(b.orderDate);
        cmp = -cmp; 
      }

      return cmp;
    });
    
    return list;
  }
   
  void _showSortSheet() {
    bool tempSortByStatus = _sortByStatus;
    bool tempSortByDate = _sortByDate;
    bool tempStatusAsc = _statusAscending;
    bool tempDateAsc = _dateAscending;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('Сортировка', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              
              // Сортировка по статусу
              SwitchListTile(
                title: const Text('По статусу'),
                value: tempSortByStatus,
                onChanged: (v) => setModalState(() => tempSortByStatus = v),
                contentPadding: EdgeInsets.zero,
                secondary: tempSortByStatus ? IconButton(
                  icon: Icon(tempStatusAsc ? Icons.arrow_upward : Icons.arrow_downward),
                  onPressed: () => setModalState(() => tempStatusAsc = !tempStatusAsc),
                  tooltip: tempStatusAsc ? 'Новый -> Отменен' : 'Отменен -> Новый',
                ) : null,
              ),
              const Divider(),
              
              // Сортировка по дате
              SwitchListTile(
                title: const Text('По дате'),
                value: tempSortByDate,
                onChanged: (v) => setModalState(() => tempSortByDate = v),
                contentPadding: EdgeInsets.zero,
                secondary: tempSortByDate ? IconButton(
                  icon: Icon(tempDateAsc ? Icons.arrow_upward : Icons.arrow_downward),
                  onPressed: () => setModalState(() => tempDateAsc = !tempDateAsc),
                  tooltip: tempDateAsc ? 'Старые -> Новые' : 'Новые -> Старые',
                ) : null,
              ),
              
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white),
                  onPressed: () {
                    setState(() {
                      _sortByStatus = tempSortByStatus;
                      _sortByDate = tempSortByDate;
                      _statusAscending = tempStatusAsc;
                      _dateAscending = tempDateAsc;
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
  // Генерация байтов Excel (для отправки и сохранения)
  Uint8List _generateOrderExcelBytes(Order order) {
    final excel = Excel.createExcel();
    final Sheet sheet = excel['Заказ'];
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

    final dateStr = '${order.orderDate.day}.${order.orderDate.month}.${order.orderDate.year}';
    sheet.appendRow([TextCellValue('Заказ №${order.id ?? "Черновик"}')]);
    sheet.appendRow([TextCellValue('Клиент:'), TextCellValue(order.clientName)]);
    sheet.appendRow([TextCellValue('Дата:'), TextCellValue(dateStr), TextCellValue('Статус:'), TextCellValue(order.status)]);
    sheet.appendRow([TextCellValue('')]); 

    sheet.appendRow([
      TextCellValue('Наименование'), TextCellValue('Цена (базовая)'), TextCellValue('Скидка, %'),
      TextCellValue('Цена со скидкой'), TextCellValue('Норма расхода'), TextCellValue('Площадь, га'),
      TextCellValue('Требуемый объем'), TextCellValue('Стоимость')
    ]);

    for (var item in order.items) {
      sheet.appendRow([
        TextCellValue(item.productName), DoubleCellValue(item.basePrice), DoubleCellValue(item.discountPercent),
        DoubleCellValue(item.discountedPrice), DoubleCellValue(item.rate), DoubleCellValue(item.area),
        TextCellValue('${item.requiredVolume.toStringAsFixed(2)} ${item.packageUnit}'), DoubleCellValue(item.totalPrice)
      ]);
    }

    List<CellValue?> totalRow = [TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue('')];
    totalRow.add(DoubleCellValue(order.totalAmount)); 
    sheet.appendRow(totalRow);

    final bytes = excel.save();
    if (bytes == null) throw Exception('Ошибка генерации файла');
    return Uint8List.fromList(bytes);
  }

  // Отправка в мессенджер
  Future<void> _shareOrderToMessenger(Order order) async {
    try {
      final bytes = _generateOrderExcelBytes(order);
      final tempDir = await getTemporaryDirectory();
      final dateStr = '${order.orderDate.day}.${order.orderDate.month}.${order.orderDate.year}';
      final file = File('${tempDir.path}/Заказ_${order.id}_$dateStr.xlsx');
      await file.writeAsBytes(bytes);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Заказ №${order.id} для ${order.clientName}',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка при отправке: $e')));
      }
    }
  }

  void _showOrderActions(BuildContext context, Order order) {
    final isDraft = order.id == null;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent, // Прозрачный фон для красивого скругления
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Действия с заказом${isDraft ? " (Черновик)" : ""}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                // Горизонтально прокручиваемый список кнопок
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (!isDraft) ...[
                        _buildActionButton(
                          icon: Icons.download,
                          label: 'Скачать Excel',
                          color: Colors.blue,
                          onTap: () {
                            Navigator.pop(ctx); // Закрываем шторку
                            _exportOrderToExcel(order);
                          },
                        ),
                        const SizedBox(width: 16),
                        _buildActionButton(
                          icon: Icons.share,
                          label: 'Отправить в мессенджер',
                          color: Colors.green,
                          onTap: () {
                            Navigator.pop(ctx); // Закрываем шторку
                            _shareOrderToMessenger(order);
                          },
                        ),
                        const SizedBox(width: 16),
                      ],
                      _buildActionButton(
                        icon: Icons.edit,
                        label: 'Редактировать',
                        color: Colors.orange,
                        onTap: () async {
                          Navigator.pop(ctx); // Закрываем шторку
                          
                          OrderManager.instance.setActiveOrder(order);
                          final res = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => OrderEditScreen(order: isDraft ? null : order),
                            ),
                          );
                          if (res == true) _loadOrders();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 100, // Фиксированная ширина для аккуратности
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: color.withValues(alpha: 0.1),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

    Widget _buildOrderCard(Order order, Order? activeOrder) {
    final bool isDraft = order.id == null;
    final bool isActive = activeOrder != null && activeOrder.id == order.id;
    final bool highlight = isDraft || isActive;

    final dateStr = '${order.orderDate.day}.${order.orderDate.month}.${order.orderDate.year}';

    return InkWell(
      // Обработка долгого нажатия
      onLongPress: () {
        HapticFeedback.vibrate(); // Легкая вибрация
        _showOrderActions(context, order);
      },
      borderRadius: BorderRadius.circular(12),
      child: Dismissible(
        key: Key('order_${order.id ?? 'draft'}'),
        direction: DismissDirection.endToStart,
        background: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(color: Colors.red.shade400, borderRadius: BorderRadius.circular(12)),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: const Icon(Icons.delete_forever, color: Colors.white, size: 32),
        ),
        confirmDismiss: (direction) async {
          return await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Удаление заказа'),
              content: Text(isDraft ? 'Удалить черновик?' : 'Вы уверены, что хотите удалить заказ №${order.id}?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true), 
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  child: const Text('Удалить')
                ),
              ],
            ),
          );
        },
        onDismissed: (direction) async {
          if (isDraft) {
            OrderManager.instance.clearActiveOrder();
          } else {
            await DatabaseHelper.instance.deleteOrder(order.id!);
          }
          _loadOrders();
        },
        child: Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: highlight ? Colors.blue.shade50 : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: highlight ? BorderSide(color: Colors.blue.shade300, width: 1.5) : BorderSide.none,
          ),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: isDraft ? Colors.blue : _getStatusColor(order.status),
              child: Icon(isDraft ? Icons.edit_document : _getStatusIcon(order.status), color: Colors.white),
            ),
            // Заголовок теперь содержит только имя (без кнопок)
            title: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                isDraft
                    ? 'Черновик (${order.clientName.isEmpty ? "Без имени" : order.clientName})'
                    : order.clientName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDraft ? Colors.blue.shade900 : null,
                ),
                softWrap: true,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('от $dateStr'),
                Text('Позиций: ${order.items.length}'),
              ],
            ),
            children: [
              const Divider(height: 1),
              if (order.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Заказ пуст'),
                )
              else
                ...order.items.map((item) => ListTile(
                      dense: true,
                      title: Text(item.productName),
                      subtitle: Text(
                        'Норма: ${item.rate} ${item.packageUnit}/га | Требуется: ${item.requiredVolume.toStringAsFixed(2)} ${item.packageUnit}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Text(
                        '${item.totalPrice.toStringAsFixed(2)} ₽',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    )),
              // Итоговая сумма
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Итого: ${order.totalAmount.toStringAsFixed(2)} ₽',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green),
                    ),
                  ],
                ),
              ),
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
        title: const Text('Заказы'),
        actions: [
          IconButton(icon: const Icon(Icons.sort), onPressed: _showSortSheet),
          IconButton(
            icon: const Icon(Icons.refresh), 
            tooltip: 'Обновить',
            onPressed: _loadOrders,
          ),
        ],
        // --- СТРОКА ПОИСКА КАК В КАТАЛОГЕ ---
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60.0), // Высота под строку поиска
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: 'Поиск по клиенту...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                          _searchFocusNode.unfocus();
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                isDense: true, // Компактный вид
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
              onSubmitted: (_) => _searchFocusNode.unfocus(), // Скрываем клавиатуру по Enter
            ),
          ),
        ),
        // ------------------------------------
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ValueListenableBuilder(
              valueListenable: OrderManager.instance.activeOrder,
              builder: (context, activeOrder, child) {
                final hasDraft = activeOrder != null && activeOrder.id == null;

                final displayList = [
                  if (hasDraft) activeOrder,
                  ..._sortedOrders,
                ];

                // Если список пуст после фильтрации
                if (displayList.isEmpty) {
                  if (_searchQuery.isNotEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 60, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            'По запросу "$_searchQuery" ничего не найдено',
                            style: const TextStyle(fontSize: 16, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }
                  return const Center(
                    child: Text('Нет заказов.\nНажмите + чтобы создать.'),
                  );
                }

                return GestureDetector(
                  onTap: () => _searchFocusNode.unfocus(), // Скрываем клавиатуру при тапе по списку
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: displayList.length,
                    itemBuilder: (context, index) {
                      final order = displayList[index];
                      return _buildOrderCard(order, activeOrder);
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          // ПРИНУДИТЕЛЬНО создаем новый заказ перед открытием
          OrderManager.instance.startNewOrder(); 
          
          final res = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const OrderEditScreen()),
          );
          if (res == true) _loadOrders();
        },
        icon: const Icon(Icons.add),
        label: const Text('Новый заказ'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
    );
  }

  // Метод экспорта остается без изменений
  Future<void> _exportOrderToExcel(Order order) async {
    // ... (код экспорта из вашего предыдущего файла) ...
    bool incName = true;
    bool incBasePrice = true;
    bool incDiscount = true;
    bool incFinalPrice = true;
    bool incRate = true;
    bool incArea = true;
    bool incVolume = true;
    bool incTotal = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: const Text('Экспорт заказа в Excel'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Выберите колонки для выгрузки:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  CheckboxListTile(title: const Text('Наименование'), value: incName, onChanged: (v) => setModalState(() => incName = v!), dense: true),
                  CheckboxListTile(title: const Text('Цена (базовая)'), value: incBasePrice, onChanged: (v) => setModalState(() => incBasePrice = v!), dense: true),
                  CheckboxListTile(title: const Text('Скидка, %'), value: incDiscount, onChanged: (v) => setModalState(() => incDiscount = v!), dense: true),
                  CheckboxListTile(title: const Text('Цена со скидкой'), value: incFinalPrice, onChanged: (v) => setModalState(() => incFinalPrice = v!), dense: true),
                  CheckboxListTile(title: const Text('Норма расхода'), value: incRate, onChanged: (v) => setModalState(() => incRate = v!), dense: true),
                  CheckboxListTile(title: const Text('Площадь, га'), value: incArea, onChanged: (v) => setModalState(() => incArea = v!), dense: true),
                  CheckboxListTile(title: const Text('Требуемый объем'), value: incVolume, onChanged: (v) => setModalState(() => incVolume = v!), dense: true),
                  CheckboxListTile(title: const Text('Стоимость позиции'), value: incTotal, onChanged: (v) => setModalState(() => incTotal = v!), dense: true),
                ],
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

    List<TextCellValue> headers = [];
    if (incName) headers.add(TextCellValue('Наименование'));
    if (incBasePrice) headers.add(TextCellValue('Цена (базовая)'));
    if (incDiscount) headers.add(TextCellValue('Скидка, %'));
    if (incFinalPrice) headers.add(TextCellValue('Цена со скидкой'));
    if (incRate) headers.add(TextCellValue('Норма расхода'));
    if (incArea) headers.add(TextCellValue('Площадь, га'));
    if (incVolume) headers.add(TextCellValue('Требуемый объем'));
    if (incTotal) headers.add(TextCellValue('Стоимость'));

    if (headers.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Выберите хотя бы одну колонку')));
      return;
    }

    showDialog(context: context, barrierDismissible: false, builder: (ctx) => const AlertDialog(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text('Генерация Excel...')])));

    try {
      final excel = Excel.createExcel();
      final Sheet sheet = excel['Заказ'];
      if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

      final dateStr = '${order.orderDate.day}.${order.orderDate.month}.${order.orderDate.year}';
      sheet.appendRow([TextCellValue('Заказ №${order.id ?? "Черновик"}')]);
      sheet.appendRow([TextCellValue('Клиент:'), TextCellValue(order.clientName)]);
      sheet.appendRow([TextCellValue('Дата:'), TextCellValue(dateStr), TextCellValue('Статус:'), TextCellValue(order.status)]);
      sheet.appendRow([TextCellValue('')]); 

      sheet.appendRow(headers);

      for (var item in order.items) {
        List<CellValue?> rowData = [];
        if (incName) rowData.add(TextCellValue(item.productName));
        if (incBasePrice) rowData.add(DoubleCellValue(item.basePrice));
        if (incDiscount) rowData.add(DoubleCellValue(item.discountPercent));
        if (incFinalPrice) rowData.add(DoubleCellValue(item.discountedPrice));
        if (incRate) rowData.add(DoubleCellValue(item.rate));
        if (incArea) rowData.add(DoubleCellValue(item.area));
        if (incVolume) rowData.add(TextCellValue('${item.requiredVolume.toStringAsFixed(2)} ${item.packageUnit}'));
        if (incTotal) rowData.add(DoubleCellValue(item.totalPrice));
        
        sheet.appendRow(rowData);
      }

      List<CellValue?> totalRow = [];
      for (int i = 0; i < headers.length - 1; i++) {
        totalRow.add(TextCellValue('')); 
      }
      totalRow.add(DoubleCellValue(order.totalAmount)); 
      sheet.appendRow(totalRow);

      if (order.notes != null && order.notes!.isNotEmpty) {
        sheet.appendRow([TextCellValue('')]);
        sheet.appendRow([TextCellValue('Примечание:'), TextCellValue(order.notes!)]);
      }

      final bytes = excel.save();
      if (bytes == null) throw Exception('Ошибка генерации файла');

      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      final uint8Bytes = Uint8List.fromList(bytes);
      final defaultFileName = 'order_${order.id ?? 'draft'}_$dateStr.xlsx';

      final Uri? outputUri = await FilePicker.saveFile(
        dialogTitle: 'Сохранить заказ',
        fileName: defaultFileName,
        bytes: uint8Bytes,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (outputUri != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Заказ успешно экспортирован'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка экспорта: $e')));
    }
  }
}