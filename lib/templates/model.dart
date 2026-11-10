import 'dart:convert';
import '../builder/store.dart';
import '../units/virt_act.dart';
import '../units/virt_event.dart';

class TemplateField {
  const TemplateField(
    this.key,
    this.label,
    this.initial, {
    this.number = false,
  });
  final String key, label, initial;
  final bool number;
}

class TemplateDataset {
  const TemplateDataset(this.label, this.columns, this.rows);
  final String label;
  final Map<String, String> columns;
  final List<Map<String, dynamic>> rows;
}

class BotTemplateDraft {
  const BotTemplateDraft(this.events, this.variables);
  final List<VirtEvent> events;
  final List<VariableDefinition> variables;
}

class BotTemplate {
  const BotTemplate({
    required this.id,
    required this.name,
    required this.summary,
    required this.description,
    required this.fields,
    required this.build,
    this.dataset,
    this.requiresAdmin = false,
  });
  final String id, name, summary, description;
  final List<TemplateField> fields;
  final TemplateDataset? dataset;
  final bool requiresAdmin;
  final BotTemplateDraft Function(
    Map<String, String>,
    List<Map<String, dynamic>>,
    String,
  )
  build;
  Map<String, String> defaults() => {
    for (final field in fields) field.key: field.initial,
  };
  List<Map<String, dynamic>> sampleRows() =>
      (jsonDecode(jsonEncode(dataset?.rows ?? [])) as List)
          .cast<Map<String, dynamic>>();
}

VirtAct templateAction(
  VirtActType type,
  String text,
  String output, [
  Map<String, dynamic> config = const {},
]) => VirtAct(type: type, text: text)..config = {'output': output, ...config};
