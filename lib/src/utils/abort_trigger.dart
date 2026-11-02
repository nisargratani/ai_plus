// Internal to the package; not exported.

import 'dart:async';

/// Returns a function telling whether [trigger] has completed (with a value
/// or an error). With no trigger, it always returns `false`.
///
/// Completion is observed asynchronously, like any future: check it after an
/// `await`, not in the same synchronous step that completed the trigger.
bool Function() watchAbortTrigger(Future<void>? trigger) {
  if (trigger == null) return () => false;
  var fired = false;
  void markFired() => fired = true;
  unawaited(trigger.then((_) => markFired(), onError: (Object _) {
    markFired();
  }));
  return () => fired;
}
