// lib/models/product.dart
class Product {
  final int? id;
  final String name;
  final String category;
  final String? composition;
  final String? manufacturer;
  final String? package;
  final String? consumptionRate;
  final double? price;
  final String? description;
  final List<String> cultures;    // Теперь список
  final List<String> diseases;    // Теперь список

  Product({
    this.id,
    required this.name,
    required this.category,
    this.composition,
    this.manufacturer,
    this.package,
    this.consumptionRate,
    this.price,
    this.description,
    this.cultures = const [],
    this.diseases = const [],
  });

  factory Product.fromMap(Map<String, dynamic> map, {
    List<String> cultures = const [],
    List<String> diseases = const [],
  }) {
    return Product(
      id: map['id'] as int?,
      name: map['name'] as String,
      category: map['category'] as String,
      composition: map['composition'] as String?,
      manufacturer: map['manufacturer'] as String?,
      package: map['package'] as String?,
      consumptionRate: map['consumption_rate'] as String?,
      price: (map['price'] as num?)?.toDouble(),
      description: map['description'] as String?,
      cultures: cultures,
      diseases: diseases,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'category': category,
      'composition': composition,
      'manufacturer': manufacturer,
      'package': package,
      'consumption_rate': consumptionRate,
      'price': price,
      'description': description,
    };
  }

  Product copyWith({
    int? id,
    String? name,
    String? category,
    String? composition,
    String? manufacturer,
    String? package,
    String? consumptionRate,
    double? price,
    String? description,
    List<String>? cultures,
    List<String>? diseases,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      composition: composition ?? this.composition,
      manufacturer: manufacturer ?? this.manufacturer,
      package: package ?? this.package,
      consumptionRate: consumptionRate ?? this.consumptionRate,
      price: price ?? this.price,
      description: description ?? this.description,
      cultures: cultures ?? this.cultures,
      diseases: diseases ?? this.diseases,
    );
  }

}