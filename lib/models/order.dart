// lib/models/order.dart

class OrderItem {
  final int? id;
  final int? orderId;
  final int? productId;
  final String productName;
  final double basePrice; 
  final double discountPercent; 
  final double rate; 
  final double area; 
  final String packageUnit; // Оставляем, чтобы знать 'л' или 'кг'

  OrderItem({
    this.id,
    this.orderId,
    this.productId,
    required this.productName,
    required this.basePrice,
    this.discountPercent = 0.0,
    this.rate = 1.0,
    this.area = 1.0,
    this.packageUnit = 'ед.', // Оставляем
  });

  double get discountedPrice => basePrice * (1 - discountPercent / 100);
  double get requiredVolume => area * rate;
  double get totalPrice => discountedPrice * requiredVolume;

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      id: map['id'] as int?,
      productId: map['product_id'] as int?,
      productName: map['product_name'] as String? ?? 'Без названия',
      basePrice: (map['base_price'] as num?)?.toDouble() ?? 0.0,
      discountPercent: (map['discount_percent'] as num?)?.toDouble() ?? 0.0,
      rate: (map['rate'] as num?)?.toDouble() ?? 1.0,
      area: (map['area'] as num?)?.toDouble() ?? 1.0,
      packageUnit: map['package_unit'] as String? ?? 'ед.',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'order_id': orderId,
      'product_id': productId,
      'product_name': productName,
      'base_price': basePrice,
      'discount_percent': discountPercent,
      'rate': rate,
      'area': area,
      'package_unit': packageUnit, // Убрали package_volume
    };
  }

  OrderItem copyWith({
    int? id,
    int? orderId,
    int? productId,
    String? productName,
    double? basePrice,
    double? discountPercent,
    double? rate,
    double? area,
    String? packageUnit,
  }) {
    return OrderItem(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      basePrice: basePrice ?? this.basePrice,
      discountPercent: discountPercent ?? this.discountPercent,
      rate: rate ?? this.rate,
      area: area ?? this.area,
      packageUnit: packageUnit ?? this.packageUnit,
    );
  }
}

class Order {
  final int? id;
  final String clientName;
  final DateTime orderDate;
  final String status; // 'Новый', 'В работе', 'Выполнен'
  
  final String? notes;
  final List<OrderItem> items;

  Order({
    this.id,
    required this.clientName,
    required this.orderDate,
    this.status = 'Новый',
    this.notes, 
    required this.items,
  });

  double get totalAmount => items.fold(0, (sum, item) => sum + item.totalPrice);

  factory Order.fromMap(Map<String, dynamic> map, List<OrderItem> items) {
    return Order(
      id: map['id'] as int?,
      clientName: map['client_name'] as String,
      orderDate: DateTime.parse(map['order_date'] as String),
      status: map['status'] as String,
      notes: map['notes'] as String?,
      items: items,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'client_name': clientName,
      'order_date': orderDate.toIso8601String(),
      'status': status,
      'total_amount': totalAmount,
      'notes': notes,
    };
  }
  // ДОБАВИТЬ ЭТОТ МЕТОД:
  Order copyWith({
    int? id,
    String? clientName,
    DateTime? orderDate,
    String? status,
    String? notes,
    List<OrderItem>? items,
  }) {
    return Order(
      id: id ?? this.id,
      clientName: clientName ?? this.clientName,
      orderDate: orderDate ?? this.orderDate,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      items: items ?? this.items,
    );
  }

}