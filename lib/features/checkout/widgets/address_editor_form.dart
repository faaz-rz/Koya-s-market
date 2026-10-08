import 'package:flutter/material.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/koyas_button.dart';
import '../models/checkout_models.dart';
import '../models/delivery_pin.dart';
import 'delivery_pin_field.dart';

/// Shared by first sign-in, saved addresses and checkout. Location is optional.
class AddressEditorForm extends StatefulWidget {
  const AddressEditorForm({
    required this.onSave,
    this.address,
    this.initialName = '',
    this.initialPhone = '',
    this.saving = false,
    this.saveLabel = 'Save',
    this.makeDefault = false,
    this.showSaveButton = true,
    this.onLocatingChanged,
    super.key,
  });
  final ValueChanged<CustomerAddress> onSave;
  final CustomerAddress? address;
  final String initialName, initialPhone, saveLabel;
  final bool saving, makeDefault;
  final bool showSaveButton;
  final ValueChanged<bool>? onLocatingChanged;
  @override
  AddressEditorFormState createState() => AddressEditorFormState();
}

class AddressEditorFormState extends State<AddressEditorForm> {
  final _form = GlobalKey<FormState>();
  final _focus = <Key, FocusNode>{
    for (final name in ['line', 'city', 'pincode', 'name', 'phone', 'label'])
      Key('address-$name'): FocusNode(),
  };
  bool _submitted = false;
  late final TextEditingController _label,
      _name,
      _phone,
      _line,
      _city,
      _pincode,
      _instructions;
  DeliveryPin? _pin;
  bool _locating = false, _pinCleared = false;
  @override
  void initState() {
    super.initState();
    final a = widget.address;
    _label = TextEditingController(text: a?.label ?? 'Home');
    _name = TextEditingController(text: a?.recipientName ?? widget.initialName);
    _phone = TextEditingController(text: a?.phone ?? widget.initialPhone);
    _line = TextEditingController(text: a?.line1 ?? '');
    _city = TextEditingController(text: a?.city ?? 'Hyderabad');
    _pincode = TextEditingController(text: a?.pincode ?? '');
    _instructions = TextEditingController(text: a?.instructions ?? '');
    _pin = a?.deliveryPin;
  }

  @override
  void dispose() {
    for (final node in _focus.values) {
      node.dispose();
    }
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

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required' : null;
  void _addressChanged(String _) {
    if (_pin != null) {
      setState(() {
        _pin = null;
        _pinCleared = true;
      });
    }
  }

  void save() {
    if (widget.saving || _locating) return;
    final invalid = _form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      setState(() => _submitted = true);
      final first = invalid.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !first.mounted) return;
        _focus[first.widget.key]?.requestFocus();
        Scrollable.ensureVisible(
          first.context,
          alignment: 0.25,
          duration:
              MediaQuery.disableAnimationsOf(context) ||
                  MediaQuery.accessibleNavigationOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
        );
      });
      return;
    }
    FocusScope.of(context).unfocus();
    widget.onSave(
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
        isDefault: widget.makeDefault || (widget.address?.isDefault ?? false),
        deliveryPin: _pin,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    autovalidateMode: _submitted
        ? AutovalidateMode.onUserInteraction
        : AutovalidateMode.disabled,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeliveryPinField(
          pin: _pin,
          enabled: !widget.saving,
          onChanged: (pin) => setState(() {
            _pin = pin;
            _pinCleared = false;
          }),
          onBusyChanged: (busy) {
            setState(() => _locating = busy);
            widget.onLocatingChanged?.call(busy);
          },
        ),
        if (_pinCleared)
          const Text(
            'Address changed. Capture a new pin at this address if needed.',
          ),
        const SizedBox(height: AppSpacing.lg),
        TextFormField(
          key: const Key('address-line'),
          focusNode: _focus[const Key('address-line')],
          controller: _line,
          enabled: !widget.saving && !_locating,
          maxLength: 200,
          onChanged: _addressChanged,
          validator: _required,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Flat, building and street',
            counterText: '',
            errorMaxLines: 2,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          key: const Key('address-city'),
          focusNode: _focus[const Key('address-city')],
          controller: _city,
          enabled: !widget.saving && !_locating,
          maxLength: 80,
          onChanged: _addressChanged,
          validator: _required,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'City',
            counterText: '',
            errorMaxLines: 2,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          key: const Key('address-pincode'),
          focusNode: _focus[const Key('address-pincode')],
          controller: _pincode,
          enabled: !widget.saving && !_locating,
          maxLength: 6,
          onChanged: _addressChanged,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          validator: (v) => RegExp(r'^\d{6}$').hasMatch(v?.trim() ?? '')
              ? null
              : 'Enter a valid 6-digit PIN',
          decoration: const InputDecoration(
            labelText: 'PIN code',
            counterText: '',
            errorMaxLines: 2,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: _instructions,
          enabled: !widget.saving,
          maxLength: 120,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Landmark (optional)',
            counterText: '',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          key: const Key('address-name'),
          focusNode: _focus[const Key('address-name')],
          controller: _name,
          enabled: !widget.saving,
          maxLength: 120,
          validator: _required,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          decoration: const InputDecoration(
            labelText: 'Recipient name',
            counterText: '',
            errorMaxLines: 2,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          key: const Key('address-phone'),
          focusNode: _focus[const Key('address-phone')],
          controller: _phone,
          enabled: !widget.saving,
          maxLength: 40,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.telephoneNumber],
          validator: (v) =>
              RegExp(r'^[+0-9 ()-]{10,40}$').hasMatch(v?.trim() ?? '') &&
                  (v?.replaceAll(RegExp(r'\D'), '').length ?? 0) >= 10
              ? null
              : 'Enter a valid phone number',
          decoration: const InputDecoration(
            labelText: 'Phone',
            counterText: '',
            errorMaxLines: 2,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: 8,
          children: ['Home', 'Work', 'Other']
              .map(
                (label) => ChoiceChip(
                  label: Text(label),
                  selected: _label.text == label,
                  onSelected: widget.saving
                      ? null
                      : (_) => setState(() => _label.text = label),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          key: const Key('address-label'),
          focusNode: _focus[const Key('address-label')],
          controller: _label,
          enabled: !widget.saving,
          maxLength: 40,
          validator: _required,
          decoration: const InputDecoration(
            labelText: 'Label',
            counterText: '',
            errorMaxLines: 2,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (widget.showSaveButton)
          KoyasButton(
            key: const Key('save-address'),
            label: widget.saveLabel,
            loading: widget.saving,
            onPressed: _locating ? null : save,
          ),
      ],
    ),
  );
}
