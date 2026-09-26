/// Implemented by built-in providers that hold resources (HTTP connections)
/// which `AiClient.close` should release.
///
/// Internal to the package; not exported.
abstract interface class CloseableProvider {
  /// Releases the provider's resources.
  void close();
}
