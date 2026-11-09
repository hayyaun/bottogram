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
        setState(
          () =>
              _error = 'The template could not be saved or removed. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addTemplate() async {
    final result = await showBEntryDialog<VirtRMUType>(
      context,
      title: 'Create keyboard template',
      fieldLabel: 'Template name',
      initialType: VirtRMUType.keyboard,
      types: const {
        VirtRMUType.keyboard: 'Reply keyboard',
        VirtRMUType.inlineKeyboard: 'Inline keyboard',
      },
      action: 'Create template',
    );
    if (result == null || !mounted) return;
    final VirtRMU template =
        result.type == VirtRMUType.keyboard
            ? VirtRMUKeyboard()
            : VirtRMUInlineKeyboard();
    template.name = result.text;
    await _run(() => context.read<RMUsCubit>().add(template));
  }

  Future<void> _remove(VirtRMU template) async {
    final accepted = await confirmRemoval(
      context,
      title: 'Delete template?',
      message:
          'Remove this saved template? Keyboards already attached to actions keep their own copies.',
      action: 'Delete template',
    );
    if (accepted && mounted) {
      await _run(() => context.read<RMUsCubit>().remove(template));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Templates')),
    body: SingleChildScrollView(
      child: BContent(
        maxWidth: 840,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BHeading(
              title: 'Keyboard templates',
              subtitle: 'Reuse a keyboard without rebuilding its buttons.',
              actions: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _addTemplate,
                  icon: const Icon(Icons.add),
                  label: const Text('Create template'),
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
                      return const BEmptyState(
                        icon: Icons.bookmarks_outlined,
                        title: 'A shortcut for your next reply',
                        message:
                            'Create an empty template here, or save a finished keyboard from the action editor.',
                      );
                    }
                    return Column(
                      children: [
                        for (final template in templates)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: BPanel(
                              padding: EdgeInsets.zero,
                              onTap:
                                  _busy
                                      ? null
                                      : () => Navigator.pop(context, template),
                              child: ListTile(
                                leading: const Icon(Icons.keyboard_outlined),
                                title: Text(
                                  template.name ?? 'Untitled keyboard',
                                ),
                                subtitle: Text(
                                  template.type == VirtRMUType.inlineKeyboard
                                      ? 'Inline keyboard'
                                      : 'Reply keyboard',
                                ),
                                trailing: IconButton(
                                  tooltip: 'Delete template',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed:
                                      _busy ? null : () => _remove(template),
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
