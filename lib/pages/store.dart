import 'package:bottogram/l10n/strings.dart';
import 'package:bottogram/ui/design.dart';
import 'package:flutter/material.dart';
import '../templates/catalog.dart';
import '../templates/model.dart';
import '../templates/setup_page.dart';

class StorePage extends StatelessWidget {
  const StorePage({super.key, this.scrollHeader});
  final Widget? scrollHeader;

  Future<void> _openTemplate(BuildContext context, BotTemplate template) async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => TemplateSetupPage(template: template)),
    );
    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.botCreatedOpenBotsToReview)),
      );
    }
  }

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
          BHeading(
            title: context.strings.botTemplates,
            subtitle: context.strings.startWithAUsefulBotThen,
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 960
                  ? 3
                  : constraints.maxWidth >= 620
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - 20 * (columns - 1)) / columns;
              return Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  for (final template in BotTemplates.all)
                    SizedBox(
                      width: width,
                      child: _TemplateCard(
                        template: template,
                        onTap: () => _openTemplate(context, template),
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

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.onTap});
  final BotTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BColors.of(context);
    return BPanel(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.asset(
                'assets/templates/${template.id}.webp',
                fit: BoxFit.cover,
                cacheWidth: 960,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  switch (template.id) {
                    'quiz' => context.strings.storeLearning,
                    'crypto' => context.strings.storeFinance,
                    'tasks' => context.strings.storeProductivity,
                    'library' => context.strings.storeKnowledge,
                    'feedback' => context.strings.storeFeedback,
                    'requests' => context.strings.storeSupport,
                    'registration' => context.strings.events,
                    _ => context.strings.automation,
                  },
                  style: BottogramDesign.text(
                    12,
                    strong: true,
                    color: colors.muted,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  template.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 62),
                  child: Text(
                    template.summary,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.strings.useTemplate,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colors.subtle,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 20,
                        color: colors.ink,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
