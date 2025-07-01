import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_caption/common/io/http.dart';
import 'package:fl_caption/common/whisper/models.dart';
import 'package:fl_caption/common/whisper/onnx_models.dart';
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'model_download_provider.g.dart';

part 'model_download_provider.freezed.dart';

@freezed
abstract class ModelDownloadStateData with _$ModelDownloadStateData {
  factory ModelDownloadStateData({
    required String modelName,
    required String modelPath,
    required double progress,
    required bool isReady,
    String? errorText,
  }) = _ModelDownloadStateData;

  factory ModelDownloadStateData.fromJson(Map<String, dynamic> json) => _$ModelDownloadStateDataFromJson(json);
}

@riverpod
class ModelDownloadState extends _$ModelDownloadState {
  @override
  ModelDownloadStateData build(String modelName, String savePath) {
    final modelData = whisperModels[modelName];
    late final File modelFile;
    if (modelData is OnnxModelsData) {
      modelFile = File('$savePath/onnx/${modelData.name}');
    } else {
      modelFile = File('$savePath/${modelData?.name ?? modelName}');
    }

    final fileExists = modelFile.existsSync();

    ref.onDispose(() {
      _downloadCancelToken?.cancel();
      _downloadCancelToken = null;
    });

    return ModelDownloadStateData(
      modelName: modelName,
      modelPath: savePath,
      progress: fileExists ? 100 : 0,
      isReady: fileExists,
    );
  }

  CancelToken? _downloadCancelToken;

  Future<bool> startDownload() async {
    if (state.errorText != null) {
      state = state.copyWith(errorText: null);
    }
    if (state.isReady) return true;
    final dir = Directory(state.modelPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final modelFile = File("${state.modelPath}/${state.modelName}.downloading");
    final dio = await RDio.createRDioClient();
    final downloadUrl = whisperModels[state.modelName]?.getDownloadUrl() ?? "";
    _downloadCancelToken = CancelToken();
    try {
      final response = await dio.download(
        downloadUrl,
        modelFile.path,
        cancelToken: _downloadCancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            state = state.copyWith(progress: (received / total * 100).toDouble());
          }
        },
      );
      _downloadCancelToken = null;
      if (response.statusCode == 200) {
        await modelFile.rename("${state.modelPath}/${state.modelName}");
        state = state.copyWith(isReady: true, progress: 100);
        debugPrint("Model ${state.modelName} downloaded successfully to ${state.modelPath}");
        return true;
      } else {
        state = state.copyWith(errorText: "下载失败: ${response.statusCode}", isReady: false, progress: 0);
      }
    } catch (e) {
      state = state.copyWith(errorText: "下载失败: $e", isReady: false, progress: 0);
    }
    return false;
  }

  Future<void> cancelDownload() async {
    if (_downloadCancelToken != null) {
      _downloadCancelToken!.cancel();
      _downloadCancelToken = null;
    }
  }
}
