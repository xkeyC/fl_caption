import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../src/rust/api/app.dart' as rs_app;
import '../src/rust/api/caption.dart' as rs;
import 'models.dart';
import 'settings.dart';
import 'windows.dart';

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
  }) => CaptionLine(
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
  }) => CaptionState(
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

/// Lines kept for the caption bar.
const _maxLines = 300;

/// Final lines kept in memory for exporting the context.
const maxHistory = 10000;

/// A final line, kept for the context export.
class HistoryEntry {
  HistoryEntry({required this.id, required this.time, required this.source});

  final int id;

  /// When the line was finished (wall clock).
  final DateTime time;
  final String source;
  String translation = '';
}

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
  Timer? _restart;

  /// The settings the running session started with.
  AppSettings? _session;

  /// Added to a session's line ids: every session numbers its lines from 1,
  /// and the lines of earlier sessions are still shown.
  int _idBase = 0;

  int _lineId(rs.CaptionEvent e) => _idBase + e.id.toInt();

  /// The phone the running session listens to (the mobile app), if any.
  String? _remote;
  String? get remote => _remote;

  /// The connected phone: while it is set, captions take its audio, never
  /// the computer's.
  String? _phone;

  /// A phone connected ([name]) or left (`null`). It stops captions from
  /// the computer's audio; when it leaves, its captions stop and the
  /// computer's come back if they were on.
  Future<void> setPhone(String? name) async {
    if (name == _phone) return;
    _phone = name;
    if (name != null) {
      // Also the session of a phone this one replaces.
      if (state.active) await stop(remember: false);
    } else {
      if (_remote != null) await stop();
      state = state.copyWith(device: '');
      if (ref.read(settingsProvider).captionsOn) await start();
    }
    _pushStatus();
  }

  /// Audio input and segmentation: a running session restarts at once
  /// (its models stay loaded).
  static bool _needsRestart(AppSettings a, AppSettings b) =>
      a.audioSource != b.audioSource ||
      a.deviceId != b.deviceId ||
      a.vadEnabled != b.vadEnabled ||
      a.vadThreshold != b.vadThreshold ||
      a.minSilenceMs != b.minSilenceMs ||
      a.maxSegmentMs != b.maxSegmentMs ||
      a.partialIntervalMs != b.partialIntervalMs ||
      a.autoGain != b.autoGain;

  /// The models a session runs (and the translator's backend): changing
  /// them is applied when the user asks (it unloads and loads models).
  static String _models(AppSettings s) => [
    s.asrModel,
    s.asrGpu,
    s.translationEnabled,
    if (s.translationEnabled) ...[
      s.translator.name,
      if (s.translator == TranslatorKind.local) ...[s.localTranslator, s.localGpu, s.contextTokens],
      if (s.translator == TranslatorKind.api) ...[s.apiBaseUrl, s.apiKey, s.apiModel, s.apiStyle.name],
    ],
  ].join('|');

  /// The running session uses other models than the ones now selected.
  bool get modelsPending {
    final session = _session;
    return state.active && session != null && _models(session) != _models(ref.read(settingsProvider));
  }

  /// The last [maxHistory] final lines, oldest first.
  final history = <HistoryEntry>[];

  @override
  CaptionState build() {
    // Word lists and translation options reach a running session at once;
    // models, devices and the backend restart it (keeping loaded models).
    ref.listen(settingsProvider, (previous, next) {
      if (!state.active || previous == null) return;
      if (_models(previous) != _models(next)) _pushStatus();
      if (_needsRestart(previous, next)) {
        _restart?.cancel();
        _restart = Timer(const Duration(milliseconds: 600), () {
          if (state.active) start();
        });
        return;
      }
      final changed =
          previous.glossary != next.glossary ||
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
    ref.onDispose(() {
      _restart?.cancel();
      _subscription?.cancel();
    });
    // The settings window shows the status (it has no caption stream).
    listenSelf((previous, next) {
      if (previous == null ||
          previous.status != next.status ||
          previous.message != next.message ||
          previous.provider != next.provider ||
          previous.device != next.device ||
          previous.lastError != next.lastError) {
        settingsChannel.invokeMethod('caption_status', statusMap(next)).catchError((_) => null);
      }
    });
    return const CaptionState();
  }

  void _pushStatus() => settingsChannel.invokeMethod('caption_status', statusMap(state)).catchError((_) => null);

  Map<String, dynamic> statusMap(CaptionState s) => {
    'status': s.status.name,
    'message': s.message,
    'provider': s.provider,
    'device': s.device,
    'lastError': s.lastError,
    'lines': history.length,
    'pending': modelsPending,
    'remote': _remote ?? '',
  };

  /// Starts captions: from the computer's audio, or from the phone named
  /// [remote] (the mobile app sends its audio; restarts keep listening to
  /// it until [stop]).
  Future<void> start({String? remote}) async {
    // Without ONNX Runtime nothing can load (the caption bar shows why).
    if (ref.read(runtimeInfoProvider).error != null) return;
    _restart?.cancel();
    // The Rust side stops a running session itself, keeping its models
    // loaded for this one.
    await _subscription?.cancel();
    _subscription = null;
    if (remote != null) _remote = remote;
    _remote ??= _phone;
    // Only the computer's own captions come back at the next launch.
    if (_remote == null) _rememberOn(true);
    final s = ref.read(settingsProvider);
    _session = s;
    final paths = ref.read(appPathsProvider);
    state = state.copyWith(status: CaptionStatus.loading, message: 'asr', lastError: '', paused: false);
    final settings = rs.LiveSettings(
      asrModel: s.asrModel,
      asrGpu: s.asrGpu,
      source: s.audioSource == 'microphone' ? rs_app.AudioSourceKind.microphone : rs_app.AudioSourceKind.system,
      deviceId: s.deviceId.isEmpty ? null : s.deviceId,
      vadModelPath: paths.vadModel,
      remoteDevice: _remote,
      vadEnabled: s.vadEnabled,
      vadThreshold: s.vadThreshold,
      minSilenceMs: s.minSilenceMs,
      maxSegmentMs: s.maxSegmentMs,
      partialIntervalMs: s.partialIntervalMs,
      autoGain: s.autoGain,
      hotwords: s.hotwords,
      asrLanguage: s.asrLanguage.isEmpty ? null : s.asrLanguage,
      replacements: replacementRulesOf(s),
      translation: translationSettingsOf(s),
    );
    _idBase = state.lines.isEmpty ? _idBase : state.lines.last.id;
    _subscription = rs
        .startLive(settings: settings)
        .listen(
          _onEvent,
          onError: (Object error) {
            state = state.copyWith(status: CaptionStatus.failed, message: '$error');
          },
        );
  }

  /// Stops the captions. [remember]: they stay off at the next start
  /// (false when the app quits: they come back then).
  Future<void> stop({bool remember = true}) async {
    _restart?.cancel();
    if (remember && _remote == null) _rememberOn(false);
    _session = null;
    _remote = null;
    await _stopSession();
  }

  void _rememberOn(bool on) {
    final settings = ref.read(settingsProvider.notifier);
    if (ref.read(settingsProvider).captionsOn != on) settings.update((s) => s.copyWith(captionsOn: on));
  }

  Future<void> _stopSession() async {
    await _subscription?.cancel();
    _subscription = null;
    if (state.active) {
      await rs.stopLive();
    }
    state = state.copyWith(status: CaptionStatus.idle, level: 0);
  }

  Future<void> toggle() => state.active ? stop() : start();

  void clear() => state = state.copyWith(lines: const []);

  /// Clears the captions, the kept history and the translator's context.
  Future<void> clearContext() async {
    history.clear();
    state = state.copyWith(lines: const []);
    await rs.clearLiveContext();
    settingsChannel.invokeMethod('caption_status', statusMap(state)).catchError((_) => null);
  }

  /// The kept history as text: time, line, translation.
  String historyText() {
    String two(int v) => v.toString().padLeft(2, '0');
    final out = StringBuffer();
    for (final h in history) {
      final t = h.time;
      out.writeln(
        '[${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}] ${h.source}',
      );
      if (h.translation.isNotEmpty) out.writeln('    ${h.translation}');
    }
    return out.toString();
  }

  /// Saves the kept history to a file the user picks.
  Future<void> exportContext() async {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    await FilePicker.saveFile(
      fileName: 'captions-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}.txt',
      bytes: utf8.encode(historyText()),
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );
  }

  void _remember(int id, String source) {
    history.add(HistoryEntry(id: id, time: DateTime.now(), source: source));
    if (history.length > maxHistory) history.removeRange(0, history.length - maxHistory);
    settingsChannel.invokeMethod('caption_status', statusMap(state)).catchError((_) => null);
  }

  void _rememberTranslation(int id, String translation) {
    for (var i = history.length - 1; i >= 0 && i >= history.length - 50; i--) {
      if (history[i].id == id) {
        history[i].translation = translation;
        return;
      }
    }
  }

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
        _upsert(
          _lineId(e),
          (line) => line.copyWith(
            source: e.text,
            stableChars: e.stableChars,
            startMs: e.startMs.toInt(),
            endMs: e.endMs.toInt(),
            asrMs: e.asrMs.toInt(),
          ),
        );
      case rs.CaptionEventKind.final_:
        if (e.text.isEmpty) {
          state = state.copyWith(lines: state.lines.where((l) => l.id != _lineId(e)).toList());
        } else {
          _remember(_lineId(e), e.text);
          _upsert(
            _lineId(e),
            (line) => line.copyWith(
              source: e.text,
              stableChars: e.text.length,
              isFinal: true,
              language: e.language,
              startMs: e.startMs.toInt(),
              endMs: e.endMs.toInt(),
              asrMs: e.asrMs.toInt(),
            ),
          );
        }
      case rs.CaptionEventKind.translation:
        if (!e.partial && e.done && !e.sameLanguage) _rememberTranslation(_lineId(e), e.text);
        _upsert(_lineId(e), (line) {
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
