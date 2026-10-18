import 'package:flutter/material.dart';

const fontFamily = 'SourceHanSansCN';

/// Accent of the app (buttons, selection, the level meter).
const accent = Color(0xFF5B8CFF);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
    surface: const Color(0xFF14161A),
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: fontFamily,
    scaffoldBackgroundColor: const Color(0xFF14161A),
    visualDensity: VisualDensity.standard,
  );
  return base.copyWith(
    cardTheme: CardThemeData(
      color: const Color(0xFF1C1F25),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF2A2E36)),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFF2A2E36), thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF181B20),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF2E333C))),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF2E333C))),
    ),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
    textTheme: base.textTheme.apply(fontFamily: fontFamily),
  );
}

/// Muted text (secondary labels, hints).
Color muted(BuildContext context) => Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
