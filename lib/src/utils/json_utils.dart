import 'dart:convert';

/// Encodes a tool result into the string form providers expect.
///
/// Strings are passed through unchanged. Other values are JSON-encoded;
/// objects that are not natively encodable use their `toJson()` method when
/// available and fall back to `toString()`, so a tool returning an arbitrary
/// object never crashes request serialisation.
String encodeToolResult(Object? result) {
  if (result is String) return result;
  return jsonEncode(result, toEncodable: _toEncodable);
}

Object? _toEncodable(Object? value) {
  try {
    // ignore: avoid_dynamic_calls
    return (value as dynamic).toJson();
  } on NoSuchMethodError {
    return value.toString();
  }
}

/// Decodes a JSON object string, returning an empty map when [source] is
/// empty, malformed, or not a JSON object.
///
/// Used for tool-call arguments, which models occasionally emit as invalid
/// JSON; the tool then receives no arguments rather than the whole request
/// failing.
Map<String, dynamic> decodeJsonObject(String? source) {
  if (source == null || source.trim().isEmpty) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(source);
    if (decoded is Map<String, dynamic>) return decoded;
  } on FormatException {
    // Fall through.
  }
  return <String, dynamic>{};
}
