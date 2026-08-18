/// A simple logger interface for the SDK.
abstract interface class AiLogger {
  void debug(String message);
  void info(String message);
  void warning(String message);
  void error(String message, {Object? error, StackTrace? stackTrace});
}

/// A default logger implementation that uses `print` (only active in debug mode by default).
class ConsoleAiLogger implements AiLogger {
  final bool enableDebug;

  const ConsoleAiLogger({this.enableDebug = false});

  @override
  void debug(String message) {
    if (enableDebug) print('[AiPlus|DEBUG] $message');
  }

  @override
  void info(String message) {
    print('[AiPlus|INFO] $message');
  }

  @override
  void warning(String message) {
    print('[AiPlus|WARNING] $message');
  }

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {
    print('[AiPlus|ERROR] $message');
    if (error != null) print(error);
    if (stackTrace != null) print(stackTrace);
  }
}
