// lib\services\filter_manager.dart
import 'package:flutter/material.dart';

class FilterManager {
  static final FilterManager instance = FilterManager._internal();
  FilterManager._internal();

  // Триггер для каталога: при изменении значения каталог применит новые фильтры
  final ValueNotifier<int> applyTrigger = ValueNotifier<int>(0);

  // Данные для фильтрации (будут заполняться из диагностики)
  Set<String> speciesToFilter = {};
  Set<String> diseasesToFilter = {};

  void applyNewFilters(Set<String> species, Set<String> diseases) {
    speciesToFilter = species;
    diseasesToFilter = diseases;
    applyTrigger.value++; // Оповещаем каталог
  }
}