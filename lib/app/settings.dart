import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'windows.dart';

/// A glossary entry: a term, its translation, and whether it is also
/// given to the speech model as a hotword (Fun-ASR-Nano).
@immutable
class GlossaryEntry {
  const GlossaryEntry({required this.source, this.target = '', this.hotword = true, this.enabled = true});

  final String source;
  final String target;
  final bool hotword;
  final bool enabled;

  GlossaryEntry copyWith({String? source, String? target, bool? hotword, bool? enabled}) => GlossaryEntry(
    source: source ?? this.source,
    target: target ?? this.target,
    hotword: hotword ?? this.hotword,
    enabled: enabled ?? this.enabled,
  );

  Map<String, dynamic> toJson() => {'source': source, 'target': target, 'hotword': hotword, 'enabled': enabled};

  factory GlossaryEntry.fromJson(Map<String, dynamic> json) => GlossaryEntry(
    source: json['source'] as String? ?? '',
    target: json['target'] as String? ?? '',
    hotword: json['hotword'] as bool? ?? true,
    enabled: json['enabled'] as bool? ?? true,
  );
}

/// A correction applied to recognized text.
@immutable
class ReplacementEntry {
  const ReplacementEntry({required this.from, this.to = '', this.enabled = true});

  final String from;
  final String to;
  final bool enabled;

  ReplacementEntry copyWith({String? from, String? to, bool? enabled}) =>
      ReplacementEntry(from: from ?? this.from, to: to ?? this.to, enabled: enabled ?? this.enabled);

  Map<String, dynamic> toJson() => {'from': from, 'to': to, 'enabled': enabled};

  factory ReplacementEntry.fromJson(Map<String, dynamic> json) => ReplacementEntry(
    from: json['from'] as String? ?? '',
    to: json['to'] as String? ?? '',
    enabled: json['enabled'] as bool? ?? true,
  );
}

enum TranslatorKind { local, api }

enum ApiStyle { chat, translationModel }

enum CaptionLines { both, translationOnly, sourceOnly }

enum SubtitleLinesMode { source, translation, both, bothTranslationFirst }

/// Everything the user sets, saved as JSON in the app support directory.
@immutable
class AppSettings {
  const AppSettings({
    this.uiLanguage = 'system',
    this.modelsDir = '',
    this.importedModels = const {},
    this.hfEndpoint = '',
    this.asrModel = 'sensevoice-small-int8-gpu-onnx',
    this.asrGpu = true,
    this.audioSource = 'system',
    this.deviceId = '',
    this.asrLanguage = '',
    this.vadThreshold = 0.5,
    this.minSilenceMs = 500,
    this.maxSegmentMs = 12000,
    this.partialIntervalMs = 400,
    this.autoGain = false,
    this.translationEnabled = true,
    this.translator = TranslatorKind.local,
    this.localTranslator = 'hy-mt2-1.8b-int4-onnx',
    this.localGpu = true,
    this.contextTokens = 4096,
    this.apiBaseUrl = '',
    this.apiKey = '',
    this.apiModel = '',
    this.apiStyle = ApiStyle.chat,
    this.targetLanguage = 'zh',
    this.background = '',
    this.contextLines = 4,
    this.temperature = 0.0,
    this.translatePartials = true,
    this.skipSameLanguage = true,
    this.glossary = const [],
    this.replacements = const [],
    this.captionLines = CaptionLines.both,
    this.translationFirst = true,
    this.historyLines = 1,
    this.sourceFontSize = 16,
    this.translationFontSize = 24,
    this.backgroundOpacity = 0.55,
    this.textColor = 0xFFFFFFFF,
    this.showStatus = true,
    this.overlayBounds,
    this.fileFormats = const ['srt'],
    this.fileLines = SubtitleLinesMode.both,
    this.fileOutputDir = '',
    this.maxCueMs = 7000,
    this.maxCueWidth = 44,
    this.stripEndPunctuation = true,
    this.ffmpegPath = '',
    this.captionsOn = false,
  });

  final String uiLanguage;
  final String modelsDir;
  final Map<String, String> importedModels;
  final String hfEndpoint;

  final String asrModel;
  final bool asrGpu;

  /// `system` (what the speakers play) or `microphone`.
  final String audioSource;
  final String deviceId;
  final String asrLanguage;
  final double vadThreshold;
  final int minSilenceMs;
  final int maxSegmentMs;
  final int partialIntervalMs;

  /// Boost quiet input before the VAD (off: it can merge sentences).
  final bool autoGain;

  final bool translationEnabled;
  final TranslatorKind translator;
  final String localTranslator;
  final bool localGpu;
  final int contextTokens;
  final String apiBaseUrl;
  final String apiKey;
  final String apiModel;
  final ApiStyle apiStyle;
  final String targetLanguage;
  final String background;
  final int contextLines;
  final double temperature;
  final bool translatePartials;
  final bool skipSameLanguage;

  final List<GlossaryEntry> glossary;
  final List<ReplacementEntry> replacements;

  final CaptionLines captionLines;
  final bool translationFirst;

  /// Earlier lines kept above the current one in the overlay.
  final int historyLines;
  final double sourceFontSize;
  final double translationFontSize;
  final double backgroundOpacity;
  final int textColor;
  final bool showStatus;

  /// left, top, width, height of the caption bar.
  final List<double>? overlayBounds;

  final List<String> fileFormats;
  final SubtitleLinesMode fileLines;
  final String fileOutputDir;
  final int maxCueMs;
  final int maxCueWidth;
  final bool stripEndPunctuation;
  final String ffmpegPath;

  /// Captions were running when the app last quit: start them again.
  final bool captionsOn;

  List<String> get hotwords =>
      glossary.where((e) => e.enabled && e.hotword && e.source.trim().isNotEmpty).map((e) => e.source.trim()).toList();

  AppSettings copyWith({
    String? uiLanguage,
    String? modelsDir,
    Map<String, String>? importedModels,
    String? hfEndpoint,
    String? asrModel,
    bool? asrGpu,
    String? audioSource,
    String? deviceId,
    String? asrLanguage,
    double? vadThreshold,
    int? minSilenceMs,
    int? maxSegmentMs,
    int? partialIntervalMs,
    bool? autoGain,
    bool? translationEnabled,
    TranslatorKind? translator,
    String? localTranslator,
    bool? localGpu,
    int? contextTokens,
    String? apiBaseUrl,
    String? apiKey,
    String? apiModel,
    ApiStyle? apiStyle,
    String? targetLanguage,
    String? background,
    int? contextLines,
    double? temperature,
    bool? translatePartials,
    bool? skipSameLanguage,
    List<GlossaryEntry>? glossary,
    List<ReplacementEntry>? replacements,
    CaptionLines? captionLines,
    bool? translationFirst,
    int? historyLines,
    double? sourceFontSize,
    double? translationFontSize,
    double? backgroundOpacity,
    int? textColor,
    bool? showStatus,
    List<double>? overlayBounds,
    List<String>? fileFormats,
    SubtitleLinesMode? fileLines,
    String? fileOutputDir,
    int? maxCueMs,
    int? maxCueWidth,
    bool? stripEndPunctuation,
    String? ffmpegPath,
    bool? captionsOn,
  }) {
    return AppSettings(
      uiLanguage: uiLanguage ?? this.uiLanguage,
      modelsDir: modelsDir ?? this.modelsDir,
      importedModels: importedModels ?? this.importedModels,
      hfEndpoint: hfEndpoint ?? this.hfEndpoint,
      asrModel: asrModel ?? this.asrModel,
      asrGpu: asrGpu ?? this.asrGpu,
      audioSource: audioSource ?? this.audioSource,
      deviceId: deviceId ?? this.deviceId,
      asrLanguage: asrLanguage ?? this.asrLanguage,
      vadThreshold: vadThreshold ?? this.vadThreshold,
      minSilenceMs: minSilenceMs ?? this.minSilenceMs,
      maxSegmentMs: maxSegmentMs ?? this.maxSegmentMs,
      partialIntervalMs: partialIntervalMs ?? this.partialIntervalMs,
      autoGain: autoGain ?? this.autoGain,
      translationEnabled: translationEnabled ?? this.translationEnabled,
      translator: translator ?? this.translator,
      localTranslator: localTranslator ?? this.localTranslator,
      localGpu: localGpu ?? this.localGpu,
      contextTokens: contextTokens ?? this.contextTokens,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      apiKey: apiKey ?? this.apiKey,
      apiModel: apiModel ?? this.apiModel,
      apiStyle: apiStyle ?? this.apiStyle,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      background: background ?? this.background,
      contextLines: contextLines ?? this.contextLines,
      temperature: temperature ?? this.temperature,
      translatePartials: translatePartials ?? this.translatePartials,
      skipSameLanguage: skipSameLanguage ?? this.skipSameLanguage,
      glossary: glossary ?? this.glossary,
      replacements: replacements ?? this.replacements,
      captionLines: captionLines ?? this.captionLines,
      translationFirst: translationFirst ?? this.translationFirst,
      historyLines: historyLines ?? this.historyLines,
      sourceFontSize: sourceFontSize ?? this.sourceFontSize,
      translationFontSize: translationFontSize ?? this.translationFontSize,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      textColor: textColor ?? this.textColor,
      showStatus: showStatus ?? this.showStatus,
      overlayBounds: overlayBounds ?? this.overlayBounds,
      fileFormats: fileFormats ?? this.fileFormats,
      fileLines: fileLines ?? this.fileLines,
      fileOutputDir: fileOutputDir ?? this.fileOutputDir,
      maxCueMs: maxCueMs ?? this.maxCueMs,
      maxCueWidth: maxCueWidth ?? this.maxCueWidth,
      stripEndPunctuation: stripEndPunctuation ?? this.stripEndPunctuation,
      ffmpegPath: ffmpegPath ?? this.ffmpegPath,
      captionsOn: captionsOn ?? this.captionsOn,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 2,
    'uiLanguage': uiLanguage,
    'modelsDir': modelsDir,
    'importedModels': importedModels,
    'hfEndpoint': hfEndpoint,
    'asrModel': asrModel,
    'asrGpu': asrGpu,
    'audioSource': audioSource,
    'deviceId': deviceId,
    'asrLanguage': asrLanguage,
    'vadThreshold': vadThreshold,
    'minSilenceMs': minSilenceMs,
    'maxSegmentMs': maxSegmentMs,
    'partialIntervalMs': partialIntervalMs,
    'autoGain': autoGain,
    'translationEnabled': translationEnabled,
    'translator': translator.name,
    'localTranslator': localTranslator,
    'localGpu': localGpu,
    'contextTokens': contextTokens,
    'apiBaseUrl': apiBaseUrl,
    'apiKey': apiKey,
    'apiModel': apiModel,
    'apiStyle': apiStyle.name,
    'targetLanguage': targetLanguage,
    'background': background,
    'contextLines': contextLines,
    'temperature': temperature,
    'translatePartials': translatePartials,
    'skipSameLanguage': skipSameLanguage,
    'glossary': glossary.map((e) => e.toJson()).toList(),
    'replacements': replacements.map((e) => e.toJson()).toList(),
    'captionLines': captionLines.name,
    'translationFirst': translationFirst,
    'historyLines': historyLines,
    'sourceFontSize': sourceFontSize,
    'translationFontSize': translationFontSize,
    'backgroundOpacity': backgroundOpacity,
    'textColor': textColor,
    'showStatus': showStatus,
    'overlayBounds': overlayBounds,
    'fileFormats': fileFormats,
    'fileLines': fileLines.name,
    'fileOutputDir': fileOutputDir,
    'maxCueMs': maxCueMs,
    'maxCueWidth': maxCueWidth,
    'stripEndPunctuation': stripEndPunctuation,
    'ffmpegPath': ffmpegPath,
    'captionsOn': captionsOn,
  };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    const d = AppSettings();
    T pick<T>(String key, T fallback) {
      final value = j[key];
      if (value is T) return value;
      if (fallback is double && value is num) return value.toDouble() as T;
      if (fallback is int && value is num) return value.toInt() as T;
      return fallback;
    }

    E pickEnum<E extends Enum>(String key, List<E> values, E fallback) =>
        values.where((v) => v.name == j[key]).firstOrNull ?? fallback;

    List<T> list<T>(String key, T Function(Map<String, dynamic>) parse) =>
        (j[key] as List? ?? const []).whereType<Map>().map((e) => parse(Map<String, dynamic>.from(e))).toList();

    return AppSettings(
      uiLanguage: pick('uiLanguage', d.uiLanguage),
      modelsDir: pick('modelsDir', d.modelsDir),
      importedModels: Map<String, String>.from(j['importedModels'] as Map? ?? const {}),
      hfEndpoint: pick('hfEndpoint', d.hfEndpoint),
      asrModel: pick('asrModel', d.asrModel),
      asrGpu: pick('asrGpu', d.asrGpu),
      audioSource: pick('audioSource', d.audioSource),
      deviceId: pick('deviceId', d.deviceId),
      asrLanguage: pick('asrLanguage', d.asrLanguage),
      vadThreshold: pick('vadThreshold', d.vadThreshold),
      minSilenceMs: pick('minSilenceMs', d.minSilenceMs),
      maxSegmentMs: pick('maxSegmentMs', d.maxSegmentMs),
      partialIntervalMs: pick('partialIntervalMs', d.partialIntervalMs),
      autoGain: pick('autoGain', d.autoGain),
      translationEnabled: pick('translationEnabled', d.translationEnabled),
      translator: pickEnum('translator', TranslatorKind.values, d.translator),
      localTranslator: pick('localTranslator', d.localTranslator),
      localGpu: pick('localGpu', d.localGpu),
      contextTokens: pick('contextTokens', d.contextTokens),
      apiBaseUrl: pick('apiBaseUrl', d.apiBaseUrl),
      apiKey: pick('apiKey', d.apiKey),
      apiModel: pick('apiModel', d.apiModel),
      apiStyle: pickEnum('apiStyle', ApiStyle.values, d.apiStyle),
      targetLanguage: pick('targetLanguage', d.targetLanguage),
      background: pick('background', d.background),
      contextLines: pick('contextLines', d.contextLines),
      temperature: pick('temperature', d.temperature),
      translatePartials: pick('translatePartials', d.translatePartials),
      skipSameLanguage: pick('skipSameLanguage', d.skipSameLanguage),
      glossary: list('glossary', GlossaryEntry.fromJson),
      replacements: list('replacements', ReplacementEntry.fromJson),
      captionLines: pickEnum('captionLines', CaptionLines.values, d.captionLines),
      translationFirst: pick('translationFirst', d.translationFirst),
      historyLines: pick('historyLines', d.historyLines),
      sourceFontSize: pick('sourceFontSize', d.sourceFontSize),
      translationFontSize: pick('translationFontSize', d.translationFontSize),
      backgroundOpacity: pick('backgroundOpacity', d.backgroundOpacity),
      textColor: pick('textColor', d.textColor),
      showStatus: pick('showStatus', d.showStatus),
      overlayBounds: (j['overlayBounds'] as List?)?.whereType<num>().map((e) => e.toDouble()).toList(),
      fileFormats: (j['fileFormats'] as List?)?.whereType<String>().toList() ?? d.fileFormats,
      fileLines: pickEnum('fileLines', SubtitleLinesMode.values, d.fileLines),
      fileOutputDir: pick('fileOutputDir', d.fileOutputDir),
      maxCueMs: pick('maxCueMs', d.maxCueMs),
      maxCueWidth: pick('maxCueWidth', d.maxCueWidth),
      stripEndPunctuation: pick('stripEndPunctuation', d.stripEndPunctuation),
      ffmpegPath: pick('ffmpegPath', d.ffmpegPath),
      captionsOn: pick('captionsOn', d.captionsOn),
    );
  }
}

/// Paths fixed at start-up.
class AppPaths {
  const AppPaths({required this.supportDir, required this.vadModel, required this.defaultModelsDir});

  final String supportDir;
  final String vadModel;
  final String defaultModelsDir;

  String get settingsFile => '$supportDir${Platform.pathSeparator}settings.json';
  String get logDir => '$supportDir${Platform.pathSeparator}logs';
}

final appPathsProvider = Provider<AppPaths>((ref) => throw UnimplementedError('overridden in main'));

final initialSettingsProvider = Provider<AppSettings>((ref) => throw UnimplementedError('overridden in main'));

class SettingsNotifier extends Notifier<AppSettings> {
  /// Set in the settings window: every change also goes to the main window
  /// (which runs the captions).
  static bool sendToMainWindow = false;

  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  void update(AppSettings Function(AppSettings) change) {
    state = change(state);
    // Only the main window writes the file: this window's copy of what the
    // main window owns (bar position, caption state) may be older.
    if (sendToMainWindow) {
      mainChannel.invokeMethod('settings_changed', jsonEncode(state.toJson())).catchError((_) => null);
    } else {
      _save();
    }
  }

  /// Settings changed in the settings window. The caption bar keeps its own
  /// position and caption state (the other window's copy may be older).
  void receive(AppSettings settings) {
    state = settings.copyWith(overlayBounds: state.overlayBounds, captionsOn: state.captionsOn);
    _save();
  }

  Future<void>? _pending;

  void _save() {
    // Coalesce bursts of changes (sliders) into one write.
    _pending ??= Future.delayed(const Duration(milliseconds: 300), () async {
      _pending = null;
      final path = ref.read(appPathsProvider).settingsFile;
      final file = File(path);
      await file.parent.create(recursive: true);
      final temp = File('$path.tmp');
      await temp.writeAsString(const JsonEncoder.withIndent('  ').convert(state.toJson()));
      await temp.rename(path);
    });
  }

  static Future<AppSettings> load(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        return AppSettings.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
      }
    } catch (error) {
      debugPrint('settings unreadable, using defaults: $error');
    }
    return const AppSettings();
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
