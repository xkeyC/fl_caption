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

@riverpod
class DartWhisperCaption extends _$DartWhisperCaption {
  rs.CancellationToken? _cancelToken;

  @override
  Future<String> build() async {
    debugPrint("[DartWhisperCaption] build");
    final dartWhisper = await ref.watch(dartWhisperProvider.future);
    debugPrint("[DartWhisperCaption] WhisperClient: ${dartWhisper.client}");
    _cancelToken = await rs.createCancellationToken();
    debugPrint("[DartWhisperCaption] launchCaption");
    final sub = rs
        .launchCaption(
          whisperClient: dartWhisper.client,
          cancelToken: _cancelToken!,
          audioDeviceIsInput: false,
        )
        .listen(
          (data) {
            if (data.isNotEmpty) {
              debugPrint("[DartWhisperCaption] Data: $data");
              final newData = data.map((e) => e.dr.text).toList().join(" ");
              // 如果 newData + state 大于 120 字符 ，则作为一个新的 state
              final stateLen = (state.value?.length ?? 0);
              final newDataLen = newData.length;
              if (stateLen + newDataLen > 240) {
                state = AsyncValue.data(newData);
              } else {
                state = AsyncValue.data((state.value ?? "") + newData);
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
      sub.cancel();
    });
    return "";
  }

  void cancel() {
    debugPrint("[DartWhisperCaption] Cancel");
    if (_cancelToken != null) {
      rs.cancelCancellationToken(token: _cancelToken!);
      _cancelToken = null;
    }
  }
}
