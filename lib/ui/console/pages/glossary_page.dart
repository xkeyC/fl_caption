import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/i18n.dart';
import '../../../app/settings.dart';
import '../../theme.dart';
import '../../widgets.dart';

class GlossaryPage extends ConsumerWidget {
  const GlossaryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final update = ref.read(settingsProvider.notifier).update;
    final glossary = s.glossary;
    final replacements = s.replacements;

    void setGlossary(List<GlossaryEntry> list) => update((s) => s.copyWith(glossary: list));
    void setReplacements(List<ReplacementEntry> list) => update((s) => s.copyWith(replacements: list));

    return PageScaffold(
      title: tr('热词与术语', 'Hotwords & glossary'),
      subtitle: tr(
        '术语会提示给翻译模型；勾选“热词”的条目还会交给 Fun-ASR-Nano 提高识别率。修改即时生效。',
        'Terms guide the translator; entries marked as hotwords also bias Fun-ASR-Nano. Changes apply at once.',
      ),
      children: [
        Section(
          title: tr('术语表', 'Glossary'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HyperlinkButton(
                child: iconLabel(FluentIcons.upload, tr('导入 CSV', 'Import CSV')),
                onPressed: () async {
                  final rows = await _importCsv();
                  if (rows == null) return;
                  final known = {for (final e in glossary) e.source.toLowerCase()};
                  setGlossary([
                    ...glossary,
                    for (final r in rows)
                      if (r.isNotEmpty && r[0].trim().isNotEmpty && !known.contains(r[0].trim().toLowerCase()))
                        GlossaryEntry(
                          source: r[0].trim(),
                          target: r.length > 1 ? r[1].trim() : '',
                          hotword: r.length > 2 ? r[2].trim() != '0' : true,
                        ),
                  ]);
                },
              ),
              HyperlinkButton(
                onPressed: glossary.isEmpty
                    ? null
                    : () => _exportCsv('glossary.csv', [
                        for (final e in glossary) [e.source, e.target, e.hotword ? '1' : '0'],
                      ]),
                child: iconLabel(FluentIcons.download, tr('导出', 'Export')),
              ),
            ],
          ),
          children: [
            _Header(columns: [tr('原文 / 热词', 'Term / hotword'), tr('译文', 'Translation'), tr('热词', 'Hotword')]),
            for (var i = 0; i < glossary.length; i++)
              _Row(
                key: ValueKey('g$i'),
                enabled: glossary[i].enabled,
                onEnabled: (v) => setGlossary([...glossary]..[i] = glossary[i].copyWith(enabled: v)),
                onDelete: () => setGlossary([...glossary]..removeAt(i)),
                cells: [
                  CommitTextField(
                    value: glossary[i].source,
                    hint: 'Hornet',
                    onCommit: (v) => setGlossary([...glossary]..[i] = glossary[i].copyWith(source: v)),
                  ),
                  CommitTextField(
                    value: glossary[i].target,
                    hint: tr('大黄蜂（可留空：只作热词）', 'Hornet (optional: hotword only)'),
                    onCommit: (v) => setGlossary([...glossary]..[i] = glossary[i].copyWith(target: v)),
                  ),
                  Checkbox(
                    checked: glossary[i].hotword,
                    onChanged: (v) => setGlossary([...glossary]..[i] = glossary[i].copyWith(hotword: v ?? false)),
                  ),
                ],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: HyperlinkButton(
                child: iconLabel(FluentIcons.add, tr('添加术语', 'Add a term')),
                onPressed: () => setGlossary([...glossary, const GlossaryEntry(source: '')]),
              ),
            ),
            Text(
              tr(
                '提示：热词只对 Fun-ASR-Nano 生效，过多会降低速度（建议 100 个以内）。',
                'Hotwords only affect Fun-ASR-Nano; many slow it down (keep it under ~100).',
              ),
              style: TextStyle(fontSize: 12, color: muted(context)),
            ),
          ],
        ),
        Section(
          title: tr('识别纠错', 'Recognition fixes'),
          trailing: HyperlinkButton(
            child: iconLabel(FluentIcons.upload, tr('导入 CSV', 'Import CSV')),
            onPressed: () async {
              final rows = await _importCsv();
              if (rows == null) return;
              setReplacements([
                ...replacements,
                for (final r in rows)
                  if (r.isNotEmpty && r[0].isNotEmpty) ReplacementEntry(from: r[0], to: r.length > 1 ? r[1] : ''),
              ]);
            },
          ),
          children: [
            Text(
              tr(
                '把识别结果中固定出错的词替换掉（英文不区分大小写），在翻译前生效。',
                'Replaces words the recognizer always gets wrong (English ignores case), before translation.',
              ),
              style: TextStyle(fontSize: 12.5, color: muted(context)),
            ),
            const SizedBox(height: 8),
            _Header(columns: [tr('识别成', 'Recognized as'), tr('替换为', 'Replace with')]),
            for (var i = 0; i < replacements.length; i++)
              _Row(
                key: ValueKey('r$i'),
                enabled: replacements[i].enabled,
                onEnabled: (v) => setReplacements([...replacements]..[i] = replacements[i].copyWith(enabled: v)),
                onDelete: () => setReplacements([...replacements]..removeAt(i)),
                cells: [
                  CommitTextField(
                    value: replacements[i].from,
                    hint: tr('笑乐', 'Lorvile'),
                    onCommit: (v) => setReplacements([...replacements]..[i] = replacements[i].copyWith(from: v)),
                  ),
                  CommitTextField(
                    value: replacements[i].to,
                    hint: tr('小乐', 'Lorville'),
                    onCommit: (v) => setReplacements([...replacements]..[i] = replacements[i].copyWith(to: v)),
                  ),
                ],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: HyperlinkButton(
                child: iconLabel(FluentIcons.add, tr('添加规则', 'Add a rule')),
                onPressed: () => setReplacements([...replacements, const ReplacementEntry(from: '')]),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static Future<List<List<String>>?> _importCsv() async {
    final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['csv', 'txt', 'tsv']);
    final path = picked?.path;
    if (path == null) return null;
    final text = await File(path).readAsString();
    return [
      for (final line in const LineSplitter().convert(text))
        if (line.trim().isNotEmpty) _splitCsv(line, path.toLowerCase().endsWith('.tsv') ? '\t' : ','),
    ];
  }

  /// One CSV line (double quotes may enclose a field with commas).
  static List<String> _splitCsv(String line, String separator) {
    final out = <String>[];
    final field = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (c == separator && !quoted) {
        out.add(field.toString());
        field.clear();
      } else {
        field.write(c);
      }
    }
    out.add(field.toString());
    return out;
  }

  static Future<void> _exportCsv(String name, List<List<String>> rows) async {
    String quote(String v) => v.contains(RegExp('[",\n]')) ? '"${v.replaceAll('"', '""')}"' : v;
    final text = rows.map((r) => r.map(quote).join(',')).join('\n');
    await FilePicker.saveFile(
      fileName: name,
      bytes: utf8.encode(text),
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.columns});

  final List<String> columns;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 12, color: muted(context));
    return Padding(
      padding: const EdgeInsets.only(left: 48, right: 48, bottom: 4),
      child: Row(
        children: [
          for (var i = 0; i < columns.length; i++)
            if (i < 2)
              Expanded(child: Text(columns[i], style: style))
            else
              SizedBox(width: 56, child: Text(columns[i], style: style)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({super.key, required this.enabled, required this.onEnabled, required this.onDelete, required this.cells});

  final bool enabled;
  final ValueChanged<bool> onEnabled;
  final VoidCallback onDelete;
  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Checkbox(checked: enabled, onChanged: (v) => onEnabled(v ?? true)),
          ),
          for (var i = 0; i < cells.length; i++)
            if (i < 2)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Opacity(opacity: enabled ? 1 : 0.5, child: cells[i]),
                ),
              )
            else
              SizedBox(width: 56, child: cells[i]),
          IconButton(icon: const Icon(FluentIcons.cancel, size: 12), onPressed: onDelete),
        ],
      ),
    );
  }
}
