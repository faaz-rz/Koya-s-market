import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../checkout/models/checkout_models.dart';
import '../models/order.dart';

extension OrderStatusUi on OrderStatus {
  String get label => switch (this) {
    OrderStatus.placed => 'Placed',
    OrderStatus.confirmed => 'Confirmed',
    OrderStatus.preparing => 'Preparing',
    OrderStatus.readyForPickup => 'Ready for pickup',
    OrderStatus.collected => 'Collected',
    OrderStatus.readyForDispatch => 'Ready for dispatch',
    OrderStatus.outForDelivery => 'Out for delivery',
    OrderStatus.delivered => 'Delivered',
    OrderStatus.cancelled => 'Cancelled',
    OrderStatus.rejected => 'Rejected',
  };

  Color get color => switch (this) {
    OrderStatus.cancelled || OrderStatus.rejected => AppColors.error,
    OrderStatus.delivered || OrderStatus.collected => AppColors.success,
    OrderStatus.readyForPickup || OrderStatus.outForDelivery => AppColors.offer,
    _ => AppColors.brand600,
  };
}

extension CustomerOrderStatusUi on CustomerOrder {
  String get customerStatusLabel => switch (status) {
    OrderStatus.readyForPickup => 'Ready for pickup',
    OrderStatus.collected => 'Collected',
    OrderStatus.delivered => 'Delivered',
    OrderStatus.cancelled => 'Cancelled',
    OrderStatus.rejected => 'Rejected',
    _ => 'Order received',
  };

  Color get customerStatusColor => switch (status) {
    OrderStatus.cancelled || OrderStatus.rejected => AppColors.error,
    OrderStatus.delivered || OrderStatus.collected => AppColors.success,
    OrderStatus.readyForPickup => AppColors.offer,
    _ => AppColors.brand600,
  };

  String get customerStatusMessage => switch (status) {
    OrderStatus.readyForPickup =>
      'Your order is packed and waiting for you at the store.',
    OrderStatus.collected => 'This order was collected successfully.',
    OrderStatus.delivered => 'This order was delivered successfully.',
    OrderStatus.cancelled => 'This order was cancelled.',
    OrderStatus.rejected => 'The store could not fulfil this order.',
    _ =>
      fulfilmentType == FulfilmentType.pickup
          ? 'We will notify you when your order is ready for pickup.'
          : 'The store has received your order.',
  };
}
