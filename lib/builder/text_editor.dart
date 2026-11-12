import 'package:bottogram/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'values.dart';

class TelegramTextEditor extends StatefulWidget {
  const TelegramTextEditor({
    super.key,
    required this.controller,
    this.references = const [],
    this.markdown = true,
    this.label = 'Message',
  });
  final TextEditingController controller;
  final List<String> references;
  final bool markdown;
  final String label;
  @override
  State<TelegramTextEditor> createState() => _TelegramTextEditorState();
}

class _TelegramTextEditorState extends State<TelegramTextEditor> {
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void insert(String before, String after, {String placeholder = 'text'}) {
    final controller = widget.controller;
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : controller.text.length;
    final end = selection.isValid ? selection.end : start;
    final selected = controller.text.substring(start, end);
    final content = selected.isEmpty ? placeholder : selected;
    final replacement = '$before$content$after';
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(start, end, replacement),
      selection: TextSelection(
        baseOffset: start + before.length,
        extentOffset: start + before.length + content.length,
      ),
    );
    _focus.requestFocus();
  }

  Future<void> _variable() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.strings.insertValue),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: context.strings.valuePath,
                  hintText: 'steps.lookup.body.price',
                  helperText: context.strings.useAFieldFromAnEarlier,
                ),
              ),
              if (widget.references.isNotEmpty)
                SizedBox(
                  height: 220,
                  child: ListView(
                    children: [
                      for (final path in widget.references)
                        ListTile(
                          dense: true,
                          title: Text(path),
                          onTap: () => Navigator.pop(context, path),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.strings.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (RegExp(
                r'^[a-zA-Z_][a-zA-Z0-9_.]*$',
              ).hasMatch(controller.text.trim())) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: Text(context.strings.insert),
          ),
        ],
      ),
    );
    // Dialog exit animations may still read the controller during this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (value != null && mounted) insert('{{', '}}', placeholder: value);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (widget.markdown) ...[
                      _button(
                        context.strings.bold,
                        Icons.format_bold,
                        '*',
                        '*',
                      ),
                      _button(
                        context.strings.italic,
                        Icons.format_italic,
                        '_',
                        '_',
                      ),
                      _button(
                        context.strings.underline,
                        Icons.format_underlined,
                        '__',
                        '__',
                      ),
                      _button(
                        context.strings.strikethrough,
                        Icons.format_strikethrough,
                        '~',
                        '~',
                      ),
                      _button(
                        context.strings.spoiler,
                        Icons.visibility_off_outlined,
                        '||',
                        '||',
                      ),
                      _button(context.strings.inlineCode, Icons.code, '`', '`'),
                      _button(
                        context.strings.codeBlock,
                        Icons.integration_instructions_outlined,
                        '```\n',
                        '\n```',
                      ),
                      PopupMenuButton<String>(
                        tooltip: context.strings.moreFormatting,
                        icon: const Icon(Icons.more_horiz),
                        onSelected: (value) {
                          switch (value) {
                            case 'link':
                              insert(
                                '[',
                                '](https://example.com)',
                                placeholder: 'link text',
                              );
                            case 'mention':
                              insert(
                                '[',
                                '](tg://user?id=123456789)',
                                placeholder: 'name',
                              );
                            case 'emoji':
                              insert(
                                '![',
                                '](tg://emoji?id=5368324170671202286)',
                                placeholder: '🙂',
                              );
                            case 'quote':
                              insert('\n>', '\n', placeholder: 'quoted text');
                            case 'expandable':
                              insert(
                                '\n**>',
                                '||\n',
                                placeholder: 'expandable quote',
                              );
                            case 'code':
                              insert(
                                '```python\n',
                                '\n```',
                                placeholder: 'print("Hello")',
                              );
                            case 'escape':
                              final selected = widget.controller.selection;
                              if (selected.isValid && !selected.isCollapsed) {
                                final text = selected.textInside(
                                  widget.controller.text,
                                );
                                final escaped = BuilderValues.escapeMarkdown(
                                  text,
                                );
                                widget.controller.value = TextEditingValue(
                                  text: widget.controller.text.replaceRange(
                                    selected.start,
                                    selected.end,
                                    escaped,
                                  ),
                                  selection: TextSelection.collapsed(
                                    offset: selected.start + escaped.length,
                                  ),
                                );
                              }
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'link',
                            child: Text(context.strings.link),
                          ),
                          PopupMenuItem(
                            value: 'mention',
                            child: Text(context.strings.mentionByUserID),
                          ),
                          PopupMenuItem(
                            value: 'quote',
                            child: Text(context.strings.blockQuote),
                          ),
                          PopupMenuItem(
                            value: 'expandable',
                            child: Text(context.strings.expandableQuote),
                          ),
                          PopupMenuItem(
                            value: 'code',
                            child: Text(context.strings.codeBlockWithLanguage),
                          ),
                          PopupMenuItem(
                            value: 'emoji',
                            child: Text(
                              context.strings.customEmojiRequiresEligibility,
                            ),
                          ),
                          PopupMenuItem(
                            value: 'escape',
                            child: Text(
                              context.strings.escapeSelectedPlainText,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: context.strings.insertVariableOrStepOutput,
              onPressed: _variable,
              icon: const Icon(Icons.data_object),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: widget.controller,
        focusNode: _focus,
        minLines: 5,
        maxLines: 16,
        keyboardType: TextInputType.multiline,
        decoration: InputDecoration(
          labelText: widget.label,
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        widget.markdown
            ? context.strings.telegramMarkdownV2EscapePunctuationInLiteral
            : context.strings.plainTextInsertValuesFromThe,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );

  Widget _button(String label, IconData icon, String before, String after) =>
      IconButton(
        tooltip: label,
        onPressed: () => insert(before, after),
        icon: Icon(icon, size: 20),
      );
}
