import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/order.dart';
import 'order_manager.dart';

enum ActiveOrderMode { none, draft, editing }

class OrderManager {
  static final OrderManager instance = OrderManager._internal();
  OrderManager._internal();

  final ValueNotifier<Order?> activeOrder = ValueNotifier(null);
  final ValueNotifier<ActiveOrderMode> activeMode = ValueNotifier(ActiveOrderMode.none);
  final ValueNotifier<bool> isSyncedWithCalculator = ValueNotifier<bool>(false);

  int? editingOrderId;

  // Оставляем старый метод для совместимости с калькулятором
  void startNewOrder() {
    activeOrder.value = Order(
      id: null,
      clientName: '',
      orderDate: DateTime.now(),
      items: [],
      status: 'Новый',
    );
    activeMode.value = ActiveOrderMode.draft;
    editingOrderId = null;
  }

  // Оставляем старый метод для совместимости со списком заказов
  void setActiveOrder(Order order) {
    if (order.id == null) {
      activeOrder.value = order;
      activeMode.value = ActiveOrderMode.draft;
    } else {
      activeOrder.value = order.copyWith();
      activeMode.value = ActiveOrderMode.editing;
      editingOrderId = order.id;
    }
  }

  void updateItems(List<OrderItem> newItems) {
    if (activeOrder.value != null) {
      activeOrder.value = activeOrder.value!.copyWith(items: newItems);
    }
  }

  void clearActiveOrder() {
    activeOrder.value = null;
    activeMode.value = ActiveOrderMode.none;
    isSyncedWithCalculator.value = false;
    editingOrderId = null;
  }
}