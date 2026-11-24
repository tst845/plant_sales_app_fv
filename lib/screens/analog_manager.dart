// lib\screens\analog_manager.dart
import 'package:flutter/material.dart';
import '../models/product.dart';

class AnalogIngredient {
  String name;
  String concentration; // Храним как строку, чтобы не терять запятые (0,5)
  String unit;

  AnalogIngredient({this.name = '', this.concentration = '', this.unit = 'г/л'});

  bool get isEmpty => name.trim().isEmpty || concentration.trim().isEmpty;

  AnalogIngredient copy() => AnalogIngredient(
    name: name, concentration: concentration, unit: unit,
  );
}

class AnalogTarget {
  String? originalProductId; // Если выбрали из базы
  String name;
  String type;
  List<AnalogIngredient> ingredients;
  String rate; // "1,0" или "0,5-1,0"
  String rateUnit; // "л/га"

  AnalogTarget({
    this.originalProductId,
    this.name = '',
    this.type = 'Фунгицид',
    List<AnalogIngredient>? ingredients,
    this.rate = '',
    this.rateUnit = 'л/га',
  }) : ingredients = ingredients ?? [AnalogIngredient()];
    // Новое свойство для красивого отображения состава
  String get compositionString {
    final validIngredients = ingredients.where((i) => i.name.trim().isNotEmpty).toList();
    if (validIngredients.isEmpty) return 'Состав не указан';
    return validIngredients
        .map((i) => '${i.name} — ${i.concentration} ${i.unit}')
        .join('\n'); // Разделяем переносом строки для читаемости
  }

}

class AnalogSearchResult {
  final AnalogTarget target;
  final List<AnalogResult> matches;
  final String? emptyReason;

  AnalogSearchResult({
    required this.target,
    required this.matches,
    this.emptyReason,
  });

  bool get hasMatches => matches.isNotEmpty;
}

class AnalogManager {
  static final AnalogManager instance = AnalogManager._internal();
  AnalogManager._internal();

  // Храним список добавленных для подбора препаратов
  final ValueNotifier<List<AnalogTarget>> targets = ValueNotifier<List<AnalogTarget>>([]);

  void addTarget(AnalogTarget target) {
    targets.value = [...targets.value, target];
  }

  void removeTarget(int index) {
    final list = List<AnalogTarget>.from(targets.value)..removeAt(index);
    targets.value = list;
  }

  void clearAll() {
    targets.value = [];
  }
}

enum AnalogMatchLevel { full, recalculate, partial }

class AnalogResult {
  final Product product;
  final AnalogMatchLevel level;
  final double? recommendedRate; // Заполняется для Level B
  final double? rateMultiplier;  // Во сколько раз изменить норму (для Level B)
  final List<String> matchingIngredients; // Для Level C
  final String targetRateUnit; // НОВОЕ: Единица измерения (л/га), чтобы правильно вывести в U
  final int matchedCount;

  AnalogResult({
    required this.product,
    required this.level,
    this.recommendedRate,
    this.rateMultiplier,
    this.matchingIngredients = const [],
    this.targetRateUnit = 'л/га',
    this.matchedCount = 0,
  });
}