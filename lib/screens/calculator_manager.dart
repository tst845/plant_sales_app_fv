import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/order.dart';
import 'order_manager.dart';

class CalcItem {
  final int productId;
  final String name;
  final double basePrice; // Цена за 1 литр/кг
  final String packageUnit; // 'л', 'кг', 'г', 'мл'
  
  double rate; // Норма расхода на га
  double area; // Площадь в га
  
  double? percent;
  double? rub;
  double? finalPrice; // Цена со скидкой за 1 литр/кг

  CalcItem({
    required this.productId,
    required this.name,
    required this.basePrice,
    required this.packageUnit,
    required this.rate,
    this.area = 1.0,
    this.percent,
    this.rub,
    this.finalPrice,
  });

  // Цена за гектар (базовая)
  double get pricePerHa => basePrice * rate;

  // Требуемый объем (Площадь * Норма)
  double get requiredVolume => area * rate;

  // Итоговая стоимость (Объем * Цена со скидкой за 1 л/кг)
  double get totalCost {
    final price = finalPrice ?? basePrice;
    return requiredVolume * price;
  }
}

class CalculatorManager {
  static final CalculatorManager instance = CalculatorManager._internal();
  CalculatorManager._internal();

  final ValueNotifier<List<CalcItem>> items = ValueNotifier<List<CalcItem>>([]);

  bool addProduct(Product product) {
    if (product.price == null) return false;
    if (items.value.length >= 50) return false; 
    if (items.value.any((e) => e.productId == product.id)) return true;

    // Извлекаем норму
    double extractedRate = 1.0;
    if (product.consumptionRate != null && product.consumptionRate!.isNotEmpty) {
      final match = RegExp(r'(\d+[.,]?\d*)').firstMatch(product.consumptionRate!);
      if (match != null) extractedRate = double.tryParse(match.group(1)!.replaceAll(',', '.')) ?? 1.0;
    }

    // Извлекаем единицу (л, кг, г, мл)
    String unit = 'л';
    if (product.package != null) {
      final lower = product.package!.toLowerCase();
      if (lower.contains('кг')) unit = 'кг';
      else if (lower.contains('г')) unit = 'г';
      else if (lower.contains('мл')) unit = 'мл';
    }

    items.value = [
      ...items.value,
      CalcItem(
        productId: product.id!,
        name: product.name,
        basePrice: product.price!,
        packageUnit: unit,
        rate: extractedRate,
        area: 1.0,
      )
    ];
    return true;
  }

  void syncWithOrderItems(List<OrderItem> orderItems) {
    List<CalcItem> newItems = orderItems.map((o) {
      final hasDiscount = o.discountPercent > 0;
      final base = o.basePrice;
      final finalP = hasDiscount ? (base * (1 - o.discountPercent / 100)) : null;

      return CalcItem(
        productId: o.productId ?? 0,
        name: o.productName,
        basePrice: base,
        packageUnit: o.packageUnit,
        rate: o.rate,
        area: o.area,
        percent: o.discountPercent,
        rub: hasDiscount ? (base - finalP!) : null,
        finalPrice: finalP,
      );
    }).toList();
    
    items.value = newItems;
    OrderManager.instance.isSyncedWithCalculator.value = true;
  }

  void updateRate(int productId, String val) {
    final r = double.tryParse(val.replaceAll(',', '.'));
    if (r == null) return;
    final list = items.value.map((e) {
      if (e.productId == productId) {
        e.rate = r;
      }
      return e;
    }).toList();
    items.value = [...list];
  }

  void updateArea(int productId, String val) {
    final a = double.tryParse(val.replaceAll(',', '.'));
    if (a == null) return;
    final list = items.value.map((e) {
      if (e.productId == productId) {
        e.area = a;
      }
      return e;
    }).toList();
    items.value = [...list];
  }

  void updatePercent(int productId, String val) {
    final p = double.tryParse(val.replaceAll(',', '.'));
    _updateCalculations(productId, percent: p);
  }

  void updateRub(int productId, String val) {
    final r = double.tryParse(val.replaceAll(',', '.'));
    _updateCalculations(productId, rub: r);
  }

  void updateFinal(int productId, String val) {
    final f = double.tryParse(val.replaceAll(',', '.'));
    _updateCalculations(productId, finalPrice: f);
  }

  void updateVolume(int productId, String val) {
    final v = double.tryParse(val.replaceAll(',', '.'));
    if (v == null) return;
    
    final list = items.value.map((e) {
      if (e.productId == productId) {
        // Защита от деления на ноль, если норма ещё не введена
        if (e.rate > 0) {
          e.area = v / e.rate;
        }
      }
      return e;
    }).toList();
    items.value = [...list];
  }

  void _updateCalculations(int productId, {double? percent, double? rub, double? finalPrice}) {
    final list = items.value.map((e) {
      if (e.productId == productId) {
        final base = e.basePrice;
        if (base == 0) { e.percent = 0; e.rub = 0; e.finalPrice = 0; return e; }

        if (percent != null) {
          e.percent = percent;
          e.rub = base * (percent / 100);
          e.finalPrice = base - e.rub!;
        } else if (rub != null) {
          e.rub = rub;
          e.finalPrice = base - rub;
          e.percent = (rub / base) * 100;
        } else if (finalPrice != null) {
          e.finalPrice = finalPrice;
          e.rub = base - finalPrice;
          e.percent = (e.rub! / base) * 100;
        }
      }
      return e;
    }).toList();
    items.value = [...list];
  }

  void removeItem(int productId) {
    items.value = items.value.where((e) => e.productId != productId).toList();
  }

  void resetItem(int productId) {
    final list = items.value.map((e) {
      if (e.productId == productId) {
        e.percent = null;
        e.rub = null;
        e.finalPrice = null;
        e.area = 1.0;
      }
      return e;
    }).toList();
    items.value = [...list];
  }

  void resetAll() {
    final list = items.value.map((e) {
      e.percent = null;
      e.rub = null;
      e.finalPrice = null;
      e.area = 1.0;
      return e;
    }).toList();
    items.value = [...list];
  }

  void clearAll() => items.value = [];
}