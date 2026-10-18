import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../src/rust/api/caption.dart' as rs;
import 'captions.dart';
import 'settings.dart';

enum JobStatus { queued, running, done, failed, cancelled }

@immutable
class Cue {
  const Cue({required this.startMs, required this.endMs, required this.text, this.translation});

  final int startMs;
  final int endMs;
  final String text;
  final String? translation;
}

@immutable
class FileJob {
  const FileJob({
    required this.id,
    required this.path,
    this.status = JobStatus.queued,
    this.stage = rs.FileJobStage.recognizing,
    this.done = 0,
    this.total = 0,
    this.cues = const [],
    this.files = const [],
    this.message = '',
    this.elapsedMs = 0,
    this.audioMs = 0,
  });

  final String id;
  final String path;
  final JobStatus status;
  final rs.FileJobStage stage;
  final int done;
  final int total;
  final List<Cue> cues;
  final List<String> files;
  final String message;
  final int elapsedMs;
  final int audioMs;

  String get name => path.split(RegExp(r'[\\/]')).last;

  double? get fraction => total > 0 ? (done / total).clamp(0.0, 1.0) : null;

  FileJob copyWith({
    JobStatus? status,
    rs.FileJobStage? stage,
    int? done,
    int? total,
    List<Cue>? cues,
    List<String>? files,
    String? message,
    int? elapsedMs,
    int? audioMs,
  }) => FileJob(
    id: id,
    path: path,
    status: status ?? this.status,
    stage: stage ?? this.stage,
    done: done ?? this.done,
    total: total ?? this.total,
    cues: cues ?? this.cues,
    files: files ?? this.files,
    message: message ?? this.message,
    elapsedMs: elapsedMs ?? this.elapsedMs,
    audioMs: audioMs ?? this.audioMs,
  );
}

/// Files transcribed one after another.
class FileJobsController extends Notifier<List<FileJob>> {
  StreamSubscription<rs.FileJobEvent>? _running;
  var _counter = 0;

  @override
  List<FileJob> build() {
    ref.onDispose(() => _running?.cancel());
    return const [];
  }

  void add(List<String> paths) {
    state = [
      ...state,
      for (final path in paths) FileJob(id: 'job${DateTime.now().microsecondsSinceEpoch}-${_counter++}', path: path),
    ];
    _next();
  }

  void remove(String id) {
    final job = state.where((j) => j.id == id).firstOrNull;
    if (job?.status == JobStatus.running) return;
    state = state.where((j) => j.id != id).toList();
  }

  void clearFinished() =>
      state = state.where((j) => j.status == JobStatus.queued || j.status == JobStatus.running).toList();

  Future<void> cancel(String id) async {
    final job = state.where((j) => j.id == id).firstOrNull;
    if (job == null) return;
    if (job.status == JobStatus.running) {
      await rs.cancelFileJob(jobId: id);
    } else if (job.status == JobStatus.queued) {
      _set(id, (j) => j.copyWith(status: JobStatus.cancelled));
    }
  }

  void _set(String id, FileJob Function(FileJob) change) => state = [for (final j in state) j.id == id ? change(j) : j];

  void _next() {
    if (state.any((j) => j.status == JobStatus.running)) return;
    final job = state.where((j) => j.status == JobStatus.queued).firstOrNull;
    if (job == null) return;
    final s = ref.read(settingsProvider);
    final paths = ref.read(appPathsProvider);
    final translate = s.translationEnabled && s.fileLines != SubtitleLinesMode.source;
    final settings = rs.FileJobSettings(
      inputPath: job.path,
      outputDir: s.fileOutputDir.isEmpty ? null : s.fileOutputDir,
      asrModel: s.asrModel,
      asrGpu: s.asrGpu,
      vadModelPath: paths.vadModel,
      hotwords: s.hotwords,
      asrLanguage: s.asrLanguage.isEmpty ? null : s.asrLanguage,
      replacements: replacementRulesOf(s),
      autoGain: s.autoGain,
      formats: s.fileFormats,
      lines: switch (translate ? s.fileLines : SubtitleLinesMode.source) {
        SubtitleLinesMode.source => rs.SubtitleLines.source,
        SubtitleLinesMode.translation => rs.SubtitleLines.translation,
        SubtitleLinesMode.both => rs.SubtitleLines.both,
        SubtitleLinesMode.bothTranslationFirst => rs.SubtitleLines.bothTranslationFirst,
      },
      maxCueMs: s.maxCueMs,
      maxCueWidth: s.maxCueWidth,
      stripEndPunctuation: s.stripEndPunctuation,
      translation: translate ? translationSettingsOf(s) : null,
      ffmpegPath: s.ffmpegPath.isEmpty ? null : s.ffmpegPath,
    );
    _set(job.id, (j) => j.copyWith(status: JobStatus.running));
    _running = rs
        .transcribeFile(jobId: job.id, settings: settings)
        .listen(
          (e) => _onEvent(job.id, e),
          onDone: () {
            _running = null;
            _next();
          },
        );
  }

  void _onEvent(String id, rs.FileJobEvent e) {
    switch (e.kind) {
      case rs.FileJobEventKind.progress:
        _set(id, (j) => j.copyWith(stage: e.stage, done: e.done.toInt(), total: e.total.toInt()));
      case rs.FileJobEventKind.cue:
        _set(id, (j) {
          final cue = Cue(startMs: e.startMs.toInt(), endMs: e.endMs.toInt(), text: e.text, translation: e.translation);
          final cues = [...j.cues];
          if (e.index < cues.length) {
            cues[e.index] = cue;
          } else {
            cues.add(cue);
          }
          return j.copyWith(cues: cues);
        });
      case rs.FileJobEventKind.done:
        _set(
          id,
          (j) => j.copyWith(
            status: JobStatus.done,
            files: e.files,
            elapsedMs: e.elapsedMs.toInt(),
            audioMs: e.audioMs.toInt(),
          ),
        );
      case rs.FileJobEventKind.failed:
        _set(
          id,
          (j) =>
              j.copyWith(status: e.message == 'cancelled' ? JobStatus.cancelled : JobStatus.failed, message: e.message),
        );
    }
  }
}

final fileJobsProvider = NotifierProvider<FileJobsController, List<FileJob>>(FileJobsController.new);
