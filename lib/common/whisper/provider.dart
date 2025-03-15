import 'dart:io';

import 'package:fl_caption/common/settings_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fl_caption/common/rust/api/whisper.dart' as rs;

import 'models.dart';

part 'provider.g.dart';

part 'provider.freezed.dart';

enum DartWhisperClientError { modelNotFound, unknown }

@freezed
class DartWhisperClient with _$DartWhisperClient {
  factory DartWhisperClient({
    required rs.WhisperClient client,
    DartWhisperClientError? errorType,
  }) = _DartWhisperClient;
}

@riverpod
class DartWhisper extends _$DartWhisper {
  @override
  Future<DartWhisperClient> build() async {
    debugPrint("[DartWhisper] build");
    DartWhisperClientError? errorType;
    final appSettings = await ref.watch(appSettingsProvider.future);
    // check file exist
    final modelFile = File(
      '${appSettings.modelWorkingDir}/${appSettings.whisperModel}',
    );
    if (!await modelFile.exists()) {
      errorType = DartWhisperClientError.modelNotFound;
    }
    final modelName = appSettings.whisperModel;
    final modelData = whisperModels[modelName];
    debugPrint(
      "[DartWhisper] modelName: $modelName modelFile: ${modelFile.absolute.path} errorType: $errorType",
    );
    final config = await getConfigByName(modelName);
    final tokenizer = await getTokenizerByName(modelName);
    debugPrint("[DartWhisper] creating WhisperClient ...");
    final whisper = rs.WhisperClient(
      whisperModel: modelFile.absolute.path,
      whisperConfig: config,
      whisperTokenizer: tokenizer,
      isMultilingual: modelData?.isMultilingual ?? true,
      isQuantized: modelData?.isQuantized ?? false,
    );
    debugPrint("[DartWhisper] WhisperClient created: $whisper");
    return DartWhisperClient(client: whisper, errorType: errorType);
  }

  Future<String> getConfigByName(String name) async {
    return await rootBundle.loadString("assets/whisper/$name-config.json");
  }

  Future<Uint8List> getTokenizerByName(String name) async {
    return (await rootBundle.load(
      "assets/whisper/$name-tokenizer.json",
    )).buffer.asUint8List();
  }
}

class DartWhisperCaptionResult {
  final String text;
  final Duration? reasoningDuration;
  final Duration? audioDuration;
  final String? reasoningLang;
  final DartWhisperClientError? errorType;

  const DartWhisperCaptionResult({
    required this.text,
    this.reasoningDuration,
    this.audioDuration,
    this.reasoningLang,
    this.errorType,
  });
}

@riverpod
class DartWhisperCaption extends _$DartWhisperCaption {
  String? _cancelToken;

  bool _isPaused = false;

  @override
  Future<DartWhisperCaptionResult> build() async {
    debugPrint("[DartWhisperCaption] build");
    final dartWhisper = await ref.watch(dartWhisperProvider.future);
    debugPrint("[DartWhisperCaption] WhisperClient: ${dartWhisper.client}");
    _cancelToken = await rs.createCancellationToken();
    debugPrint("[DartWhisperCaption] launchCaption");
    final appSettings = await ref.read(appSettingsProvider.future);
    final sub = rs
        .launchCaption(
          whisperClient: dartWhisper.client,
          cancelTokenId: _cancelToken ?? "",
          audioDeviceIsInput: false,
          audioLanguage: appSettings.audioLanguage,
          tryWithCuda: appSettings.tryWithCuda,
        )
        .listen(
          (data) {
            if (data.isNotEmpty) {
              // debugPrint("[DartWhisperCaption] Data: $data");
              final newData = data.map((e) => e.dr.text).toList().join(" ");
              if (newData.isNotEmpty) {
                // debugPrint("[DartWhisperCaption] New Data: $newData");
                state = AsyncData(
                  DartWhisperCaptionResult(
                    text: newData,
                    reasoningDuration: Duration(
                      milliseconds:
                          data.lastOrNull?.reasoningDuration?.toInt() ?? 0,
                    ),
                    audioDuration: Duration(
                      milliseconds:
                          data.lastOrNull?.audioDuration?.toInt() ?? 0,
                    ),
                    reasoningLang: data.lastOrNull?.reasoningLang,
                    errorType: dartWhisper.errorType,
                  ),
                );
              }
            }
          },
          onDone: () {
            debugPrint("[DartWhisperCaption] Done");
          },
          onError: (e) {
            debugPrint("[DartWhisperCaption] Error: $e");
          },
        );
    ref.onDispose(() {
      debugPrint("[DartWhisperCaption] Dispose");
      sub.cancel();
      cancel(_cancelToken);
    });
    return DartWhisperCaptionResult(text: "", errorType: dartWhisper.errorType);
  }

  bool get isPaused => _isPaused;

  void pause() {
    debugPrint("[DartWhisperCaption] Pause");
    _isPaused = true;
    cancel(_cancelToken);
  }

  void resume() {
    debugPrint("[DartWhisperCaption] Resume");
    _isPaused = false;
    ref.invalidateSelf();
  }

  void cancel(String? cancelToken) {
    if (cancelToken == null) return;
    debugPrint("[DartWhisperCaption] Cancel");
    rs.cancelCancellationToken(tokenId: cancelToken);
    _cancelToken = null;
  }
}
