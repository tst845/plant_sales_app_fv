import '../models/product.dart';
import '../database/database_helper.dart';
import '../utils/data_normalizer.dart';
import '../screens/analog_manager.dart';

class AnalogService {
  static const List<String> _antidotes = [
    'мефенпир', 'клоквинтосет', 'ципросульфамид', 'изоксадифен'
  ];

    static Future<AnalogSearchResult> findAnalogs(AnalogTarget target) async {
    final allProducts = await DatabaseHelper.instance.getAllProducts();
    final targetTypeNorm = DataNormalizer.normalizeProductType(target.type);

    // Для микроудобрений и спецпрепаратов запускаем отдельную логику
    if (targetTypeNorm == 'Микроудобрение' || targetTypeNorm == 'Спецпрепарат') {
      return _findMicroFertilizerAnalogs(target, allProducts);
    }
    // 1. Проверка нормы расхода
    final double targetRate = _parseRate(target.rate);
    if (targetRate <= 0) {
      return AnalogSearchResult(
        target: target,
        matches: [],
        emptyReason: 'Не указана норма расхода у исходного препарата',
      );
    }

    // 2. Парсинг целевых ДВ
    final Map<String, double> targetAiPerHa = {};
    final Map<String, double> targetRawConc = {};
    for (var ing in target.ingredients) {
      if (ing.name.trim().isEmpty || ing.concentration.trim().isEmpty) continue;
      if (_antidotes.any((a) => ing.name.toLowerCase().contains(a))) continue;
      final double conc = _parseRate(ing.concentration);
      if (conc > 0) {
        final key = ing.name.trim().toLowerCase();
        targetRawConc[key] = conc;
        targetAiPerHa[key] = conc * targetRate;
      }
    }

    if (targetAiPerHa.isEmpty) {
      return AnalogSearchResult(
        target: target,
        matches: [],
        emptyReason: 'У исходного препарата не указан состав (действующие вещества)',
      );
    }

    // 3. Фильтрация по типу (эффективно — сначала отсекаем лишнее)
    final sameTypeProducts = allProducts.where((p) {
      // Исключаем сам исходный препарат
      if (target.originalProductId != null && p.id.toString() == target.originalProductId) {
        return false;
      }
      return _typesMatch(p.category, target.type);
    }).toList();

    if (sameTypeProducts.isEmpty) {
      return AnalogSearchResult(
        target: target,
        matches: [],
        emptyReason: 'В каталоге нет других препаратов с типом «${target.type}»',
      );
    }

    // 4. Анализ кандидатов
    final results = <AnalogResult>[];
    for (var p in sameTypeProducts) {
      final candIngredients = DataNormalizer.parseComposition(p.composition);
      final Map<String, double> candAi = {};
      for (var ci in candIngredients) {
        final name = (ci['substance'] ?? '').trim().toLowerCase();
        if (name.isEmpty || _antidotes.any((a) => name.contains(a))) continue;
        final conc = _parseRate(ci['qty'] ?? '');
        if (conc > 0) candAi[name] = conc;
      }
      if (candAi.isEmpty) continue;

      final matchLevel = _analyzeMatch(targetAiPerHa, targetRawConc, candAi, targetRate);
      if (matchLevel != null) {
        results.add(AnalogResult(
          product: p,
          level: matchLevel.level,
          recommendedRate: matchLevel.recommendedRate,
          rateMultiplier: matchLevel.rateMultiplier,
          matchingIngredients: matchLevel.matchingIngredients,
          targetRateUnit: target.rateUnit,
        ));
      }
    }

    if (results.isEmpty) {
      return AnalogSearchResult(
        target: target,
        matches: [],
        emptyReason: 'Среди ${sameTypeProducts.length} препаратов типа «${target.type}» '
            'не найдено совпадений по составу',
      );
    }

    results.sort((a, b) => a.level.index.compareTo(b.level.index));
    return AnalogSearchResult(target: target, matches: results);
  }

  /// Сравнение типов с нормализацией и fallback для нестандартных категорий
  static bool _typesMatch(String dbType, String targetType) {
    final norm1 = DataNormalizer.normalizeProductType(dbType);
    final norm2 = DataNormalizer.normalizeProductType(targetType);

    // Оба распознаны как стандартные типы → сравниваем канонические формы
    if (norm1 != 'Другое' && norm2 != 'Другое') {
      return norm1 == norm2;
    }

    // Fallback: литеральное сравнение (для нестандартных категорий)
    return dbType.trim().toLowerCase() == targetType.trim().toLowerCase();
  }

  static _MatchResult? _analyzeMatch(
      Map<String, double> targetAi, 
      Map<String, double> targetRaw,
      Map<String, double> candAi, 
      double targetRate) {
    
    final targetKeys = targetAi.keys.toSet();
    final candKeys = candAi.keys.toSet();
    final isFullSetMatch = targetKeys.length == candKeys.length && targetKeys.containsAll(candKeys);

    if (isFullSetMatch) {
      bool allConcMatch = true;
      bool allRatesEqual = true;
      double? firstCalcRate;

      for (var key in targetAi.keys) {
        // ИСПРАВЛЕНО: Сравниваем сырые концентрации (62.5 и 62.5)
        final tRaw = targetRaw[key]!;
        final cRaw = candAi[key]!;
        
        if ((tRaw - cRaw).abs() > (tRaw * 0.02)) allConcMatch = false;

        // Расчет новой нормы: (г/га) / (г/л) = л/га
        final calcRate = targetAi[key]! / cRaw;
        if (firstCalcRate == null) {
          firstCalcRate = calcRate;
        } else {
          if ((firstCalcRate - calcRate).abs() > (firstCalcRate * 0.15)) {
            allRatesEqual = false;
          }
        }
      }

      if (allConcMatch) {
        return _MatchResult(level: AnalogMatchLevel.full);
      } else if (allRatesEqual && firstCalcRate != null) {
        return _MatchResult(
          level: AnalogMatchLevel.recalculate,
          recommendedRate: firstCalcRate,
          rateMultiplier: firstCalcRate / targetRate,
        );
      }
    }

    final matchingKeys = targetKeys.intersection(candKeys);
    if (matchingKeys.isNotEmpty) {
      return _MatchResult(
        level: AnalogMatchLevel.partial,
        matchingIngredients: matchingKeys.toList(),
      );
    }

    return null;
  }

  static double _parseRate(String? str) {
    if (str == null) return 0.0;
    final match = RegExp(r'[\d.,]+').firstMatch(str);
    if (match != null) {
      return double.tryParse(match.group(0)!.replaceAll(',', '.')) ?? 0.0;
    }
    return 0.0;
  }

  static AnalogSearchResult _findMicroFertilizerAnalogs(AnalogTarget target, List<Product> allProducts) {
    final double targetRate = _parseRate(target.rate);
    if (targetRate <= 0) {
      return AnalogSearchResult(target: target, matches: [], emptyReason: 'Не указана норма расхода');
    }

    // Собираем целевые элементы (игнорируем антидоты и пустые строки)
    final Set<String> targetElements = {};
    for (var ing in target.ingredients) {
      final name = ing.name.trim().toLowerCase();
      if (name.isNotEmpty && !_antidotes.any((a) => name.contains(a))) {
        targetElements.add(name);
      }
    }

    if (targetElements.isEmpty) {
      return AnalogSearchResult(target: target, matches: [], emptyReason: 'У исходного препарата не указан состав');
    }

    final results = <AnalogResult>[];
    // Ищем среди микроудобрений и спецпрепаратов
    final candidateTypes = ['Микроудобрение', 'Спецпрепарат'];

    for (var p in allProducts) {
      if (target.originalProductId != null && p.id.toString() == target.originalProductId) continue;

      final candType = DataNormalizer.normalizeProductType(p.category);
      if (!candidateTypes.contains(candType)) continue;

      final candIngredients = DataNormalizer.parseComposition(p.composition);
      final Set<String> candElements = {};
      for (var ci in candIngredients) {
        final name = (ci['substance'] ?? '').trim().toLowerCase();
        if (name.isNotEmpty && !_antidotes.any((a) => name.contains(a))) {
          candElements.add(name);
        }
      }

      if (candElements.isEmpty) continue;

      // Ищем пересечение
      final matched = targetElements.intersection(candElements);
      if (matched.isEmpty) continue;

      // Если совпал хотя бы один элемент — это аналог
      final matchedCount = matched.length;
      
      // Пытаемся рассчитать норму по первому совпавшему элементу
      double? recommendedRate;
      double? rateMultiplier;
      String? matchedElement;

      for (var element in matched) {
        // Находим концентрацию этого элемента в целевом препарате
        final targetConc = target.ingredients
            .firstWhere((i) => i.name.trim().toLowerCase() == element)
            .concentration;
        
        // Находим концентрацию в кандидате
        final candConcStr = candIngredients.firstWhere(
          (ci) => (ci['substance'] ?? '').trim().toLowerCase() == element
        )['qty'];

        final double? tConc = double.tryParse(targetConc.replaceAll(',', '.'));
        final double? cConc = double.tryParse((candConcStr ?? '').replaceAll(',', '.'));

        if (tConc != null && cConc != null && cConc > 0) {
          recommendedRate = (tConc * targetRate) / cConc;
          rateMultiplier = recommendedRate / targetRate;
          matchedElement = element;
          break; // Достаточно одного элемента для расчёта
        }
      }

      results.add(AnalogResult(
        product: p,
        level: AnalogMatchLevel.partial, // Всегда partial, так как состав может не совпадать полностью
        recommendedRate: recommendedRate,
        rateMultiplier: rateMultiplier,
        matchingIngredients: matched.toList(),
        targetRateUnit: target.rateUnit,
        matchedCount: matchedCount,
      ));
    }

    if (results.isEmpty) {
      return AnalogSearchResult(
        target: target,
        matches: [],
        emptyReason: 'В каталоге не найдено микроудобрений или спецпрепаратов с такими же элементами',
      );
    }

    // Сортируем: сначала те, у кого совпало больше элементов
    results.sort((a, b) => b.matchedCount.compareTo(a.matchedCount));

    return AnalogSearchResult(target: target, matches: results);
  }


}

class _MatchResult {
  final AnalogMatchLevel level;
  final double? recommendedRate;
  final double? rateMultiplier;
  final List<String> matchingIngredients;

  _MatchResult({
    required this.level,
    this.recommendedRate,
    this.rateMultiplier,
    this.matchingIngredients = const [],
  });

  
}