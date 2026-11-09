import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/ui/design.dart';
import 'manifest.dart';
import 'parameters_form.dart';

class PluginParametersPage extends StatelessWidget {
  const PluginParametersPage({
    super.key,
    required this.bot,
    required this.plugin,
  });
  final VirtBot bot;
  final PluginManifest plugin;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit bot parameters')),
    body: SingleChildScrollView(
      child: BContent(
        maxWidth: 840,
        child: BPanel(
          child: PluginParametersForm(
            plugin: plugin,
            setup: bot.setup!,
            onSave: (adminId, values) async {
              await context.read<BotsCubit>().updatePluginParameters(
                bot,
                adminId: adminId,
                parameters: values,
              );
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ),
      ),
    ),
  );
}
