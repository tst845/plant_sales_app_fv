// lib/models/product.dart

// НОВЫЙ КЛАСС: Модель действующего вещества
class ProductActiveIngredient {
  final String name;
  final double? concentration;
  final String unit;

  ProductActiveIngredient({
    required this.name,
    this.concentration,
    this.unit = '',
  });
}


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
  final List<String> cultures;    
  final List<String> diseases;    
  final List<ProductActiveIngredient> activeIngredients; 

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
    this.activeIngredients = const [],
  });

  factory Product.fromMap(Map<String, dynamic> map, {
    List<String> cultures = const [],
    List<String> diseases = const [],
    List<ProductActiveIngredient> activeIngredients = const [],
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
      activeIngredients: activeIngredients, 
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
    List<ProductActiveIngredient>? activeIngredients, 
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
      activeIngredients: activeIngredients ?? this.activeIngredients, 
    );
  }

}