# Plant Sales App (Flutter)

Мобильное приложение для продаж средств защиты растений (СЗР). 
Переписано с Python/Kivy на Flutter для Android.

## 📱 Скриншоты

| До (Python/Kivy) и После (Flutter) |
|:------:|
|Python/Kivy|
|Диагностика|
| <img width="298" height="494" alt="png1" src="https://github.com/user-attachments/assets/a39476c9-29b0-4eb0-89e5-1d66d76a387c" /> 
  <img width="253" height="430" alt="png2" src="https://github.com/user-attachments/assets/4c7a70ac-5445-428b-b90a-f702483cafc3" /> |
|Каталог|
|<img width="241" height="402" alt="png3" src="https://github.com/user-attachments/assets/0cdd41b3-a404-4c33-a85d-0d5051ea8d6d" /> 
<img width="226" height="374" alt="png6" src="https://github.com/user-attachments/assets/50bd5506-6853-4c14-9046-f120fff72508" />
|
|Настройки|
|<img width="253" height="417" alt="png4" src="https://github.com/user-attachments/assets/00f2aa7c-bb0b-421b-a790-9bd23a857b5b" />|
|Flutter|
|Диагностика|
|<img width="1182" height="2560" alt="jpg4" src="https://github.com/user-attachments/assets/225d5441-6689-4889-80dc-49288b00ef74" />|
|Каталог|
| <img width="1182" height="2560" alt="jpg2" src="https://github.com/user-attachments/assets/61f218a9-c7c3-4c96-bd2d-0c138ef228d9" />
  <img width="1182" height="2560" alt="jpg1" src="https://github.com/user-attachments/assets/50eb53d8-2324-4a54-a658-a01eda53136c" />)|
|Настройки|
|<img width="1182" height="2560" alt="jpg3" src="https://github.com/user-attachments/assets/789e3653-4aee-4b18-a581-55a89047a64a" />) |

## ✅ Реализовано

### Общее
- Трёхвкладочная навигация (Диагностика / Каталог / Настройки)
- Сборка APK под Android

### База данных
- Локальное хранилище SQLite (`sqflite`)
- Модель `Product` с полями: название, категория, состав, производитель, упаковка, норма расхода, цена
- CRUD-операции через `DatabaseHelper`
- Очистка базы данных с подтверждением

### Каталог
- Список препаратов с прокруткой
- Поиск по названию и составу
- Фильтр по категориям (чипсы)
- Разворачивающиеся карточки с деталями
- Отображение первого действующего вещества (ДВ) на карточке
- Форматирование нормы расхода с единицами измерения

### Импорт из Excel
- Выбор `.xlsx` / `.xls` файлов
- Диалог выбора листов
- Автоопределение формата (прайс-лист / экспортированный каталог)
- Поиск колонок по ключевым словам
- Обработка дублирующихся колонок
- Валидация строк с отчётом по ошибкам
- Статистика по каждому листу

## 🚧 В разработке / запланировано

### Работа с фото и нейросети
- [ ] Съёмка фото с камеры
- [ ] Выбор фото из галереи
- [ ] Интеграция ONNX-моделей для диагностики болезней растений
- [ ] Отображение результатов распознавания

### Данные
- [ ] Импорт описаний препаратов (культуры, болезни)
- [ ] Обновление существующих препаратов из Excel
- [ ] Экспорт каталога в Excel
- [ ] Шаблоны импорта

### Прочее
- [ ] Интеграция с заказами и клиентами

## 🛠️ Технологии

- **Flutter** 3.x / Dart 3.x
- **sqflite** — локальная база данных
- **excel** — чтение Excel-файлов
- **file_picker** — выбор файлов

