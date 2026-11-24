// lib/utils/data_normalizer.dart
import '../database/database_helper.dart';

class DataNormalizer {
   
  static const Map<String, String> _typeRoots = {
    'герб': 'Гербицид',
    'инсек': 'Инсектицид',
    'фунг': 'Фунгицид',
    'протр': 'Протравитель',
    'десик': 'Десикант',
    'спец': 'Спецпрепарат',
    'роден': 'Родентицид',
    'фумиг': 'Фумигант',
    'микроуд': 'Микроудобрение',
  };

  /// Умное распознавание типа препарата из строки-разделителя
  static String normalizeProductType(String input) {
    final word = input.trim().toLowerCase().replaceAll(RegExp(r'[\s\-]'), '');
    if (word.isEmpty) return 'Другое';

    // Ищем совпадения по корням (гербециды -> герб -> Гербицид)
    for (var entry in _typeRoots.entries) {
      if (word.contains(entry.key)) {
        return entry.value;
      }
    }
    return 'Другое';
  }
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
    '4-д', '2м-4х', 'мцпа'
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

      // Точное совпадение (регистр не важен)
      if (dbLower == lowerWord) return dbWord;

      // Совпадение с учётом склонений: различие только в 1–2 последних символах
      // (Пшеница / Пшеницы / Пшеницу; Тля / Тли)
      if (lowerWord.length >= 4 && dbLower.length >= 4) {
        final rootInput = lowerWord.substring(0, lowerWord.length - 2);
        final rootDb = dbLower.substring(0, dbLower.length - 2);
        if (rootInput == rootDb) return dbWord;
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
    // 1. Словарь для замены похожих кириллических символов на латиницу (для хим. формул)
  static const Map<String, String> _cyrillicToLatin = {
    'А': 'A', 'В': 'B', 'С': 'C', 'Е': 'E', 'Н': 'H', 'К': 'K', 'М': 'M', 
    'О': 'O', 'Р': 'P', 'Т': 'T', 'Х': 'X', 'а': 'a', 'с': 'c', 'е': 'e', 
    'о': 'o', 'р': 'p', 'х': 'x'
  };

  /// Очищает название ДВ: заменяет кириллицу на латиницу (если это формула),
  /// делает первую букву заглавной.
  static String cleanActiveIngredient(String raw) {
    String cleaned = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return cleaned;

    // Если строка короткая и без пробелов (похожа на формулу типа CaO, N, P2O5)
    if (cleaned.length <= 5 && !cleaned.contains(' ')) {
      final buffer = StringBuffer();
      for (int i = 0; i < cleaned.length; i++) {
        buffer.write(_cyrillicToLatin[cleaned[i]] ?? cleaned[i]);
      }
      cleaned = buffer.toString();
    }
    
    // Делаем первую букву заглавной, остальные строчными
    if (cleaned.isNotEmpty) {
      cleaned = cleaned[0].toUpperCase() + cleaned.substring(1).toLowerCase();
    }
    
    return cleaned;
  }

  /// Расстояние Левенштейна для поиска опечаток
  static int _levenshtein(String a, String b) {
    a = a.toLowerCase();
    b = b.toLowerCase();
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    List<int> v0 = List<int>.generate(b.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(b.length + 1, 0);

    for (int i = 0; i < a.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < b.length; j++) {
        int cost = (a[i] == b[j]) ? 0 : 1;
        v1[j + 1] = [v1[j] + 1, v0[j + 1] + 1, v0[j] + cost].reduce((x, y) => x < y ? x : y);
      }
      v0 = List.from(v1);
    }
    return v1[b.length];
  }

  /// Умная нормализация названия ДВ с учетом существующих в БД
  static String normalizeActiveIngredientName(String input, List<String> knownIngredients) {
    final cleaned = cleanActiveIngredient(input);
    if (cleaned.isEmpty) return '';

    // 1. Точное совпадение
    for (final known in knownIngredients) {
      if (known.toLowerCase() == cleaned.toLowerCase()) return known;
    }

    // 2. Если это короткая формула (<= 4 символов) - строгое совпадение, никаких опечаток
    if (cleaned.length <= 4) {
      return cleaned; // Не нашли точного - возвращаем как новое
    }

    // 3. Для длинных названий ищем с допуском (1 ошибка для <10 символов, 2 для >=10)
    final allowedDistance = cleaned.length < 10 ? 1 : 2;
    for (final known in knownIngredients) {
      if (_levenshtein(known, cleaned) <= allowedDistance) {
        return known;
      }
    }

    return cleaned;
  }

  /// Универсальный парсер состава
  static List<Map<String, String>> parseComposition(String? composition) {
    if (composition == null || composition.isEmpty) return [];
    
    final result = <Map<String, String>>[];
    
    // Готовим текст: убираем переносы строк, приводим к одному пробелу
    String text = composition.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();

    // Ищем глобальную единицу измерения в конце, например "(%)"
    String globalUnit = '';
    final globalUnitMatch = RegExp(r'\(([^)]+)\)\s*$').firstMatch(text);
    if (globalUnitMatch != null) {
      final possibleUnit = globalUnitMatch.group(1)!.trim();
      if (['%', 'г/л', 'г/кг', 'мл/л'].contains(possibleUnit)) {
        globalUnit = possibleUnit;
        text = text.substring(0, globalUnitMatch.start).trim(); // Отрезаем "(%)"
      }
    }

    // Разбиваем по + или ; (запятые не трогаем, это десятичные дроби)
    final parts = text.split(RegExp(r'[+;]'));

    // Регулярка для поиска "Число Единица" (например: 62,5 г/л)
    final numberUnitRegex = RegExp(r'([\d.,]+)\s*(г/л|г/кг|г/га|кг/га|мл/л|мл/га|л/га|%)', caseSensitive: false);
    
    // Регулярка для поиска в скобках (например: N (15,0 %) или N (15,0))
    final bracketRegex = RegExp(r'([A-Za-zА-Яа-яЁё0-9\-\s]+)\s*\(\s*([\d.,]+)\s*([^)]*)\s*\)');

    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;

      // Проверяем формат "Название (Число Единица)"
      final bracketMatch = bracketRegex.firstMatch(trimmed);
      if (bracketMatch != null) {
        final name = bracketMatch.group(1)!.trim();
        final qty = bracketMatch.group(2)!.replaceAll(',', '.');
        String unit = bracketMatch.group(3)!.trim();
        if (unit.isEmpty) unit = globalUnit;
        
        if (name.isNotEmpty) {
          result.add({'substance': name, 'qty': qty, 'unit': unit});
          continue;
        }
      }

      // Проверяем стандартный формат "Название Число Единица" или "Число Единица Название"
      final match = numberUnitRegex.firstMatch(trimmed);
      if (match != null) {
        final qty = match.group(1)!.replaceAll(',', '.');
        final unit = match.group(2)!;
        
        // Удаляем найденное число и единицу, чтобы получить название
        String substance = trimmed.replaceAll(match.group(0)!, '').trim();
        // Очищаем от лишних символов по краям (-, :, пробелы)
        substance = substance.replaceAll(RegExp(r'^[-+:\s]+|[-+:\s]+$'), '').trim();

        if (substance.isEmpty) substance = 'Неизвестное вещество';

        result.add({'substance': substance, 'qty': qty, 'unit': unit});
      } else {
        // Если числа нет вообще (например, "Антидот")
        result.add({'substance': trimmed, 'qty': '', 'unit': ''});
      }
    }

    return result;
  }
}