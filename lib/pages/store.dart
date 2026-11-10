import 'package:bottogram/ui/design.dart';
import 'package:flutter/material.dart';

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
          const BHeading(title: 'Store'),
          const SizedBox(height: 48),
          const BEmptyState(
            icon: Icons.storefront_outlined,
            title: 'No templates yet',
            message: 'Ready-made bot templates will appear here.',
          ),
        ],
      ),
    ),
  );
}
