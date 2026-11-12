import 'package:bottogram/l10n/strings.dart';
import 'package:bottogram/store/rmus.dart';
import 'package:bottogram/units/virt_rmu.dart';
import 'package:bottogram/ui/design.dart';
import 'package:bottogram/ui/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class TemplatesPage extends StatefulWidget {
  const TemplatesPage({super.key, required this.selectMode});
  final bool selectMode;
  @override
  State<TemplatesPage> createState() => _TemplatesPageState();
}

class _TemplatesPageState extends State<TemplatesPage> {
  bool _busy = false;
  String? _error;
  Future<void> _run(Future<void> Function() change) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await change();
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.strings.theTemplateCouldNotBeSaved);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addTemplate() async {
    final result = await showBEntryDialog<VirtRMUType>(
      context,
      title: context.strings.createKeyboardTemplate,
      fieldLabel: context.strings.templateName,
      initialType: VirtRMUType.keyboard,
      types: {
        VirtRMUType.keyboard: context.strings.replyKeyboard,
        VirtRMUType.inlineKeyboard: context.strings.inlineKeyboard,
      },
      action: context.strings.createTemplate,
    );
    if (result == null || !mounted) return;
    final VirtRMU template = result.type == VirtRMUType.keyboard
        ? VirtRMUKeyboard()
        : VirtRMUInlineKeyboard();
    template.name = result.text;
    await _run(() => context.read<RMUsCubit>().add(template));
  }

  Future<void> _remove(VirtRMU template) async {
    final accepted = await confirmRemoval(
      context,
      title: context.strings.deleteTemplate,
      message: context.strings.removeThisSavedTemplateKeyboardsAlready,
      action: context.strings.deleteTemplateAction,
    );
    if (accepted && mounted) {
      await _run(() => context.read<RMUsCubit>().remove(template));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.strings.templates)),
    body: SingleChildScrollView(
      child: BContent(
        maxWidth: 840,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BHeading(
              title: context.strings.keyboardTemplates,
              subtitle: context.strings.reuseAKeyboardWithoutRebuildingIts,
              actions: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _addTemplate,
                  icon: const Icon(Icons.add),
                  label: Text(context.strings.createTemplate),
                ),
              ],
            ),
            const SizedBox(height: 28),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: BNotice(message: _error!, error: true),
              ),
            FutureBuilder<void>(
              future: context.read<RMUsCubit>().ready,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                return BlocBuilder<RMUsCubit, List<VirtRMU>>(
                  builder: (context, templates) {
                    final storageError = context.read<RMUsCubit>().lastError;
                    if (storageError != null) {
                      return BNotice(message: storageError, error: true);
                    }
                    if (templates.isEmpty) {
                      return BEmptyState(
                        icon: Icons.bookmarks_outlined,
                        title: context.strings.aShortcutForYourNextReply,
                        message: context.strings.createAnEmptyTemplateHereOr,
                      );
                    }
                    return Column(
                      children: [
                        for (final template in templates)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: BPanel(
                              padding: EdgeInsets.zero,
                              onTap: _busy
                                  ? null
                                  : () => Navigator.pop(context, template),
                              child: ListTile(
                                leading: const Icon(Icons.keyboard_outlined),
                                title: Text(
                                  template.name ??
                                      context.strings.untitledKeyboard,
                                ),
                                subtitle: Text(
                                  template.type == VirtRMUType.inlineKeyboard
                                      ? context.strings.inlineKeyboard
                                      : context.strings.replyKeyboard,
                                ),
                                trailing: IconButton(
                                  tooltip: context.strings.deleteTemplateAction,
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: _busy
                                      ? null
                                      : () => _remove(template),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}
