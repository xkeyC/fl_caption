import 'dart:io';

import 'package:fl_caption/common/rust/candle_models/whisper/model.dart' show WhisperStatus;
import 'package:fl_caption/common/whisper/onnx_models.dart';
import 'package:fl_caption/pages/settings/settings_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fl_caption/common/rust/api/whisper.dart' as rs;

import 'models.dart';

part 'provider.g.dart';

part 'provider.freezed.dart';

enum DartWhisperClientError { modelNotFound, unknown }

@freezed
abstract class DartWhisperClient with _$DartWhisperClient {
  factory DartWhisperClient({required rs.WhisperClient client, DartWhisperClientError? errorType}) = _DartWhisperClient;
}

@riverpod
class DartWhisper extends _$DartWhisper {
  @override
  Future<DartWhisperClient> build() async {
    debugPrint("[DartWhisper] build");
    DartWhisperClientError? errorType;
    final appSettings = await ref.watch(appSettingsProvider.future);
    final modelData = whisperModels[appSettings.whisperModel];
    if (modelData == null) {
      throw "Model Configuration Error: Model ${appSettings.whisperModel} not found in whisperModels";
    }
    final Map<String, String> modelFiles = {};
    final isOnnxModel = modelData is OnnxModelsData;

    if (modelData.downloadUrls.length > 1) {
      for (final entry in modelData.downloadUrls.entries) {
        final fileName = entry.key;
        var modelDir = appSettings.modelWorkingDir;
        if (isOnnxModel) modelDir = "$modelDir/onnx/${modelData.name}";
        modelFiles[fileName] = "$modelDir/$fileName";
      }
    } else {
      modelFiles[modelData.name] = "${appSettings.modelWorkingDir}/onnx/${modelData.name}";
    }

    // check files existence
    for (final entry in modelFiles.entries) {
      if (!await File(entry.value).exists()) {
        errorType = DartWhisperClientError.modelNotFound;
      }
    }

    final modelName = appSettings.whisperModel;
    debugPrint("[DartWhisper] modelName: $modelName modelFile: ${modelFiles[modelName]} errorType: $errorType");
    final config = await getConfigByModel(modelData);
    final tokenizer = await getTokenizerByModel(modelData);
    final modelType = getModelType(modelData);
    debugPrint("[DartWhisper] creating WhisperClient ...");
    final whisper = rs.WhisperClient(
      models: modelFiles,
      config: config,
      tokenizer: tokenizer,
      isMultilingual: modelData.isMultilingual,
      isQuantized: modelData.isQuantized,
      modelType: modelType,
    );
    debugPrint("[DartWhisper] WhisperClient created: $whisper");
    return DartWhisperClient(client: whisper, errorType: errorType);
  }

  Future<String> getConfigByModel(WhisperModelData model) async {
    if (model is OnnxModelsData) {
      if (model.onnxExecMode == "sense-voice") {
        return "";
      }
      return await rootBundle.loadString("assets/whisper/onnx/${model.name}-config.json");
    }
    return await rootBundle.loadString("assets/whisper/${model.configType.name}-config.json");
  }

  Future<Uint8List> getTokenizerByModel(WhisperModelData model) async {
    if (model is OnnxModelsData) {
      if (model.onnxExecMode == "sense-voice") {
        return (await rootBundle.load("assets/whisper/onnx/${model.name}-tokens.txt")).buffer.asUint8List();
      } else {
        return (await rootBundle.load("assets/whisper/onnx/${model.name}-tokenizer.json")).buffer.asUint8List();
      }
    }
    return (await rootBundle.load("assets/whisper/${model.configType.name}-tokenizer.json")).buffer.asUint8List();
  }

  String getModelType(WhisperModelData model) {
    if (model is OnnxModelsData) {
      return "${model.onnxExecMode}_onnx";
    }
    return "whisper";
  }
}

class DartWhisperCaptionResult {
  final String text;
  final Duration? reasoningDuration;
  final Duration? audioDuration;
  final String? reasoningLang;
  final DartWhisperClientError? errorType;
  final WhisperStatus whisperStatus;
  final String? errorMessage;

  const DartWhisperCaptionResult({
    required this.text,
    this.reasoningDuration,
    this.audioDuration,
    this.reasoningLang,
    this.errorType,
    this.whisperStatus = WhisperStatus.loading,
    this.errorMessage,
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
    try {
      _cancelToken = await rs.createCancellationToken();
      debugPrint("[DartWhisperCaption] launchCaption");
      final appSettings = await ref.read(appSettingsProvider.future);
      final vadModelPath = await _checkVadModel(appSettings);
      final sub = rs
          .launchCaption(
            whisperClient: dartWhisper.client,
            cancelTokenId: _cancelToken ?? "",
            audioDeviceIsInput: false,
            audioLanguage: dartWhisper.client.isMultilingual ? appSettings.audioLanguage : null,
            tryWithCuda: appSettings.tryWithCuda,
            whisperMaxAudioDuration: appSettings.whisperMaxAudioDuration.toInt(),
            inferenceInterval: BigInt.from(appSettings.inferenceInterval),
            whisperDefaultMaxDecodeTokens: BigInt.from(appSettings.whisperDefaultMaxDecodeTokens),
            whisperTemperature: appSettings.whisperTemperature,
            vadModelPath: vadModelPath,
            vadFiltersValue: appSettings.vadThreshold,
          )
          .listen(
            (data) async {
              if (data.isNotEmpty) {
                final resultList = data.map((e) => e.dr).toList();
                final newResultList = List.from(resultList);
                for (final r in resultList) {
                  debugPrint(
                    "[DartWhisperCaption] Result:  ${r.text} avgLogprob =${r.avgLogprob.toStringAsFixed(6)} noSpeechProb= ${r.noSpeechProb.toStringAsFixed(6)}",
                  );
                }
                newResultList.removeWhere((e) {
                  // 移除低置信度的结果
                  if (e.avgLogprob < -1.5) {
                    debugPrint("[DartWhisperCaption] Remove low logprob: ${e.avgLogprob}");
                    return true;
                  }
                  if (e.noSpeechProb > 0.8) {
                    debugPrint("[DartWhisperCaption] Remove high no speech prob: ${e.noSpeechProb}");
                    return true;
                  }
                  return false;
                });
                if (newResultList.isEmpty) return;
                final newData = newResultList.map((e) => e.text).toList().join(" ");
                state = AsyncData(
                  DartWhisperCaptionResult(
                    text: newData,
                    reasoningDuration: Duration(milliseconds: data.lastOrNull?.reasoningDuration?.toInt() ?? 0),
                    audioDuration: Duration(milliseconds: data.lastOrNull?.audioDuration?.toInt() ?? 0),
                    reasoningLang: data.lastOrNull?.reasoningLang,
                    errorType: dartWhisper.errorType,
                    whisperStatus: data.lastOrNull?.status ?? WhisperStatus.loading,
                  ),
                );
              }
            },
            onDone: () {
              debugPrint("[DartWhisperCaption] Done");
            },
            onError: (e) {
              debugPrint("[DartWhisperCaption] Error: $e");
              state = AsyncData(
                DartWhisperCaptionResult(
                  text: "",
                  errorType: dartWhisper.errorType,
                  errorMessage: e.toString(),
                  whisperStatus: WhisperStatus.error,
                ),
              );
            },
          );
      ref.onDispose(() {
        debugPrint("[DartWhisperCaption] Dispose");
        sub.cancel();
        cancel(_cancelToken);
      });
    } catch (e) {
      debugPrint("[DartWhisperCaption] Error: $e");
      return DartWhisperCaptionResult(text: "", errorType: dartWhisper.errorType, errorMessage: e.toString());
    }

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

  Future<String?> _checkVadModel(AppSettingsData appSettings) async {
    if (!appSettings.withVAD) return null;
    final vadModelPath = "${(await getApplicationSupportDirectory()).absolute.path}/vad_model/silero-vad-v5_q4.onnx"
        .replaceAll("\\", "/");
    final file = File(vadModelPath);
    if (await file.exists()) {
      debugPrint("[DartWhisperCaption] Vad model exists");
      return vadModelPath;
    } else {
      // extract from assets
      debugPrint("[DartWhisperCaption] Vad model not found, extracting from assets");
      const assetsPath = "assets/models/silero-vad-v5_q4.onnx";
      final bytes = await rootBundle.load(assetsPath);
      await file.create(recursive: true);
      await file.writeAsBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes), flush: true);
      debugPrint("[DartWhisperCaption] Vad model extracted to $vadModelPath");
      return vadModelPath;
    }
  }
}
