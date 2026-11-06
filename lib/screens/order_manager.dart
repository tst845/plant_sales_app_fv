import 'package:flutter/material.dart';
import '../models/order.dart';
import 'calculator_manager.dart';

class OrderManager {
  static final OrderManager instance = OrderManager._internal();
  OrderManager._internal();

  // Текущий редактируемый заказ (черновик)
  final ValueNotifier<Order?> activeOrder = ValueNotifier<Order?>(null);
  
  // Флаг, включена ли синхронизация с калькулятором
  final ValueNotifier<bool> isSyncedWithCalculator = ValueNotifier<bool>(false);

  void startNewOrder() {
    activeOrder.value = Order(
      clientName: '',
      orderDate: DateTime.now(),
      status: 'Новый',
      items: [],
    );
    isSyncedWithCalculator.value = false;
  }

  void setActiveOrder(Order? order) {
    activeOrder.value = order;
    isSyncedWithCalculator.value = false;
  }

  void clearActiveOrder() {
    activeOrder.value = null;
    isSyncedWithCalculator.value = false;
  }

  // Обновление списка препаратов (вызывается из калькулятора или заказа)
  void updateItems(List<OrderItem> newItems) {
    final current = activeOrder.value;
    if (current == null) return;
    
    activeOrder.value = Order(
      id: current.id,
      clientName: current.clientName,
      orderDate: current.orderDate,
      status: current.status,
      notes: current.notes,
      items: newItems,
    );
  }
  
  // // Добавление списка OrderItem в активный заказ
  // void addItemsToActiveOrder(List<OrderItem> newItems) {
  //   final order = activeOrder.value;
  //   if (order == null) return;

  //   final List<OrderItem> updatedItems = List.from(order.items);

  //   for (var newItem in newItems) {
  //     final idx = updatedItems.indexWhere((o) => o.productId == newItem.productId);
  //     if (idx != -1) {
  //       updatedItems[idx] = newItem; // Обновляем
  //     } else {
  //       updatedItems.add(newItem); // Добавляем
  //     }
  //   }

  //   activeOrder.value = Order(
  //     id: order.id,
  //     clientName: order.clientName,
  //     orderDate: order.orderDate,
  //     status: order.status,
  //     notes: order.notes,
  //     items: updatedItems,
  //   );
  // }
}