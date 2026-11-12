// lib/utils/data_normalizer.dart
import '../database/database_helper.dart';

class DataNormalizer {
  // Словарь базовых синонимов (для культур и болезней)
  static const Map<String, String> _synonyms = {
    // Культуры
    'ябл': 'Яблоня',
    'груш': 'Груша',
    'вишн': 'Вишня',
    'череш': 'Черешня',
    'пшен': 'Пшеница',
    'ячмен': 'Ячмень',
    'кукуруз': 'Кукуруза',
    'свекл': 'Свекла',
    'картоф': 'Картофель',
    'томат': 'Томаты',
    'огурц': 'Огурцы',
    'виноград': 'Виноград',
    'апельсин': 'Апельсин',
    'мандарин': 'Мандарин',
    'лимон': 'Лимон',
    // Болезни
    'парш': 'Парша',
    'мучнист': 'Мучнистая роса',
    'фитофтор': 'Фитофтороз',
    'монилиоз': 'Монилиоз',
    'альтернариоз': 'Альтернариоз',
    'фузариоз': 'Фузариоз',
    'колорад': 'Колорадский жук',
    'тля': 'Тля',
    'клещ': 'Клещ',
  };

  static const List<String> _blackList = [
    '4-д', '2м-4х', 'мцпа', 'сорные', 'сорняки', 'вредители', 'болезни',
    'виды', 'комплекс', 'фитофтороз', 'альтернариоз', 'мучнистая', 'парша'
  ];

  /// Приводит первую букву к верхнему регистру, а остальные к нижнему.
  static String capitalize(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    return trimmed[0].toUpperCase() + trimmed.substring(1).toLowerCase();
  }

  /// СИНХРОННАЯ версия нормализации для батч-обработки.
  /// Списки knownCultures и knownDiseases должны быть получены из БД ЗАРАНЕЕ.
  static String normalizeCategoryNameSync(
    String input, {
    required bool isCulture,
    required List<String> knownCultures,
    required List<String> knownDiseases,
  }) {
    String word = input.trim();
    if (word.isEmpty) return '';

    // 1. Отрезаем всё в скобках
    word = word.split('(').first.trim();
    if (word.isEmpty) return '';

    final lowerWord = word.toLowerCase();

    // 2. Черный список
    for (final badWord in _blackList) {
      if (lowerWord.contains(badWord)) return '';
    }

    // 3. Жесткий словарь синонимов
    for (final entry in _synonyms.entries) {
      if (lowerWord.contains(entry.key)) {
        return entry.value;
      }
    }

    // 4. Поиск по уже существующим в БД (в памяти, без запросов!)
    final dbList = isCulture ? knownCultures : knownDiseases;
    for (final dbWord in dbList) {
      final dbLower = dbWord.toLowerCase();
      final rootInput = word.length > 3 ? word.substring(0, word.length - 2) : word;
      final rootDb = dbLower.length > 3 ? dbLower.substring(0, dbLower.length - 2) : dbLower;

      if (rootInput == rootDb || dbLower.startsWith(rootInput) || word.startsWith(rootDb)) {
        return dbWord;
      }
    }

    // 5. Новое слово
    return word[0].toUpperCase() + word.substring(1).toLowerCase();
  }

  /// АСИНХРОННАЯ обертка для одиночного вызова (сама запрашивает списки из БД)
  static Future<String> normalizeCategoryName(String input, {required bool isCulture}) async {
    final data = await DatabaseHelper.instance.getUniqueCulturesAndDiseases();
    return normalizeCategoryNameSync(
      input,
      isCulture: isCulture,
      knownCultures: data['cultures'] ?? [],
      knownDiseases: data['diseases'] ?? [],
    );
  }

  /// Нормализация нормы расхода (без изменений)
  static String normalizeRate(String value, String unit) {
    if (value.trim().isEmpty) return '';
    String cleanVal = value.replaceAll('.', ',').replaceAll(RegExp(r'\s+'), ' ').trim();
    cleanVal = cleanVal.replaceAll(RegExp(r'(л|кг|г|мл|/га)'), '').trim();
    String cleanUnit = unit.trim().isEmpty ? 'л/га' : unit.trim();
    return '$cleanVal $cleanUnit';
  }

  /// Нормализация состава (без изменений)
  static String normalizeComposition(List<Map<String, String>> items) {
    final validItems = items.where((i) {
      final substance = i['substance']?.trim() ?? '';
      final qty = i['qty']?.trim() ?? '';
      return substance.isNotEmpty && qty.isNotEmpty;
    }).toList();

    return validItems.map((i) {
      final substance = i['substance']!.trim();
      final qty = i['qty']!.trim().replaceAll('.', ',');
      final unit = i['unit']?.trim() ?? '';
      return '$substance $qty $unit'.trim();
    }).join('; ');
  }

  /// Парсинг строки состава (без изменений)
  static List<Map<String, String>> parseComposition(String? composition) {
    if (composition == null || composition.isEmpty) return [];
    final result = <Map<String, String>>[];
    final parts = composition.split(';');

    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;

      final words = trimmed.split(' ');
      if (words.length >= 3) {
        final unit = words.last;
        final qty = words[words.length - 2];
        final substance = words.sublist(0, words.length - 2).join(' ');
        result.add({'substance': substance, 'qty': qty, 'unit': unit});
      } else if (words.length == 2) {
        result.add({'substance': words[0], 'qty': words[1], 'unit': ''});
      } else {
        result.add({'substance': trimmed, 'qty': '', 'unit': ''});
      }
    }
    return result;
  }
}