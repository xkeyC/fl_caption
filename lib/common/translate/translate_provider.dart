import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_caption/common/io/http.dart';
import 'package:fl_caption/common/settings_provider.dart';
import 'package:fl_caption/common/whisper/provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:synchronized/synchronized.dart';

part 'translate_provider.g.dart';

@riverpod
class TranslateProvider extends _$TranslateProvider {
  @override
  String build() {
    ref.listen(dartWhisperCaptionProvider, (p, n) async {
      _updateTranslate(p ?? AsyncValue.data(""), n);
    });
    return "";
  }

  void _updateTranslate(AsyncValue<String> p, AsyncValue<String> n) async {
    final appSettings = await ref.read(appSettingsProvider.future);
    if (appSettings.llmProviderUrl.isEmpty ||
        appSettings.llmProviderModel.isEmpty) {
      state = "<no config llm>";
      return;
    }
    final pText = p.value ?? "";
    final text = n.value ?? "";
    if (pText == text) return;
    if (text.isEmpty) return;
    _doTranslate(text: text, appSettings: appSettings);
  }

  final _asyncLock = Lock();

  Dio? _dio;

  void _doTranslate({
    required String text,
    required AppSettingsData appSettings,
  }) async {
    await _asyncLock.synchronized(() async {
      // state = "";
      _dio ??= await RDio.createRDioClient();
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
                    r"<system>You are an online subtitle translator, translating user input into Chinese (zh_CN), and do not output subtitle content.</system>",
              },
              {"role": "user", "content": text},
            ],
            "temperature": 0.6,
            "stream": true, // Enable streaming
            "max_tokens": 512,
          },
          options: Options(
            headers: {
              "Authorization": "Bearer ${appSettings.llmProviderKey}",
              "Content-Type": "application/json",
              "Accept": "text/event-stream",
              "Accept-Charset": "utf-8",
            },
            responseType: ResponseType.stream, // Set response type to stream
          ),
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
        state = partialTranslation;
      } catch (e) {
        state = "Error: $e";
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
