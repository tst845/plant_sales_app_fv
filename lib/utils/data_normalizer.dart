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

  /// Приводит первую букву к верхнему регистру, а остальные к нижнему.
  /// Пример: "ЯБЛОНЯ" -> "Яблоня", "яблоня" -> "Яблоня".
  static String capitalize(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    return trimmed[0].toUpperCase() + trimmed.substring(1).toLowerCase();
  }

  /// Нормализация названий культур и болезней (с учетом БД)
  static Future<String> normalizeCategoryName(String input, {required bool isCulture}) async {
    String word = input.trim();
    if (word.isEmpty) return '';

    // 1. Отрезаем всё в скобках: "Пшеница (озимая)" -> "Пшеница"
    word = word.split('(').first.trim();

    // 2. Черный список (игнорируем мусор вроде "4-Д и МЦПА" или "сорные растения")
    final lowerWord = word.toLowerCase();
    final blackList = [
      '4-д', '2м-4х', 'мцпа', 'сорные', 'сорняки', 'вредители', 'болезни',
      'виды', 'комплекс', 'фитофтороз', 'альтернариоз', 'мучнистая', 'парша'
    ];
    for (final badWord in blackList) {
      if (lowerWord.contains(badWord)) {
        return ''; // Возвращаем пустую строку, чтобы это значение не сохранялось
      }
    }

    // 3. Жесткий словарь синонимов (для унификации)
    const Map<String, String> synonyms = {
      'ябл': 'Яблоня', 'груш': 'Груша', 'вишн': 'Вишня', 'череш': 'Черешня',
      'пшен': 'Пшеница', 'ячмен': 'Ячмень', 'кукуруз': 'Кукуруза',
      'свекл': 'Свекла', 'картоф': 'Картофель', 'томат': 'Томаты',
      'огурц': 'Огурцы', 'виноград': 'Виноград', 'парш': 'Парша',
      'мучнист': 'Мучнистая роса', 'фитофтор': 'Фитофтороз',
      'колорад': 'Колорадский жук', 'тля': 'Тля', 'клещ': 'Клещ',
      'апельсин': 'Апельсин', 'мандарин': 'Мандарин', 'лимон': 'Лимон',
    };

    for (final entry in synonyms.entries) {
      if (lowerWord.contains(entry.key)) {
        return entry.value;
      }
    }

    // 4. Поиск по уже существующим в БД
    final existingDbValues = await DatabaseHelper.instance.getUniqueCulturesAndDiseases();
    final List<String> dbList = isCulture ? existingDbValues['cultures']! : existingDbValues['diseases']!;

    for (final dbWord in dbList) {
      final dbLower = dbWord.toLowerCase();
      String rootInput = word.length > 3 ? word.substring(0, word.length - 2) : word;
      String rootDb = dbLower.length > 3 ? dbLower.substring(0, dbLower.length - 2) : dbLower;

      if (rootInput == rootDb || dbLower.startsWith(rootInput) || word.startsWith(rootDb)) {
        return dbWord;
      }
    }

    // 5. Если это новое слово — форматируем
    return word[0].toUpperCase() + word.substring(1).toLowerCase();
  }
  /// Нормализация нормы расхода
  /// Превращает "0.5" в "0,5 л/га" (или другую единицу)
  static String normalizeRate(String value, String unit) {
    if (value.trim().isEmpty) return '';
    
    // Меняем точки на запятые, убираем лишние пробелы
    String cleanVal = value.replaceAll('.', ',').replaceAll(RegExp(r'\s+'), ' ').trim();
    
    // Если пользователь уже ввел единицу, отрезаем её (мы приклеим свою)
    cleanVal = cleanVal.replaceAll(RegExp(r'(л|кг|г|мл|/га)'), '').trim();
    
    // Если единица не передана, ставим по умолчанию л/га
    String cleanUnit = unit.trim().isEmpty ? 'л/га' : unit.trim();

    return '$cleanVal $cleanUnit';
  }

  /// Нормализация состава
  /// Собирает список из строк вида "Вещество 250 г/кг" в одну строку
  static String normalizeComposition(List<Map<String, String>> items) {
    final validItems = items.where((i) {
      final substance = i['substance']?.trim() ?? '';
      final qty = i['qty']?.trim() ?? '';
      return substance.isNotEmpty && qty.isNotEmpty;
    }).toList();

    return validItems.map((i) {
      final substance = i['substance']!.trim();
      final qty = i['qty']!.trim().replaceAll('.', ','); // Заменяем точки на запятые
      final unit = i['unit']?.trim() ?? '';
      return '$substance $qty $unit'.trim();
    }).join('; ');
  }

  /// Парсинг строки состава обратно в список (для редактирования)
  static List<Map<String, String>> parseComposition(String? composition) {
    if (composition == null || composition.isEmpty) return [];

    final result = <Map<String, String>>[];
    final parts = composition.split(';');

    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;

      // Пытаемся разобрать строку: "Боскалид 250 г/кг"
      // Ищем последний пробел, чтобы отделить единицу, и предпоследний - чтобы отделить число
      // Это простая эвристика. Регулярка была бы надежнее, но тут строки короткие.
      
      final words = trimmed.split(' ');
      if (words.length >= 3) {
        final unit = words.last;
        final qty = words[words.length - 2];
        final substance = words.sublist(0, words.length - 2).join(' ');
        
        result.add({'substance': substance, 'qty': qty, 'unit': unit});
      } else if (words.length == 2) {
         // Например "Медь 50"
         result.add({'substance': words[0], 'qty': words[1], 'unit': ''});
      } else {
         // Не распознали, кидаем как есть в вещество
         result.add({'substance': trimmed, 'qty': '', 'unit': ''});
      }
    }
    return result;
  }
}