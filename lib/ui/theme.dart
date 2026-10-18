import 'package:fluent_ui/fluent_ui.dart';

const fontFamily = 'SourceHanSansCN';

/// Aurora teal: buttons, selection, the transcript's translations.
const accent = Color(0xFF2EC4B6);

/// Panels over the aurora: translucent, so the aurora shows through.
const panelColor = Color(0x52102028);
const cardColor = Color(0x661A2E38);
const strokeColor = Color(0x1AFFFFFF);

FluentThemeData buildTheme() {
  return FluentThemeData(
    brightness: Brightness.dark,
    accentColor: AccentColor.swatch(const {
      'darkest': Color(0xFF13756C),
      'darker': Color(0xFF1A9187),
      'dark': Color(0xFF22AA9E),
      'normal': Color(0xFF2EC4B6),
      'light': Color(0xFF2EC4B6),
      'lighter': Color(0xFF2EC4B6),
      'lightest': Color(0xFF7FE0D6),
    }),
    visualDensity: const VisualDensity(vertical: 1),
    fontFamily: fontFamily,
    scaffoldBackgroundColor: Colors.transparent,
    micaBackgroundColor: const Color(0xFF0A1A24),
    cardColor: cardColor,
    navigationPaneTheme: const NavigationPaneThemeData(backgroundColor: Colors.transparent),
    buttonTheme: ButtonThemeData(
      // fluent_ui 4.16 fills disabled IconButtons with the button colour;
      // keep them transparent (as ToolBox does).
      iconButtonStyle: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          const res = ResourceDictionary.dark();
          if (states.isDisabled) return res.subtleFillColorTransparent;
          if (states.isPressed) return res.subtleFillColorTertiary;
          if (states.isHovered) return res.subtleFillColorSecondary;
          return res.subtleFillColorTransparent;
        }),
      ),
    ),
  );
}

/// Muted text (secondary labels, hints).
Color muted(BuildContext context) => FluentTheme.of(context).resources.textFillColorSecondary;
