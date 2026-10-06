import 'package:flutter/material.dart';
import '../../../core/theme/app_spacing.dart';
import '../models/checkout_models.dart';
import '../models/delivery_pin.dart';
import 'delivery_pin_field.dart';

class AddressEditorDialog extends StatefulWidget {
  const AddressEditorDialog({this.address, super.key});
  final CustomerAddress? address;
  @override
  State<AddressEditorDialog> createState() => _AddressEditorDialogState();
}

class _AddressEditorDialogState extends State<AddressEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _label,
      _name,
      _phone,
      _line,
      _city,
      _pincode,
      _instructions;
  DeliveryPin? _pin;
  bool _locating = false;
  bool _pinCleared = false;
  @override
  void initState() {
    super.initState();
    final a = widget.address;
    _label = TextEditingController(text: a?.label ?? 'Home');
    _name = TextEditingController(text: a?.recipientName ?? '');
    _phone = TextEditingController(text: a?.phone ?? '');
    _line = TextEditingController(text: a?.line1 ?? '');
    _city = TextEditingController(text: a?.city ?? 'Hyderabad');
    _pincode = TextEditingController(text: a?.pincode ?? '');
    _instructions = TextEditingController(text: a?.instructions ?? '');
    _pin = a?.deliveryPin;
  }

  @override
  void dispose() {
    for (final c in [
      _label,
      _name,
      _phone,
      _line,
      _city,
      _pincode,
      _instructions,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) =>
      v == null || v.trim().isEmpty ? 'This field is required' : null;
  void _addressChanged(String _) {
    if (_pin != null) {
      setState(() {
        _pin = null;
        _pinCleared = true;
      });
    }
  }

  void _save() {
    if (_locating || !_form.currentState!.validate()) return;
    Navigator.of(context).pop(
      CustomerAddress(
        id:
            widget.address?.id ??
            'address-${DateTime.now().millisecondsSinceEpoch}',
        revision: widget.address?.revision ?? 0,
        label: _label.text.trim(),
        recipientName: _name.text.trim(),
        phone: _phone.text.trim(),
        line1: _line.text.trim(),
        city: _city.text.trim(),
        pincode: _pincode.text.trim(),
        instructions: _instructions.text.trim(),
        isDefault: widget.address?.isDefault ?? false,
        deliveryPin: _pin,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.address == null ? 'Add delivery address' : 'Edit address',
    ),
    content: SizedBox(
      width: 480,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _label,
                maxLength: 40,
                validator: _required,
                decoration: const InputDecoration(labelText: 'Label'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _name,
                maxLength: 120,
                validator: _required,
                decoration: const InputDecoration(labelText: 'Recipient name'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _phone,
                maxLength: 40,
                keyboardType: TextInputType.phone,
                validator: (v) =>
                    RegExp(r'^[+0-9 ()-]{10,40}$').hasMatch(v?.trim() ?? '') &&
                        (v?.replaceAll(RegExp(r'\D'), '').length ?? 0) >= 10
                    ? null
                    : 'Enter a valid phone number',
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _line,
                enabled: !_locating,
                maxLength: 200,
                onChanged: _addressChanged,
                validator: _required,
                decoration: const InputDecoration(
                  labelText: 'Flat, building and street',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _city,
                enabled: !_locating,
                maxLength: 80,
                onChanged: _addressChanged,
                validator: _required,
                decoration: const InputDecoration(labelText: 'City'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _pincode,
                enabled: !_locating,
                maxLength: 6,
                onChanged: _addressChanged,
                keyboardType: TextInputType.number,
                validator: (v) => RegExp(r'^\d{6}$').hasMatch(v?.trim() ?? '')
                    ? null
                    : 'Enter a valid 6-digit PIN',
                decoration: const InputDecoration(labelText: 'PIN code'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _instructions,
                maxLength: 120,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Landmark or delivery instructions (optional)',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              DeliveryPinField(
                pin: _pin,
                onChanged: (pin) => setState(() {
                  _pin = pin;
                  _pinCleared = false;
                }),
                onBusyChanged: (busy) => setState(() => _locating = busy),
              ),
              if (_pinCleared)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Address changed. Capture a new pin at this address if needed.',
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _locating ? null : _save,
        child: const Text('Save'),
      ),
    ],
  );
}
