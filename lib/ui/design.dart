import 'package:flutter/material.dart';

abstract final class BColors {
  static const canvas = Color(0xFFF7F9F8);
  static const surface = Color(0xFFFFFFFF);
  static const subtle = Color(0xFFEBF0EE);
  static const ink = Color(0xFF06525C);
  static const muted = Color(0xFF2F737D);
  static const line = Color(0xFFD5E1DC);
  static const inverseMuted = Color(0xFFC1D0D2);
  static const success = Color(0xFF276749);
  static const successWash = Color(0xFFEDF6F0);
  static const warning = Color(0xFF85551D);
  static const warningWash = Color(0xFFFCF4E7);
  static const error = Color(0xFFAC3838);
  static const errorWash = Color(0xFFFFF0EE);

  static BPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? BPalette.dark
          : BPalette.light;
}

class BPalette {
  const BPalette({
    required this.canvas,
    required this.surface,
    required this.subtle,
    required this.ink,
    required this.muted,
    required this.line,
    required this.inverseMuted,
    required this.success,
    required this.successWash,
    required this.warning,
    required this.warningWash,
    required this.error,
    required this.errorWash,
  });
  final Color canvas, surface, subtle, ink, muted, line, inverseMuted;
  final Color success, successWash, warning, warningWash, error, errorWash;

  static const light = BPalette(
    canvas: BColors.canvas,
    surface: BColors.surface,
    subtle: BColors.subtle,
    ink: BColors.ink,
    muted: BColors.muted,
    line: BColors.line,
    inverseMuted: BColors.inverseMuted,
    success: BColors.success,
    successWash: BColors.successWash,
    warning: BColors.warning,
    warningWash: BColors.warningWash,
    error: BColors.error,
    errorWash: BColors.errorWash,
  );
  static const dark = BPalette(
    canvas: Color(0xFF0E191B),
    surface: Color(0xFF17272A),
    subtle: Color(0xFF233A3D),
    ink: Color(0xFFC9F0ED),
    muted: Color(0xFF9FC6C6),
    line: Color(0xFF365255),
    inverseMuted: Color(0xFF325559),
    success: Color(0xFF8CD7AD),
    successWash: Color(0xFF183C2B),
    warning: Color(0xFFEDC68C),
    warningWash: Color(0xFF40311E),
    error: Color(0xFFFFB4AB),
    errorWash: Color(0xFF492827),
  );
}

abstract final class BottogramDesign {
  static const radius = BorderRadius.all(Radius.circular(20));
  static const controlRadius = BorderRadius.all(Radius.circular(8));

  static TextStyle text(
    double size, {
    bool strong = false,
    Color? color,
    double? height,
  }) => TextStyle(
    fontFamily: 'Host Grotesk',
    fontFamilyFallback: const ['Noto Sans Arabic'],
    fontSize: size,
    fontWeight: strong ? FontWeight.w500 : FontWeight.w400,
    fontVariations: [FontVariation('wght', strong ? 500 : 400)],
    color: color,
    height: height ?? 1.45,
    letterSpacing: size >= 28 ? -size * .035 : -.1,
  );

  static ThemeData get theme => _theme(BPalette.light, Brightness.light);
  static ThemeData get darkTheme => _theme(BPalette.dark, Brightness.dark);

  static ThemeData _theme(BPalette colors, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.ink,
      onPrimary: colors.canvas,
      primaryContainer: colors.subtle,
      onPrimaryContainer: colors.ink,
      secondary: colors.muted,
      onSecondary: colors.surface,
      secondaryContainer: colors.subtle,
      onSecondaryContainer: colors.ink,
      surface: colors.surface,
      onSurface: colors.ink,
      onSurfaceVariant: colors.muted,
      surfaceContainerLowest: colors.surface,
      surfaceContainerLow: colors.canvas,
      surfaceContainer: colors.subtle,
      surfaceContainerHigh: colors.subtle,
      surfaceContainerHighest: colors.line,
      outline: colors.line,
      outlineVariant: colors.line,
      inverseSurface: colors.ink,
      onInverseSurface: colors.canvas,
      inversePrimary: colors.canvas,
      error: colors.error,
      onError: colors.surface,
      errorContainer: colors.errorWash,
      onErrorContainer: colors.error,
    );
    final border = OutlineInputBorder(
      borderRadius: controlRadius,
      borderSide: BorderSide(color: colors.line),
    );
    const shape = RoundedRectangleBorder(borderRadius: controlRadius);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.canvas,
      fontFamily: 'Host Grotesk',
      fontFamilyFallback: const ['Noto Sans Arabic'],
      textTheme: TextTheme(
            displayLarge: text(48, strong: true, height: 1.1),
            displayMedium: text(40, strong: true, height: 1.1),
            displaySmall: text(34, strong: true, height: 1.15),
            headlineLarge: text(32, strong: true, height: 1.15),
            headlineMedium: text(28, strong: true, height: 1.2),
            headlineSmall: text(24, strong: true, height: 1.25),
            titleLarge: text(20, strong: true),
            titleMedium: text(18, strong: true),
            titleSmall: text(16, strong: true),
            bodyLarge: text(16),
            bodyMedium: text(16),
            bodySmall: text(14, color: colors.muted),
            labelLarge: text(16, strong: true),
            labelMedium: text(14, strong: true),
            labelSmall: text(13, strong: true),
          )
          .apply(bodyColor: colors.ink, displayColor: colors.ink)
          .copyWith(bodySmall: text(14, color: colors.muted)),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.canvas,
        foregroundColor: colors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 72,
        titleSpacing: 16,
        titleTextStyle: text(20, strong: true, color: colors.ink),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: colors.line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: border,
        enabledBorder: border,
        disabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: colors.ink, width: 2),
        ),
        errorBorder: border.copyWith(
          borderSide: BorderSide(color: colors.error),
        ),
        focusedErrorBorder: border.copyWith(
          borderSide: BorderSide(color: colors.error, width: 2),
        ),
        labelStyle: text(14, color: colors.muted),
        floatingLabelStyle: text(13, strong: true),
        helperStyle: text(13, color: colors.muted),
        errorStyle: text(13, color: colors.error),
        helperMaxLines: 4,
        errorMaxLines: 3,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.ink,
          foregroundColor: colors.canvas,
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: text(16, strong: true),
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.ink,
          minimumSize: const Size(48, 48),
          side: BorderSide(color: colors.line),
          textStyle: text(16, strong: true),
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.ink,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          textStyle: text(14, strong: true),
          shape: shape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colors.ink,
          minimumSize: const Size(48, 48),
          shape: shape,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.ink,
        foregroundColor: colors.canvas,
        elevation: 0,
        hoverElevation: 2,
        shape: shape,
        extendedTextStyle: text(16, strong: true),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: radius),
        titleTextStyle: text(24, strong: true, color: colors.ink),
        contentTextStyle: text(16, color: colors.ink),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.ink,
        contentTextStyle: text(14, color: colors.canvas),
        behavior: SnackBarBehavior.floating,
        shape: shape,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.subtle,
        indicatorShape: shape,
        labelTextStyle: WidgetStatePropertyAll(text(13, strong: true)),
        iconTheme: WidgetStatePropertyAll(IconThemeData(color: colors.ink)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surface,
        selectedColor: colors.subtle,
        labelStyle: text(14, color: colors.ink),
        secondaryLabelStyle: text(14, color: colors.ink),
        side: BorderSide(color: colors.line),
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      dividerTheme: DividerThemeData(
        color: colors.line,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.muted,
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.ink,
        linearTrackColor: colors.subtle,
      ),
      tooltipTheme: TooltipThemeData(
        textStyle: text(13, color: colors.canvas),
        decoration: BoxDecoration(
          color: colors.ink,
          borderRadius: controlRadius,
        ),
      ),
      visualDensity: VisualDensity.standard,
    );
  }
}

class BContent extends StatelessWidget {
  const BContent({
    super.key,
    required this.child,
    this.maxWidth = 1120,
    this.padding = const EdgeInsets.all(24),
  });
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class BHeading extends StatelessWidget {
  const BHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final words = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style:
                constraints.maxWidth < 500
                    ? Theme.of(context).textTheme.headlineMedium
                    : Theme.of(context).textTheme.displaySmall,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      );
      if (constraints.maxWidth < 600) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            words,
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: words),
          if (actions.isNotEmpty) ...[const SizedBox(width: 24), ...actions],
        ],
      );
    },
  );
}

class BPanel extends StatefulWidget {
  const BPanel({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(24),
    this.color,
    this.borderColor,
  });
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  @override
  State<BPanel> createState() => _BPanelState();
}

class _BPanelState extends State<BPanel> {
  bool _hover = false;
  bool _focus = false;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration:
        MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
    transform: Matrix4.translationValues(
      0,
      _hover && widget.onTap != null ? -2 : 0,
      0,
    ),
    child: Material(
      color: widget.color ?? BColors.of(context).surface,
      shape: RoundedRectangleBorder(
        borderRadius: BottogramDesign.radius,
        side: BorderSide(
          color:
              widget.borderColor ??
              (_hover || _focus
                  ? BColors.of(context).ink
                  : BColors.of(context).line),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child:
          widget.onTap == null
              ? Padding(padding: widget.padding, child: widget.child)
              : InkWell(
                onTap: widget.onTap,
                onHover: (value) => setState(() => _hover = value),
                onFocusChange: (value) => setState(() => _focus = value),
                child: Padding(padding: widget.padding, child: widget.child),
              ),
    ),
  );
}

class BSection extends StatelessWidget {
  const BSection({
    super.key,
    required this.title,
    required this.child,
    this.description,
    this.trailing,
  });
  final String title;
  final Widget child;
  final String? description;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          if (trailing != null) trailing!,
        ],
      ),
      if (description != null) ...[
        const SizedBox(height: 8),
        Text(description!, style: Theme.of(context).textTheme.bodySmall),
      ],
      const SizedBox(height: 16),
      child,
    ],
  );
}

class BEmptyState extends StatelessWidget {
  const BEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: BColors.of(context).subtle,
                  borderRadius: BottogramDesign.radius,
                ),
                child: Icon(icon, size: 32, color: BColors.of(context).ink),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      ),
    ),
  );
}

class BNotice extends StatelessWidget {
  const BNotice({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.error = false,
    this.trailing,
  });
  final String message;
  final IconData icon;
  final bool error;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: error ? BColors.of(context).errorWash : BColors.of(context).subtle,
      borderRadius: BottogramDesign.controlRadius,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: error ? BColors.of(context).error : BColors.of(context).ink,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: BottogramDesign.text(
              14,
              color:
                  error ? BColors.of(context).error : BColors.of(context).ink,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

class BStatus extends StatelessWidget {
  const BStatus({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.background,
  });
  final String label;
  final IconData? icon;
  final Color? color;
  final Color? background;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: background ?? BColors.of(context).subtle,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: color ?? BColors.of(context).muted),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            style: BottogramDesign.text(
              13,
              strong: true,
              color: color ?? BColors.of(context).muted,
            ),
          ),
        ),
      ],
    ),
  );
}
