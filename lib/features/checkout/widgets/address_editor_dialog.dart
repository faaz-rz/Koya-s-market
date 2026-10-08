import 'package:flutter/material.dart';
import '../models/checkout_models.dart';
import 'address_editor_form.dart';

class AddressEditorDialog extends StatefulWidget {
  const AddressEditorDialog({this.address, super.key});
  final CustomerAddress? address;
  @override
  State<AddressEditorDialog> createState() => _AddressEditorDialogState();
}

class _AddressEditorDialogState extends State<AddressEditorDialog> {
  final _form = GlobalKey<AddressEditorFormState>();
  bool _locating = false;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.address == null ? 'Add delivery address' : 'Edit address',
    ),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: AddressEditorForm(
          key: _form,
          address: widget.address,
          showSaveButton: false,
          onLocatingChanged: (busy) => setState(() => _locating = busy),
          onSave: (saved) => Navigator.of(context).pop(saved),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('save-address'),
        onPressed: _locating ? null : () => _form.currentState?.save(),
        child: const Text('Save'),
      ),
    ],
  );
}
