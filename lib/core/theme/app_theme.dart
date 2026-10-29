import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

abstract final class AppTheme {
  static ThemeData light() => _build(AppColors.light, Brightness.light);
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: c.accent,
          brightness: brightness,
        ).copyWith(
          primary: c.primary,
          onPrimary: c.onPrimary,
          secondary: c.accent,
          surface: c.surface,
          onSurface: c.ink,
          error: c.bad,
          outline: c.line,
          surfaceTint: Colors.transparent,
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: kFontFamily,
      scaffoldBackgroundColor: c.background,
      splashFactory: InkSparkle.splashFactory,
      extensions: [c],
    );

    final text = _textTheme(base.textTheme, c);
    const stadium = StadiumBorder();

    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: brightness == Brightness.light
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          disabledBackgroundColor: c.surfaceAlt,
          disabledForegroundColor: c.inkFaint,
          minimumSize: const Size.fromHeight(58),
          elevation: 0,
          textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          shape: stadium,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          backgroundColor: c.surface,
          minimumSize: const Size.fromHeight(58),
          side: BorderSide(color: c.line),
          textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          shape: stadium,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.ink,
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          shape: stadium,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: c.ink),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        elevation: 0,
        highlightElevation: 0,
        shape: stadium,
        extendedTextStyle: text.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        hintStyle: text.bodyMedium?.copyWith(color: c.inkFaint),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: c.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: c.ink, width: 1.2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        selectedColor: c.primary,
        secondarySelectedColor: c.primary,
        side: BorderSide(color: c.line),
        labelStyle: text.labelLarge?.copyWith(color: c.ink),
        secondaryLabelStyle: text.labelLarge?.copyWith(color: c.onPrimary),
        checkmarkColor: c.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: stadium,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(stadium),
          // Outline only: the choice reads by weight and colour, not by a
          // filled pill.
          side: WidgetStatePropertyAll(BorderSide(color: c.line)),
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.ink : c.inkFaint,
          ),
          textStyle: WidgetStatePropertyAll(
            text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(0, 46)),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.onPrimary,
        unselectedLabelColor: c.inkMuted,
        labelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: text.labelLarge,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        indicator: ShapeDecoration(color: c.primary, shape: stadium),
        splashBorderRadius: BorderRadius.circular(Radii.pill),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.leaf,
        linearTrackColor: c.surfaceAlt,
        circularTrackColor: c.surfaceAlt,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        showDragHandle: true,
        dragHandleColor: c.line,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.background),
        shape: stadium,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onPrimary : c.inkFaint,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.ink : c.surfaceAlt,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.ink,
        thumbColor: c.ink,
        inactiveTrackColor: c.surfaceAlt,
        overlayColor: c.ink.withValues(alpha: 0.08),
        trackHeight: 4,
        valueIndicatorColor: c.ink,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.ink,
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base, AppColors c) {
    TextStyle? s(
      TextStyle? t,
      double size,
      FontWeight w, {
      double? height,
      double? spacing,
      Color? color,
    }) => t?.copyWith(
      fontFamily: kFontFamily,
      fontSize: size,
      fontWeight: w,
      height: height,
      letterSpacing: spacing,
      color: color ?? c.ink,
    );

    // Large headlines are LIGHT with tight tracking — the airy, editorial
    // feel of the references. Hierarchy comes from size, not weight.
    return base.copyWith(
      displayLarge: s(
        base.displayLarge,
        56,
        FontWeight.w300,
        height: 1.0,
        spacing: -2.2,
      ),
      displayMedium: s(
        base.displayMedium,
        44,
        FontWeight.w300,
        height: 1.04,
        spacing: -1.6,
      ),
      displaySmall: s(
        base.displaySmall,
        36,
        FontWeight.w300,
        height: 1.08,
        spacing: -1.2,
      ),
      headlineLarge: s(
        base.headlineLarge,
        30,
        FontWeight.w400,
        height: 1.12,
        spacing: -0.9,
      ),
      headlineMedium: s(
        base.headlineMedium,
        26,
        FontWeight.w400,
        height: 1.15,
        spacing: -0.7,
      ),
      headlineSmall: s(
        base.headlineSmall,
        21,
        FontWeight.w500,
        height: 1.22,
        spacing: -0.4,
      ),
      titleLarge: s(
        base.titleLarge,
        18,
        FontWeight.w600,
        height: 1.3,
        spacing: -0.2,
      ),
      titleMedium: s(base.titleMedium, 16, FontWeight.w600, height: 1.35),
      titleSmall: s(base.titleSmall, 14, FontWeight.w600, height: 1.35),
      bodyLarge: s(base.bodyLarge, 16, FontWeight.w400, height: 1.5),
      bodyMedium: s(
        base.bodyMedium,
        14,
        FontWeight.w400,
        height: 1.5,
        color: c.inkMuted,
      ),
      bodySmall: s(
        base.bodySmall,
        12.5,
        FontWeight.w400,
        height: 1.45,
        color: c.inkMuted,
      ),
      labelLarge: s(base.labelLarge, 14, FontWeight.w500),
      labelMedium: s(base.labelMedium, 12, FontWeight.w500, color: c.inkMuted),
      labelSmall: s(
        base.labelSmall,
        11,
        FontWeight.w500,
        spacing: 0.3,
        color: c.inkMuted,
      ),
    );
  }
}
