import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../src/rust/api/app.dart' as rs_app;
import '../src/rust/api/caption.dart' as rs;
import 'settings.dart';

/// One caption: the recognized line (growing while it is spoken) and its
/// translation (streamed).
@immutable
class CaptionLine {
  const CaptionLine({
    required this.id,
    this.source = '',
    this.stableChars = 0,
    this.isFinal = false,
    this.translation = '',
    this.translationDone = false,
    this.translationIsPartial = false,
    this.sameLanguage = false,
    this.language,
    this.startMs = 0,
    this.endMs = 0,
    this.asrMs = 0,
    this.translationMs = 0,
  });

  final int id;
  final String source;

  /// Leading characters of a partial line that the previous partial had
  /// too (likely to stay).
  final int stableChars;
  final bool isFinal;
  final String translation;
  final bool translationDone;
  final bool translationIsPartial;
  final bool sameLanguage;
  final String? language;
  final int startMs;
  final int endMs;
  final int asrMs;
  final int translationMs;

  CaptionLine copyWith({
    String? source,
    int? stableChars,
    bool? isFinal,
    String? translation,
    bool? translationDone,
    bool? translationIsPartial,
    bool? sameLanguage,
    String? language,
    int? startMs,
    int? endMs,
    int? asrMs,
    int? translationMs,
  }) =>
      CaptionLine(
        id: id,
        source: source ?? this.source,
        stableChars: stableChars ?? this.stableChars,
        isFinal: isFinal ?? this.isFinal,
        translation: translation ?? this.translation,
        translationDone: translationDone ?? this.translationDone,
        translationIsPartial: translationIsPartial ?? this.translationIsPartial,
        sameLanguage: sameLanguage ?? this.sameLanguage,
        language: language ?? this.language,
        startMs: startMs ?? this.startMs,
        endMs: endMs ?? this.endMs,
        asrMs: asrMs ?? this.asrMs,
        translationMs: translationMs ?? this.translationMs,
      );
}

enum CaptionStatus { idle, loading, running, failed }

@immutable
class CaptionState {
  const CaptionState({
    this.status = CaptionStatus.idle,
    this.message = '',
    this.provider = '',
    this.device = '',
    this.level = 0,
    this.lines = const [],
    this.lastError = '',
    this.paused = false,
  });

  final CaptionStatus status;

  /// What is loading (`asr`, `translator`) or why it failed.
  final String message;
  final String provider;
  final String device;
  final double level;
  final List<CaptionLine> lines;
  final String lastError;
  final bool paused;

  bool get active => status == CaptionStatus.loading || status == CaptionStatus.running;

  CaptionState copyWith({
    CaptionStatus? status,
    String? message,
    String? provider,
    String? device,
    double? level,
    List<CaptionLine>? lines,
    String? lastError,
    bool? paused,
  }) =>
      CaptionState(
        status: status ?? this.status,
        message: message ?? this.message,
        provider: provider ?? this.provider,
        device: device ?? this.device,
        level: level ?? this.level,
        lines: lines ?? this.lines,
        lastError: lastError ?? this.lastError,
        paused: paused ?? this.paused,
      );
}

/// Lines kept for the transcript view.
const _maxLines = 300;

rs.TranslationSettings? translationSettingsOf(AppSettings s) {
  if (!s.translationEnabled) return null;
  return rs.TranslationSettings(
    backend: s.translator == TranslatorKind.local ? rs.TranslatorBackend.local : rs.TranslatorBackend.api,
    localModel: s.localTranslator,
    localGpu: s.localGpu,
    contextTokens: s.contextTokens,
    apiBaseUrl: s.apiBaseUrl,
    apiKey: s.apiKey,
    apiModel: s.apiModel,
    apiStyle: s.apiStyle == ApiStyle.chat ? rs.ApiPromptStyle.chat : rs.ApiPromptStyle.translationModel,
    targetLanguage: s.targetLanguage,
    background: s.background,
    glossary: s.glossary
        .where((e) => e.enabled && e.source.trim().isNotEmpty && e.target.trim().isNotEmpty)
        .map((e) => rs.GlossaryTerm(source: e.source, target: e.target))
        .toList(),
    contextLines: s.contextLines,
    temperature: s.temperature,
    translatePartials: s.translatePartials,
    skipSameLanguage: s.skipSameLanguage,
  );
}

List<rs.ReplacementRule> replacementRulesOf(AppSettings s) => s.replacements
    .where((e) => e.enabled && e.from.isNotEmpty)
    .map((e) => rs.ReplacementRule(from: e.from, to: e.to))
    .toList();

class CaptionController extends Notifier<CaptionState> {
  StreamSubscription<rs.CaptionEvent>? _subscription;

  @override
  CaptionState build() {
    // Word lists and translation options reach a running session at once;
    // models, devices and the backend need a restart.
    ref.listen(settingsProvider, (previous, next) {
      if (!state.active || previous == null) return;
      final changed = previous.glossary != next.glossary ||
          previous.replacements != next.replacements ||
          previous.targetLanguage != next.targetLanguage ||
          previous.background != next.background ||
          previous.contextLines != next.contextLines ||
          previous.translatePartials != next.translatePartials ||
          previous.skipSameLanguage != next.skipSameLanguage ||
          previous.asrLanguage != next.asrLanguage;
      if (changed) {
        rs.updateLive(
          hotwords: next.hotwords,
          asrLanguage: next.asrLanguage.isEmpty ? null : next.asrLanguage,
          rules: replacementRulesOf(next),
          translation: translationSettingsOf(next),
        );
      }
    });
    ref.onDispose(() => _subscription?.cancel());
    return const CaptionState();
  }

  Future<void> start() async {
    await stop();
    final s = ref.read(settingsProvider);
    final paths = ref.read(appPathsProvider);
    state = state.copyWith(status: CaptionStatus.loading, message: 'asr', lastError: '', paused: false);
    final settings = rs.LiveSettings(
      asrModel: s.asrModel,
      asrGpu: s.asrGpu,
      source: s.audioSource == 'microphone' ? rs_app.AudioSourceKind.microphone : rs_app.AudioSourceKind.system,
      deviceId: s.deviceId.isEmpty ? null : s.deviceId,
      vadModelPath: paths.vadModel,
      vadThreshold: s.vadThreshold,
      minSilenceMs: s.minSilenceMs,
      maxSegmentMs: s.maxSegmentMs,
      partialIntervalMs: s.partialIntervalMs,
      hotwords: s.hotwords,
      asrLanguage: s.asrLanguage.isEmpty ? null : s.asrLanguage,
      replacements: replacementRulesOf(s),
      translation: translationSettingsOf(s),
    );
    _subscription = rs.startLive(settings: settings).listen(_onEvent, onError: (Object error) {
      state = state.copyWith(status: CaptionStatus.failed, message: '$error');
    });
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    if (state.active) {
      await rs.stopLive();
    }
    state = state.copyWith(status: CaptionStatus.idle, level: 0);
  }

  Future<void> toggle() => state.active ? stop() : start();

  void clear() => state = state.copyWith(lines: const []);

  void _onEvent(rs.CaptionEvent e) {
    switch (e.kind) {
      case rs.CaptionEventKind.state:
        final status = switch (e.status) {
          rs.LiveStatus.loading => CaptionStatus.loading,
          rs.LiveStatus.running => CaptionStatus.running,
          rs.LiveStatus.stopped => CaptionStatus.idle,
          rs.LiveStatus.failed => CaptionStatus.failed,
        };
        state = state.copyWith(
          status: status,
          message: e.message,
          provider: e.asrProvider.isEmpty ? state.provider : e.asrProvider,
          device: e.device.isEmpty ? state.device : e.device,
          level: status == CaptionStatus.running ? state.level : 0,
        );
      case rs.CaptionEventKind.level:
        state = state.copyWith(level: e.level);
      case rs.CaptionEventKind.partial:
        _upsert(e.id.toInt(), (line) => line.copyWith(
              source: e.text,
              stableChars: e.stableChars,
              startMs: e.startMs.toInt(),
              endMs: e.endMs.toInt(),
              asrMs: e.asrMs.toInt(),
            ));
      case rs.CaptionEventKind.final_:
        if (e.text.isEmpty) {
          state = state.copyWith(lines: state.lines.where((l) => l.id != e.id.toInt()).toList());
        } else {
          _upsert(e.id.toInt(), (line) => line.copyWith(
                source: e.text,
                stableChars: e.text.length,
                isFinal: true,
                language: e.language,
                startMs: e.startMs.toInt(),
                endMs: e.endMs.toInt(),
                asrMs: e.asrMs.toInt(),
              ));
        }
      case rs.CaptionEventKind.translation:
        _upsert(e.id.toInt(), (line) {
          // A late partial translation never replaces a final one.
          if (e.partial && line.translationDone && !line.translationIsPartial) return line;
          return line.copyWith(
            translation: e.text,
            translationDone: e.done,
            translationIsPartial: e.partial,
            sameLanguage: e.sameLanguage,
            translationMs: e.done ? e.totalMs.toInt() : line.translationMs,
          );
        });
      case rs.CaptionEventKind.error:
        state = state.copyWith(lastError: e.message);
    }
  }

  void _upsert(int id, CaptionLine Function(CaptionLine) change) {
    final lines = [...state.lines];
    final index = lines.lastIndexWhere((l) => l.id == id);
    if (index >= 0) {
      lines[index] = change(lines[index]);
    } else {
      lines.add(change(CaptionLine(id: id)));
      lines.sort((a, b) => a.id.compareTo(b.id));
      if (lines.length > _maxLines) lines.removeRange(0, lines.length - _maxLines);
    }
    state = state.copyWith(lines: lines);
  }
}

final captionProvider = NotifierProvider<CaptionController, CaptionState>(CaptionController.new);
