import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/file_jobs.dart';
import '../../../app/i18n.dart';
import '../../../app/settings.dart';
import '../../../src/rust/api/caption.dart' as rs;
import '../../theme.dart';
import '../../widgets.dart';

const _mediaExtensions = [
  'wav', 'mp3', 'flac', 'm4a', 'aac', 'ogg', 'opus', 'wma', 'm4s', //
  'mp4', 'mkv', 'mov', 'webm', 'avi', 'flv', 'ts',
];

class FilesPage extends HookConsumerWidget {
  const FilesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final jobs = ref.watch(fileJobsProvider);
    final update = ref.read(settingsProvider.notifier).update;
    final dragging = useState(false);
    final selected = useState<String?>(null);
    final shown =
        jobs.where((j) => j.id == selected.value).firstOrNull ??
        jobs.where((j) => j.status == JobStatus.running).firstOrNull ??
        jobs.lastOrNull;

    Future<void> pick() async {
      final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: _mediaExtensions);
      final paths = files.map((f) => f.path).whereType<String>().toList();
      if (paths.isNotEmpty) ref.read(fileJobsProvider.notifier).add(paths);
    }

    return PageScaffold(
      title: tr('文件转字幕', 'Files to subtitles'),
      subtitle: tr(
        '把音频或视频文件转成字幕或歌词文件，可附带译文。使用“实时字幕”页选择的语音模型与“翻译”页的设置。',
        'Turns audio or video files into subtitle or lyrics files, with translations if you like. Uses the speech model of Live captions and the Translation settings.',
      ),
      children: [
        DropTarget(
          onDragEntered: (_) => dragging.value = true,
          onDragExited: (_) => dragging.value = false,
          onDragDone: (detail) {
            dragging.value = false;
            final paths = detail.files.map((f) => f.path).where((p) => File(p).existsSync()).toList();
            if (paths.isNotEmpty) ref.read(fileJobsProvider.notifier).add(paths);
          },
          child: GestureDetector(
            onTap: pick,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: dragging.value ? accent.withValues(alpha: 0.14) : Colors.black.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: dragging.value ? accent : strokeColor, width: 1.5),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(FluentIcons.cloud_upload, size: 30, color: dragging.value ? accent : muted(context)),
                  const SizedBox(height: 8),
                  Text(tr('拖入文件，或点击选择', 'Drop files here, or click to choose')),
                  const SizedBox(height: 2),
                  Text('MP4 · MKV · MP3 · WAV · FLAC · M4A …', style: TextStyle(fontSize: 12, color: muted(context))),
                ],
              ),
            ),
          ),
        ),
        Section(
          title: tr('输出', 'Output'),
          children: [
            SettingRow(
              label: tr('格式', 'Formats'),
              description: tr('LRC 为歌词格式', 'LRC is the lyrics format'),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final format in const ['srt', 'vtt', 'lrc', 'txt'])
                    ToggleButton(
                      checked: s.fileFormats.contains(format),
                      onChanged: (on) {
                        final next = on ? [...s.fileFormats, format] : s.fileFormats.where((f) => f != format).toList();
                        if (next.isNotEmpty) update((s) => s.copyWith(fileFormats: next));
                      },
                      child: Text(format.toUpperCase()),
                    ),
                ],
              ),
            ),
            SettingRow(
              label: tr('字幕内容', 'Lines'),
              description: s.translationEnabled
                  ? null
                  : tr('翻译已在“翻译”页关闭，仅输出原文', 'Translation is off on the Translation page: source only'),
              child: Choice<SubtitleLinesMode>(
                value: s.fileLines,
                items: [
                  (SubtitleLinesMode.source, tr('仅原文', 'Source only')),
                  (SubtitleLinesMode.translation, tr('仅译文', 'Translation only')),
                  (SubtitleLinesMode.both, tr('双语（原文在上）', 'Bilingual (source first)')),
                  (SubtitleLinesMode.bothTranslationFirst, tr('双语（译文在上）', 'Bilingual (translation first)')),
                ],
                onChanged: (v) => update((s) => s.copyWith(fileLines: v)),
              ),
            ),
            SettingRow(
              label: tr('保存到', 'Save to'),
              description: s.fileOutputDir.isEmpty ? tr('与源文件相同的目录', 'Beside the source file') : s.fileOutputDir,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Button(
                    onPressed: () async {
                      final dir = await FilePicker.getDirectoryPath();
                      if (dir != null) update((s) => s.copyWith(fileOutputDir: dir));
                    },
                    child: Text(tr('选择目录', 'Choose')),
                  ),
                  if (s.fileOutputDir.isNotEmpty)
                    Tooltip(
                      message: tr('恢复为源文件目录', 'Back to beside the source'),
                      child: IconButton(
                        icon: const Icon(FluentIcons.undo),
                        onPressed: () => update((s) => s.copyWith(fileOutputDir: '')),
                      ),
                    ),
                ],
              ),
            ),
            SliderRow(
              label: tr('每条字幕最长', 'Longest cue'),
              value: s.maxCueMs / 1000,
              min: 2,
              max: 12,
              divisions: 10,
              format: (v) => '${v.round()} s',
              onChanged: (v) => update((s) => s.copyWith(maxCueMs: (v * 1000).round())),
            ),
            SliderRow(
              label: tr('每行最多字符', 'Widest line'),
              description: tr('中日韩文字按 2 计', 'CJK characters count two'),
              value: s.maxCueWidth.toDouble(),
              min: 20,
              max: 84,
              divisions: 16,
              format: (v) => '${v.round()}',
              onChanged: (v) => update((s) => s.copyWith(maxCueWidth: v.round())),
            ),
            SwitchRow(
              label: tr('去掉句末逗号句号', 'Drop trailing commas and full stops'),
              value: s.stripEndPunctuation,
              onChanged: (v) => update((s) => s.copyWith(stripEndPunctuation: v)),
            ),
          ],
        ),
        if (jobs.isNotEmpty)
          Section(
            title: tr('任务', 'Jobs'),
            trailing: HyperlinkButton(
              onPressed: () => ref.read(fileJobsProvider.notifier).clearFinished(),
              child: Text(tr('清除已完成', 'Clear finished')),
            ),
            children: [
              for (final job in jobs)
                _JobTile(job: job, selected: job.id == shown?.id, onTap: () => selected.value = job.id),
            ],
          ),
        if (shown != null && shown.cues.isNotEmpty) _CuePreview(job: shown),
      ],
    );
  }
}

String _stageLabel(rs.FileJobStage stage) => switch (stage) {
  rs.FileJobStage.decoding => tr('转换音频', 'Converting audio'),
  rs.FileJobStage.recognizing => tr('识别中', 'Recognizing'),
  rs.FileJobStage.translating => tr('翻译中', 'Translating'),
  rs.FileJobStage.writing => tr('写入文件', 'Writing'),
};

class _JobTile extends ConsumerWidget {
  const _JobTile({required this.job, required this.selected, required this.onTap});

  final FileJob job;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(fileJobsProvider.notifier);
    final (icon, color) = switch (job.status) {
      JobStatus.queued => (FluentIcons.clock, muted(context)),
      JobStatus.running => (FluentIcons.sync, accent),
      JobStatus.done => (FluentIcons.completed_solid, Colors.green.lighter),
      JobStatus.failed => (FluentIcons.error_badge, Colors.red.lighter),
      JobStatus.cancelled => (FluentIcons.cancel, muted(context)),
    };
    final detail = switch (job.status) {
      JobStatus.queued => tr('排队中', 'Queued'),
      JobStatus.running =>
        job.stage == rs.FileJobStage.translating
            ? '${_stageLabel(job.stage)} ${job.done}/${job.total}'
            : '${_stageLabel(job.stage)} ${job.fraction == null ? '' : '${(job.fraction! * 100).round()}%'}',
      JobStatus.done => tr(
        '完成：${job.cues.length} 条，音频 ${(job.audioMs / 60000).toStringAsFixed(1)} 分钟，用时 ${(job.elapsedMs / 1000).toStringAsFixed(1)} 秒',
        'Done: ${job.cues.length} cues, ${(job.audioMs / 60000).toStringAsFixed(1)} min of audio in ${(job.elapsedMs / 1000).toStringAsFixed(1)} s',
      ),
      JobStatus.failed => job.message,
      JobStatus.cancelled => tr('已取消', 'Cancelled'),
    };
    return HoverButton(
      onPressed: onTap,
      builder: (context, states) => Container(
        decoration: BoxDecoration(
          color: selected || states.isHovered ? Colors.white.withValues(alpha: 0.05) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(job.name, overflow: TextOverflow.ellipsis),
                        Text(
                          detail,
                          style: TextStyle(
                            fontSize: 12,
                            color: job.status == JobStatus.failed ? Colors.red.lighter : muted(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (job.status == JobStatus.done)
                    for (final file in job.files)
                      HyperlinkButton(
                        onPressed: () => launchUrl(Uri.file(File(file).parent.path)),
                        child: Text(file.split('.').last.toUpperCase()),
                      ),
                  if (job.status == JobStatus.running || job.status == JobStatus.queued)
                    Tooltip(
                      message: tr('取消', 'Cancel'),
                      child: IconButton(
                        icon: const Icon(FluentIcons.cancel, size: 12),
                        onPressed: () => controller.cancel(job.id),
                      ),
                    )
                  else
                    Tooltip(
                      message: tr('移除', 'Remove'),
                      child: IconButton(
                        icon: const Icon(FluentIcons.delete, size: 14),
                        onPressed: () => controller.remove(job.id),
                      ),
                    ),
                ],
              ),
              if (job.status == JobStatus.running)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 30),
                  child: ProgressBar(value: job.fraction == null ? null : job.fraction! * 100),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CuePreview extends StatelessWidget {
  const _CuePreview({required this.job});

  final FileJob job;

  @override
  Widget build(BuildContext context) {
    String clock(int ms) =>
        '${(ms ~/ 60000).toString().padLeft(2, '0')}:${(ms ~/ 1000 % 60).toString().padLeft(2, '0')}.${(ms % 1000 ~/ 100)}';
    return Section(
      title: '${tr('预览', 'Preview')} · ${job.name}',
      children: [
        SizedBox(
          height: 320,
          child: ListView.builder(
            itemCount: job.cues.length,
            itemBuilder: (context, i) {
              final cue = job.cues[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        '${clock(cue.startMs)} → ${clock(cue.endMs)}',
                        style: TextStyle(fontSize: 12, color: muted(context), height: 1.6),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(cue.text),
                          if (cue.translation != null && cue.translation!.isNotEmpty)
                            Text(cue.translation!, style: const TextStyle(color: accent)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
