import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProductSearchHistoryController extends Notifier<List<String>> {
  static const _maximumEntries = 6;

  @override
  List<String> build() => const [];

  void add(String value) {
    final query = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (query.length < 2) return;
    final normalized = query.toLowerCase();
    state = [
      query,
      ...state.where((entry) => entry.toLowerCase() != normalized),
    ].take(_maximumEntries).toList(growable: false);
  }

  void clear() => state = const [];
}

final productSearchHistoryProvider =
    NotifierProvider<ProductSearchHistoryController, List<String>>(
      ProductSearchHistoryController.new,
    );
