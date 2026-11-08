import 'package:flutter/material.dart';
import '../models/product.dart';
import 'dart:math' as math;
import '../models/order.dart';
import 'order_manager.dart';

class CalcItem {
  final int productId;
  final String name;
  final double basePrice;
  final String? packageStr; // Строка упаковки (например, "10 л")
  
  double rate; // Норма расхода
  double area; // Площадь (для режима "На площадь")
  
  double? percent;
  double? rub;
  double? finalPrice; // Цена со скидкой за 1 упаковку

  CalcItem({
    required this.productId,
    required this.name,
    required this.basePrice,
    this.packageStr,
    required this.rate,
    this.area = 1.0,
    this.percent,
    this.rub,
    this.finalPrice,
  });

  // Цена за гектар (базовая)
  double getEffectiveBasePrice(bool isAreaMode) {
    if (isAreaMode) {
      // В режиме площади показываем цену за Га
      return basePrice * rate; 
    }
    return basePrice;
  }

  // --- ПАРСИНГ УПАКОВКИ ---
  double get packageVolume {
    if (packageStr == null || packageStr!.isEmpty) return 1.0;
    final match = RegExp(r'(\d+([.,]\d+)?)').firstMatch(packageStr!);
    if (match != null) {
      return double.tryParse(match.group(1)!.replaceAll(',', '.')) ?? 1.0;
    }
    return 1.0;
  }

  String get packageUnit {
    if (packageStr == null) return 'ед.';
    final lower = packageStr!.toLowerCase();
    if (lower.contains('мл')) return 'мл'; // Проверяем мл до л
    if (lower.contains('кг')) return 'кг'; // Проверяем кг до г
    if (lower.contains('г')) return 'г';
    if (lower.contains('л')) return 'л';
    return 'ед.';
  }

  // --- РАСЧЕТЫ ДЛЯ РЕЖИМА "НА ПЛОЩАДЬ" ---
  
  // Требуемый объем (Площадь * Норма)
  double get requiredVolume => area * rate;

  // Количество упаковок (округление вверх)
  int get packagesCount {
    if (packageVolume <= 0) return 0;
    final count = requiredVolume / packageVolume;
    return count.ceil();
  }

  // Итоговая стоимость (Кол-во упаковок * Цена со скидкой)
  double get totalCost {
    final price = finalPrice ?? basePrice; // Если скидки нет, берем базовую
    return packagesCount * price;
  }
}

class CalculatorManager {
  static final CalculatorManager instance = CalculatorManager._internal();
  CalculatorManager._internal();

  final ValueNotifier<List<CalcItem>> items = ValueNotifier<List<CalcItem>>([]);
  final ValueNotifier<bool> isAreaMode = ValueNotifier<bool>(false); // Переименовали в isAreaMode

 bool addProduct(Product product) {
    if (product.price == null) return false;
    
    // УВЕЛИЧИВАЕМ ЛИМИТ (или убираем вовсе)
    if (items.value.length >= 50) return false; 
    
    if (items.value.any((e) => e.productId == product.id)) return true;

    double extractedRate = 1.0;
    if (product.consumptionRate != null && product.consumptionRate!.isNotEmpty) {
      final match = RegExp(r'(\d+[.,]?\d*)').firstMatch(product.consumptionRate!);
      if (match != null) {
        extractedRate = double.tryParse(match.group(1)!.replaceAll(',', '.')) ?? 1.0;
      }
    }

    items.value = [
      ...items.value,
      CalcItem(
        productId: product.id!,
        name: product.name,
        basePrice: product.price!,
        packageStr: product.package,
        rate: extractedRate,
        area: 1.0,
      )
    ];
    return true;
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

  void syncWithOrderItems(List<OrderItem> orderItems) {
    List<CalcItem> newItems = orderItems.map((o) {
      // ПЕРЕСЧИТЫВАЕМ СКИДКУ, чтобы калькулятор не терял её
      final hasDiscount = o.discountPercent > 0;
      final base = o.basePrice;
      final finalP = hasDiscount ? (base * (1 - o.discountPercent / 100)) : null;

      return CalcItem(
        productId: o.productId ?? 0,
        name: o.productName,
        basePrice: base,
        packageStr: '${o.packageVolume} ${o.packageUnit}',
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

  void toggleMode(bool isArea) {
    if (isAreaMode.value == isArea) return;
    isAreaMode.value = isArea;
    _recalculateAll();
  }

  void _recalculateAll() {
    final isArea = isAreaMode.value;
    final list = items.value.map((e) {
      final effectiveBase = e.getEffectiveBasePrice(isArea);
      if (e.percent != null) {
        e.rub = effectiveBase * (e.percent! / 100);
        e.finalPrice = effectiveBase - e.rub!;
      } else {
        e.rub = null;
        e.finalPrice = null;
      }
      return e;
    }).toList();
    items.value = [...list];
  }

  void updateRate(int productId, String val) {
    final r = double.tryParse(val.replaceAll(',', '.'));
    if (r == null) return;
    final list = items.value.map((e) {
      if (e.productId == productId) {
        e.rate = r;
        if (e.percent != null) {
          final effectiveBase = e.getEffectiveBasePrice(isAreaMode.value);
          e.rub = effectiveBase * (e.percent! / 100);
          e.finalPrice = effectiveBase - e.rub!;
        }
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

  void _updateCalculations(int productId, {double? percent, double? rub, double? finalPrice}) {
    final isArea = isAreaMode.value;
    final list = items.value.map((e) {
      if (e.productId == productId) {
        final base = e.getEffectiveBasePrice(isArea);
        if (base == 0) {
          e.percent = 0; e.rub = 0; e.finalPrice = 0;
          return e;
        }

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
}