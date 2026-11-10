import 'package:bottogram/ui/design.dart';
import 'package:flutter/material.dart';
import '../templates/catalog.dart';
import '../templates/setup_page.dart';

class StorePage extends StatelessWidget {
  const StorePage({super.key, this.scrollHeader});
  final Widget? scrollHeader;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: BContent(
      padding: EdgeInsets.fromLTRB(
        24,
        scrollHeader == null ? 24 : 16,
        24,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (scrollHeader != null) scrollHeader!,
          const BHeading(
            title: 'Bot templates',
            subtitle:
                'Start with a useful bot, then make its events and actions your own.',
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 850
                  ? (constraints.maxWidth - 16) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final template in BotTemplates.all)
                    SizedBox(
                      width: width,
                      child: BPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              template.name,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(template.summary),
                            const SizedBox(height: 20),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.arrow_forward, size: 18),
                              label: const Text('Use template'),
                              onPressed: () async {
                                final created = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        TemplateSetupPage(template: template),
                                  ),
                                );
                                if (created == true && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Bot created. Open Bots to review its actions and start it.',
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}
