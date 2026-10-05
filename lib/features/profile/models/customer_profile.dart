class CustomerProfile {
  const CustomerProfile({
    required this.id,
    this.revision = 0,
    required this.name,
    required this.email,
    required this.phone,
  });

  final String id;
  final int revision;
  final String name;
  final String email;
  final String phone;

  CustomerProfile copyWith({
    String? name,
    String? email,
    String? phone,
    int? revision,
  }) {
    return CustomerProfile(
      id: id,
      revision: revision ?? this.revision,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
    );
  }
}
