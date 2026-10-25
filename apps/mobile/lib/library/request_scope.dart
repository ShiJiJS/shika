/// Cancels obsolete HTTP work as well as preventing its result from publishing.
class RequestScope {
  bool cancelled = false;
  final Set<void Function()> _callbacks = {};

  void add(void Function() callback) {
    if (cancelled) {
      callback();
    } else {
      _callbacks.add(callback);
    }
  }

  void remove(void Function() callback) => _callbacks.remove(callback);
  void cancel() {
    if (cancelled) return;
    cancelled = true;
    for (final callback in _callbacks.toList()) {
      callback();
    }
    _callbacks.clear();
  }
}
