import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_caption/common/io/http.dart';
import 'package:fl_caption/common/whisper/models.dart';
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
    required double currentProgress,
    required int currentTotal,
    required bool isReady,
    @Default(0) currentDownloadFileIndex,
    String? errorText,
  }) = _ModelDownloadStateData;

  factory ModelDownloadStateData.fromJson(Map<String, dynamic> json) => _$ModelDownloadStateDataFromJson(json);
}

@riverpod
class ModelDownloadState extends _$ModelDownloadState {
  @override
  ModelDownloadStateData build(String modelName, String savePath) {
    state = ModelDownloadStateData(
      modelName: modelName,
      modelPath: savePath,
      currentProgress: 0,
      currentTotal: 0,
      isReady: false,
    );
    final allExist = modelFileNames.every((fileName) {
      final filePath = "${modelDirectory.absolute.path}/$fileName";
      return File(filePath).existsSync();
    });

    ref.onDispose(() {
      _downloadCancelToken?.cancel();
      _downloadCancelToken = null;
    });

    return ModelDownloadStateData(
      modelName: modelName,
      modelPath: savePath,
      currentProgress: allExist ? 100 : 0,
      currentTotal: 0,
      isReady: allExist,
    );
  }

  bool get isMultipleFiles {
    final modelData = whisperModels[state.modelName];
    return (modelData?.downloadUrls.length ?? 0) > 1;
  }

  Directory get modelDirectory {
    final modelData = whisperModels[state.modelName];
    final isOnnxModel = modelData?.configType == WhisperModelConfigType.onnx;
    if (isMultipleFiles) {
      if (isOnnxModel) {
        return Directory("${state.modelPath}/onnx/${state.modelName}");
      }
      return Directory("${state.modelPath}/${state.modelName}");
    }
    if (isOnnxModel) {
      return Directory("${state.modelPath}/onnx");
    }
    return Directory(state.modelPath);
  }

  List<String> get modelFileNames {
    final modelData = whisperModels[state.modelName];
    return modelData?.downloadUrls.keys.toList() ?? <String>[];
  }

  CancelToken? _downloadCancelToken;

  Future<bool> startDownload() async {
    if (state.errorText != null) {
      state = state.copyWith(errorText: null);
    }
    if (state.isReady) return true;

    final downloadUrlsMap = whisperModels[state.modelName]?.getDownloadUrls();
    if (downloadUrlsMap == null || downloadUrlsMap.isEmpty) {
      state = state.copyWith(errorText: "下载链接未找到", isReady: false, currentProgress: 0);
      return false;
    }
    var modelPath = modelDirectory.absolute.path;
    final dir = Directory(modelPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final dio = await RDio.createRDioClient();

    _downloadCancelToken = CancelToken();
    for (final downloadItem in downloadUrlsMap.entries) {
      final fileName = downloadItem.key;
      final fileUrl = downloadItem.value;
      final modelFile = File("$modelPath/$fileName");
      if (await modelFile.exists()) {
        debugPrint("Model file ${modelFile.path} already exists, skipping download.");
        state = state.copyWith(currentDownloadFileIndex: state.currentDownloadFileIndex + 1);
        continue;
      }
      final modelFileDownloading = File("${modelFile.path}.downloading");
      try {
        state = state.copyWith(currentProgress: 0, currentTotal: 0, errorText: null);
        final response = await dio.download(
          fileUrl,
          modelFileDownloading.absolute.path,
          cancelToken: _downloadCancelToken,
          onReceiveProgress: (received, total) {
            if (total != -1) {
              state = state.copyWith(currentProgress: (received / total * 100).toDouble(), currentTotal: total);
            }
          },
        );
        _downloadCancelToken = null;
        if (response.statusCode == 200) {
          await modelFileDownloading.rename(modelFile.absolute.path);
          state = state.copyWith(isReady: true, currentProgress: 100);
          debugPrint("Model ${state.modelName} downloaded successfully to ${state.modelPath}");
        } else {
          state = state.copyWith(errorText: "下载失败: ${response.statusCode}", isReady: false, currentProgress: 0);
          return false;
        }
      } catch (e) {
        state = state.copyWith(errorText: "下载失败: $e", isReady: false, currentProgress: 0);
        return false;
      }
      state = state.copyWith(currentDownloadFileIndex: state.currentDownloadFileIndex + 1);
      debugPrint("Model file ${modelFile.path} downloaded successfully.");
    }

    return true;
  }

  Future<void> cancelDownload() async {
    if (_downloadCancelToken != null) {
      _downloadCancelToken!.cancel();
      _downloadCancelToken = null;
    }
  }
}
