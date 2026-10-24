import 'package:flutter/foundation.dart';

import '../../library/models.dart';

/// A selection is an ID snapshot; late all-selection never replaces a newer
/// manual choice, query, source or connection. Cancelling preserves prior IDs.
class CatalogSelection extends ChangeNotifier {
  CatalogSelection({required this.connection, required this.cancelRead});
  final Object Function() connection;
  final VoidCallback cancelRead;
  final ids = <String>{};
  bool loading = false, _disposed = false;
  String error = '';
  int _generation = 0;

  void cancel({bool clear = false}) {
    _generation++;
    if (loading) cancelRead();
    loading = false;
    error = '';
    if (clear) ids.clear();
    if (!_disposed) notifyListeners();
  }

  void toggle(String id) {
    cancel();
    ids.contains(id) ? ids.remove(id) : ids.add(id);
    notifyListeners();
  }

  Future<void> all(Future<Set<String>> Function() read) async {
    cancel();
    final current = ++_generation, owner = connection();
    loading = true;
    notifyListeners();
    try {
      final result = await read();
      if (_disposed ||
          current != _generation ||
          !identical(owner, connection())) {
        return;
      }
      ids
        ..clear()
        ..addAll(result);
    } on RequestCancelled {
      // Explicit cancellation leaves the prior selection intact.
    } catch (failure) {
      if (!_disposed &&
          current == _generation &&
          identical(owner, connection())) {
        error = '全选未完成，原选择已保留：$failure';
      }
    } finally {
      if (!_disposed && current == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}
