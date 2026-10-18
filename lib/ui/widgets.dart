import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// A page: title, optional actions, scrolling content.
class PageScaffold extends StatelessWidget {
  const PageScaffold({super.key, required this.title, this.subtitle, this.actions = const [], required this.children});

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final typography = FluentTheme.of(context).typography;
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: typography.title),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: TextStyle(color: muted(context))),
                  ],
                ],
              ),
            ),
            ...actions,
          ],
        ),
        const SizedBox(height: 20),
        for (final child in children) ...[child, const SizedBox(height: 14)],
      ],
    );
  }
}

/// A card of settings with a heading.
class Section extends StatelessWidget {
  const Section({super.key, required this.title, this.trailing, required this.children});

  final String title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      backgroundColor: cardColor,
      borderColor: strokeColor,
      borderRadius: BorderRadius.circular(8),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: FluentTheme.of(context).typography.subtitle?.copyWith(fontSize: 17))),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

/// A label (and description) on the left, a control on the right.
class SettingRow extends StatelessWidget {
  const SettingRow({super.key, required this.label, this.description, required this.child, this.wide = false});

  final String label;
  final String? description;
  final Widget child;

  /// The control takes the remaining width (text fields).
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        if (description != null) ...[
          const SizedBox(height: 2),
          Text(description!, style: TextStyle(fontSize: 12, color: muted(context))),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          if (wide) SizedBox(width: 220, child: text) else Expanded(child: text),
          const SizedBox(width: 16),
          if (wide) Expanded(child: child) else child,
        ],
      ),
    );
  }
}

class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.label, this.description, required this.value, required this.onChanged});

  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SettingRow(
    label: label,
    description: description,
    child: ToggleSwitch(checked: value, onChanged: onChanged),
  );
}

/// A drop-down of `(value, label)` items.
class Choice<T> extends StatelessWidget {
  const Choice({super.key, required this.value, required this.items, required this.onChanged, this.width = 280});

  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    final known = items.any((item) => item.$1 == value);
    return SizedBox(
      width: width,
      child: ComboBox<T>(
        value: known ? value : null,
        isExpanded: true,
        items: [
          for (final (v, label) in items)
            ComboBoxItem(
              value: v,
              child: Text(label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

/// Two or more options side by side (a segmented choice).
class Segments<T> extends StatelessWidget {
  const Segments({super.key, required this.value, required this.items, required this.onChanged});

  final T value;
  final List<(T, IconData, String)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (v, icon, label) in items)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: ToggleButton(
              checked: v == value,
              onChanged: (_) => onChanged(v),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [Icon(icon, size: 14), const SizedBox(width: 8), Text(label)],
              ),
            ),
          ),
      ],
    );
  }
}

/// A text box that reports its value when editing ends (focus lost or
/// Enter), not on every keystroke.
class CommitTextField extends StatefulWidget {
  const CommitTextField({
    super.key,
    required this.value,
    required this.onCommit,
    this.hint,
    this.obscure = false,
    this.maxLines = 1,
    this.inputFormatters,
  });

  final String value;
  final ValueChanged<String> onCommit;
  final String? hint;
  final bool obscure;
  final int maxLines;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<CommitTextField> createState() => _CommitTextFieldState();
}

class _CommitTextFieldState extends State<CommitTextField> {
  late final TextEditingController _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(CommitTextField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value != _controller.text) _controller.text = widget.value;
  }

  void _commit() {
    if (_controller.text != widget.value) widget.onCommit(_controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextBox(
      controller: _controller,
      focusNode: _focus,
      obscureText: widget.obscure,
      maxLines: widget.obscure ? 1 : widget.maxLines,
      minLines: 1,
      inputFormatters: widget.inputFormatters,
      placeholder: widget.hint,
      onSubmitted: (_) => _commit(),
    );
  }
}

/// A slider with its value shown.
class SliderRow extends StatelessWidget {
  const SliderRow({
    super.key,
    required this.label,
    this.description,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final String? description;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      label: label,
      description: description,
      child: SizedBox(
        width: 320,
        child: Row(
          children: [
            Expanded(
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                label: format(value),
                onChanged: onChanged,
              ),
            ),
            SizedBox(width: 64, child: Text(format(value), textAlign: TextAlign.end)),
          ],
        ),
      ),
    );
  }
}

/// A small coloured label.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? accent;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
      child: Text(
        text,
        style: TextStyle(fontSize: 11.5, color: c, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// An icon and text inside a button.
Widget iconLabel(IconData icon, String text, {double size = 14}) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Icon(icon, size: size),
    const SizedBox(width: 8),
    Text(text),
  ],
);

String formatBytes(num bytes) {
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(2)} GB';
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(0)} MB';
  if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(0)} KB';
  return '$bytes B';
}

String formatMb(num mb) => mb >= 1024 ? '${(mb / 1024).toStringAsFixed(1)} GB' : '${mb.round()} MB';

Future<void> showMessage(BuildContext context, String text, {InfoBarSeverity severity = InfoBarSeverity.info}) {
  return displayInfoBar(
    context,
    builder: (context, close) => InfoBar(
      title: Text(text),
      severity: severity,
      action: IconButton(icon: const Icon(FluentIcons.clear), onPressed: close),
    ),
  );
}
