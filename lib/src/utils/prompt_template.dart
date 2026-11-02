/// A lightweight template engine for constructing prompts.
///
/// Supports simple variable substitution using `{{variable}}` syntax.
/// Whitespace inside the braces is allowed (`{{ variable }}`). Variables are
/// validated at render time — missing variables throw an [ArgumentError].
///
/// ```dart
/// final template = AiPromptTemplate(
///   'Summarize this text:\n\n{{text}}',
/// );
///
/// final prompt = template.render({'text': 'Flutter is a UI toolkit...'});
/// ```
class AiPromptTemplate {
  /// The raw template string with `{{variable}}` placeholders.
  final String template;

  /// Creates a prompt template.
  const AiPromptTemplate(this.template);

  /// The one pattern used both to list and to substitute variables, so a
  /// placeholder is either rendered or reported as missing, never silently
  /// left in the output.
  static final _variablePattern = RegExp(r'\{\{\s*(\w+)\s*\}\}');

  /// The set of variable names found in this template.
  Set<String> get variables =>
      _variablePattern.allMatches(template).map((m) => m.group(1)!).toSet();

  /// Renders the template by replacing all `{{variable}}` placeholders
  /// with values from [values].
  ///
  /// Substitution is single-pass: placeholders that appear inside inserted
  /// values are left as-is, so untrusted input cannot expand other
  /// variables. Extra entries in [values] are ignored.
  ///
  /// Throws [ArgumentError] if any template variable is missing from [values].
  String render(Map<String, String> values) {
    final missingVars = variables.difference(values.keys.toSet());

    if (missingVars.isNotEmpty) {
      throw ArgumentError(
        'Missing template variables: ${missingVars.join(', ')}',
      );
    }

    return template.replaceAllMapped(
      _variablePattern,
      (m) => values[m.group(1)!]!,
    );
  }

  @override
  String toString() => 'AiPromptTemplate(variables: $variables)';
}
