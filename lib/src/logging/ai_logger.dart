/// A simple logger interface for the SDK.
///
/// Implement it to route SDK logs into your own logging setup
/// (`package:logging`, Crashlytics, ...). The SDK only logs request
/// metadata, never message contents or API keys.
abstract interface class AiLogger {
  /// Verbose diagnostics, e.g. stream completion timings.
  void debug(String message);

  /// Normal operational events, e.g. a request being sent.
  void info(String message);

  /// Recoverable problems, e.g. a request being retried.
  void warning(String message);

  /// Failures, with the originating [error] and [stackTrace] when available.
  void error(String message, {Object? error, StackTrace? stackTrace});
}

/// A logger that writes to standard output with `print`.
///
/// Info, warning and error messages are always printed; debug messages only
/// when [enableDebug] is `true`.
class ConsoleAiLogger implements AiLogger {
  /// Whether [debug] messages are printed.
  final bool enableDebug;

  /// Creates a console logger.
  const ConsoleAiLogger({this.enableDebug = false});

  @override
  void debug(String message) {
    if (enableDebug) _print('[AiPlus|DEBUG] $message');
  }

  @override
  void info(String message) => _print('[AiPlus|INFO] $message');

  @override
  void warning(String message) => _print('[AiPlus|WARNING] $message');

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {
    _print('[AiPlus|ERROR] $message');
    if (error != null && !message.contains('$error')) _print('$error');
    // Stack traces are verbose; only print them in debug mode.
    if (enableDebug && stackTrace != null) _print('$stackTrace');
  }

  static void _print(String line) => print(line);
}
