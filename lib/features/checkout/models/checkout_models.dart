enum FulfilmentType { pickup, delivery }

enum PaymentMethod { cashOnDelivery, payAtStore, online }

class CustomerAddress {
  const CustomerAddress({
    required this.id,
    this.revision = 0,
    required this.label,
    required this.recipientName,
    required this.phone,
    required this.line1,
    required this.city,
    required this.pincode,
    this.instructions = '',
    this.isDefault = false,
  });

  final String id;
  final int revision;
  final String label;
  final String recipientName;
  final String phone;
  final String line1;
  final String city;
  final String pincode;
  final String instructions;
  final bool isDefault;

  String get formatted => '$line1, $city – $pincode';

  CustomerAddress copyWith({
    int? revision,
    String? label,
    String? recipientName,
    String? phone,
    String? line1,
    String? city,
    String? pincode,
    String? instructions,
    bool? isDefault,
  }) {
    return CustomerAddress(
      id: id,
      revision: revision ?? this.revision,
      label: label ?? this.label,
      recipientName: recipientName ?? this.recipientName,
      phone: phone ?? this.phone,
      line1: line1 ?? this.line1,
      city: city ?? this.city,
      pincode: pincode ?? this.pincode,
      instructions: instructions ?? this.instructions,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}

class FulfilmentSlot {
  const FulfilmentSlot({required this.id, required this.label});

  final String id;
  final String label;
}
