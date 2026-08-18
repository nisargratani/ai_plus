/// A simple abstraction over JSON Schema.
class AiJsonSchema {
  final String type;
  final String? description;
  final Map<String, AiJsonSchema>? properties;
  final List<String>? required;
  final AiJsonSchema? items;
  final List<dynamic>? enumValues;

  const AiJsonSchema({
    required this.type,
    this.description,
    this.properties,
    this.required,
    this.items,
    this.enumValues,
  });

  /// Creates a string schema.
  factory AiJsonSchema.string({String? description, List<String>? enumValues}) {
    return AiJsonSchema(
        type: 'string', description: description, enumValues: enumValues);
  }

  /// Creates an integer schema.
  factory AiJsonSchema.integer({String? description}) {
    return AiJsonSchema(type: 'integer', description: description);
  }

  /// Creates a number (float) schema.
  factory AiJsonSchema.number({String? description}) {
    return AiJsonSchema(type: 'number', description: description);
  }

  /// Creates a boolean schema.
  factory AiJsonSchema.boolean({String? description}) {
    return AiJsonSchema(type: 'boolean', description: description);
  }

  /// Creates an object schema.
  factory AiJsonSchema.object({
    required Map<String, AiJsonSchema> properties,
    List<String>? required,
    String? description,
  }) {
    return AiJsonSchema(
      type: 'object',
      properties: properties,
      required: required,
      description: description,
    );
  }

  /// Creates an array schema.
  factory AiJsonSchema.array({
    required AiJsonSchema items,
    String? description,
  }) {
    return AiJsonSchema(
      type: 'array',
      items: items,
      description: description,
    );
  }

  /// Converts this schema to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'type': type};
    if (description != null) map['description'] = description;
    if (properties != null) {
      map['properties'] = properties!.map((k, v) => MapEntry(k, v.toJson()));
    }
    if (required != null) map['required'] = required;
    if (items != null) map['items'] = items!.toJson();
    if (enumValues != null) map['enum'] = enumValues;
    return map;
  }
}
