/// A lightweight template engine for constructing prompts.
///
/// Supports simple variable substitution using `{{variable}}` syntax.
/// Variables are validated at render time — missing variables throw
/// an [ArgumentError].
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

  /// The set of variable names found in this template.
  Set<String> get variables {
    final regex = RegExp(r'\{\{(\w+)\}\}');
    return regex.allMatches(template).map((m) => m.group(1)!).toSet();
  }

  /// Renders the template by replacing all `{{variable}}` placeholders
  /// with values from [values].
  ///
  /// Throws [ArgumentError] if any template variable is missing from [values].
  String render(Map<String, String> values) {
    final requiredVars = variables;
    final missingVars = requiredVars.difference(values.keys.toSet());

    if (missingVars.isNotEmpty) {
      throw ArgumentError(
        'Missing template variables: ${missingVars.join(', ')}',
      );
    }

    String result = template;
    for (final entry in values.entries) {
      result = result.replaceAll('{{${entry.key}}}', entry.value);
    }
    return result;
  }

  @override
  String toString() => 'AiPromptTemplate(variables: $variables)';
}
