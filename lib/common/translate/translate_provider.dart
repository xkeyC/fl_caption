import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fl_caption/common/io/http.dart';
import 'package:fl_caption/common/settings_provider.dart';
import 'package:fl_caption/common/whisper/language.dart';
import 'package:fl_caption/common/whisper/provider.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:synchronized/synchronized.dart';

part 'translate_provider.g.dart';

@riverpod
class TranslateProvider extends _$TranslateProvider {
  @override
  String build() {
    ref.listen(dartWhisperCaptionProvider, (p, n) async {
      _updateTranslate(p?.value?.text, n.value?.text, n.value?.reasoningLang);
    });
    return "";
  }

  void _updateTranslate(String? p, String? n, String? lang) async {
    final appSettings = await ref.watch(appSettingsProvider.future);
    if (appSettings.llmProviderUrl.isEmpty ||
        appSettings.llmProviderModel.isEmpty) {
      state = "<Not config llm>";
      return;
    }
    if (appSettings.captionLanguage == null) {
      state = "<Not config captionLanguage>";
      return;
    }
    final captionLanguage = whisperLanguages[appSettings.captionLanguage!]!;
    final pText = p ?? "";
    final text = n ?? "";
    if (pText == text) return;
    if (text.isEmpty) return;
    _doTranslate(
      text: text,
      appSettings: appSettings,
      captionLanguage: captionLanguage,
    );
  }

  final _asyncLock = Lock();

  Dio? _dio;

  void _doTranslate({
    required String text,
    required AppSettingsData appSettings,
    required WhisperLanguage captionLanguage,
  }) async {
    await _asyncLock.synchronized(() async {
      // state = "";
      _dio ??= await RDio.createRDioClient();
      final cancelToken = CancelToken();
      ref.onDispose(() {
        cancelToken.cancel();
        _dio = null;
      });
      try {
        // Set up streaming request
        final response = await _dio!.post(
          appSettings.llmProviderUrl,
          data: {
            "model": appSettings.llmProviderModel,
            "messages": [
              {
                "role": "system",
                "content":
                    "<system>You are an online subtitle translator, translating user input into ${captionLanguage.displayName} (${captionLanguage.code}), and out put to result block; eg: <result>This is Translate Output</result>> </system>",
              },
              {"role": "user", "content": text},
            ],
            "temperature": 0.1,
            "stream": true, // Enable streaming
            "max_tokens": 256,
          },
          options: Options(
            headers: {
              "Authorization": "Bearer ${appSettings.llmProviderKey}",
              "Content-Type": "application/json",
              "Accept": "text/event-stream",
              "Accept-Charset": "utf-8",
            },
            responseType: ResponseType.stream, // Set response type to stream
            sendTimeout: Duration(seconds: 1),
            receiveTimeout: Duration(seconds: 1),
          ),
          cancelToken: cancelToken,
        );

        String partialTranslation = "";

        // Process the stream data
        final stream = response.data.stream as Stream<List<int>>;
        await for (final chunk in stream
            .transform(unit8Transformer)
            .transform(const Utf8Decoder())
            .transform(const LineSplitter())) {
          // Split by "data: " for SSE format
          final lines = chunk.split('data: ');
          for (final line in lines) {
            if (line.trim().isEmpty || line.trim() == '[DONE]') continue;
            try {
              final jsonData = jsonDecode(line);
              final content =
                  jsonData['choices']?[0]?['delta']?['content'] as String?;
              if (content != null) {
                partialTranslation += content;
              }
            } catch (e) {
              // Skip invalid JSON chunks
              continue;
            }
          }
        }
        // Update the state with the final translation [partialTranslation] eg:<result>This is Translate Output</result>
        final resultRegex = RegExp(r'<result>(.*?)</result>', dotAll: true);
        final match = resultRegex.firstMatch(partialTranslation);
        if (match != null && match.groupCount >= 1) {
          state = match.group(1) ?? "";
        } else {
          state = partialTranslation;
        }
      } catch (e) {
        debugPrint("[TranslateProvider] Error: $e");
      }
    });
  }

  StreamTransformer<Uint8List, List<int>> unit8Transformer =
      StreamTransformer.fromHandlers(
        handleData: (List<int> data, sink) {
          sink.add(data);
        },
      );
}
