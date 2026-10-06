import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/four_dot_loader.dart';
import '../../products/models/product.dart';

/// Keep adjustments local until Save. Button-only edits use an atomic delta;
/// a typed physical count keeps the revision that was visible when editing.
class StockQuantityEditor extends StatefulWidget {
  const StockQuantityEditor({
    required this.product,
    required this.busy,
    required this.onSetStock,
    required this.onAdjustStock,
    super.key,
  });

  final Product product;
  final bool busy;
  final Future<bool> Function(Product product, int quantity) onSetStock;
  final Future<bool> Function(Product product, int delta) onAdjustStock;

  @override
  State<StockQuantityEditor> createState() => _StockQuantityEditorState();
}

class _StockQuantityEditorState extends State<StockQuantityEditor> {
  late final TextEditingController _controller;
  late Product _baseline;
  bool _typed = false;
  bool _saving = false;
  String? _error;

  int? get _quantity => int.tryParse(_controller.text.trim());
  bool get _dirty => _controller.text != '${_baseline.stockQuantity}';
  bool get _busy => widget.busy || _saving;
  bool get _stale => _typed && widget.product.revision != _baseline.revision;

  @override
  void initState() {
    super.initState();
    _baseline = widget.product;
    _controller = TextEditingController(text: '${_baseline.stockQuantity}');
  }

  @override
  void didUpdateWidget(covariant StockQuantityEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_saving) return;
    if (!_dirty) {
      _reset();
    } else if (!_typed && _quantity != null) {
      final delta = _quantity! - _baseline.stockQuantity;
      _baseline = widget.product;
      _controller.text = '${_baseline.stockQuantity + delta}';
    }
  }

  void _reset() {
    _baseline = widget.product;
    _controller.text = '${_baseline.stockQuantity}';
    _typed = false;
    _error = null;
  }

  void _step(int delta) {
    final next = (_quantity ?? _baseline.stockQuantity) + delta;
    if (next < 0 || next > 999999) return;
    setState(() {
      _controller.text = '$next';
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_busy || !_dirty || !widget.product.active || _stale) return;
    final quantity = _quantity;
    if (quantity == null || quantity < 0 || quantity > 999999) {
      setState(() => _error = 'Enter a whole number from 0 to 999999.');
      return;
    }
    final delta = quantity - _baseline.stockQuantity;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = !_typed && delta.abs() <= 1000
          ? await widget.onAdjustStock(_baseline, delta)
          : await widget.onSetStock(_baseline, quantity);
      if (mounted) {
        setState(() {
          if (saved) {
            _reset();
          } else {
            _error = 'Not saved. Check stock before retrying.';
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Not saved. Check stock before retrying.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !_busy && widget.product.active;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton.outlined(
              key: Key('admin-stock-decrease-${widget.product.id}'),
              tooltip: 'Decrease ${widget.product.name} stock',
              onPressed: enabled && (_quantity ?? 0) > 0
                  ? () => _step(-1)
                  : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            SizedBox(
              width: 112,
              child: TextField(
                key: Key('admin-stock-quantity-${widget.product.id}'),
                controller: _controller,
                enabled: enabled,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  labelText: 'Total stock',
                  counterText: '',
                  isDense: true,
                ),
                onChanged: (_) => setState(() {
                  _typed = true;
                  _error = null;
                }),
                onSubmitted: (_) => _save(),
              ),
            ),
            IconButton.filledTonal(
              key: Key('admin-stock-increase-${widget.product.id}'),
              tooltip: 'Increase ${widget.product.name} stock',
              onPressed: enabled && (_quantity ?? 0) < 999999
                  ? () => _step(1)
                  : null,
              icon: const Icon(Icons.add_rounded),
            ),
            FilledButton(
              key: Key('admin-stock-save-${widget.product.id}'),
              onPressed: enabled && _dirty && !_stale ? _save : null,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: FourDotLoader(size: 20),
                    )
                  : const Text('Save'),
            ),
            if (_dirty && !_busy)
              TextButton(
                key: Key('admin-stock-reset-${widget.product.id}'),
                onPressed: () => setState(_reset),
                child: const Text('Reset'),
              ),
          ],
        ),
        if (_stale || _error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _stale ? 'Stock changed. Reset to the latest count.' : _error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}
