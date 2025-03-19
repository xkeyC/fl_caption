import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fl_caption/common/io/http.dart';
import 'package:fl_caption/pages/settings/settings_provider.dart';
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
    if (appSettings.llmProviderUrl.isEmpty || appSettings.llmProviderModel.isEmpty) {
      state = "";
      return;
    }
    if (appSettings.captionLanguage == null) {
      state = "<Not config captionLanguage>";
      return;
    }
    final captionLanguage = captionLanguages[appSettings.captionLanguage!]!;
    final pText = p ?? "";
    final text = n ?? "";
    if (pText == text) return;
    if (text.isEmpty) return;
    _doTranslate(text: text, appSettings: appSettings, captionLanguage: captionLanguage);
  }

  final _asyncLock = Lock();

  Dio? _dio;

  final Map<String, String> _historyMessage = {};

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
        var fixedText = _checkText(text);
        // Set up streaming request
        final workingDur = Duration(seconds: 2);
        final response = await _dio!.post(
          appSettings.llmProviderUrl,
          data: {
            "model": appSettings.llmProviderModel,
            "messages": [
              if (appSettings.llmContextOptimization)
                {
                  "role": "system",
                  "content":
                      "<system>You are an online subtitle translation tool. The input is a streaming response, which may have incoherent beginnings or endings. user will provide historical context in "
                      "<history> \$sourceText -> \$translate </history>, and the main content within <live></live> tags. If there is a possible overlap between the beginning of <live> and <history>, "
                      "please ignore this part (if it is a complete sentence) or complete this part (if it is an incomplete sentence) according to the context. If the end of <live> is fragmented, append `....` to indicate continuation. "
                      "If you encounter a large amount of repeated content, it is most likely a speech recognition error. Please translate it into the form of \$content x \$count."
                      "Translate the user's content to "
                      "${captionLanguage.displayName} (${captionLanguage.code}) "
                      "and output the final translation within <result> tags. "
                      "Example: <result>This is Translated Output</result></system>",
                }
              else
                {
                  "role": "system",
                  "content":
                      "<system>You are an online subtitle translator, translating <live> \$userMessage </live> into "
                      "${captionLanguage.displayName} (${captionLanguage.code}), "
                      "If you encounter a large amount of repeated content, it is most likely a speech recognition error. Please translate it into the form of \$content x \$count."
                      "And out put to result block; eg: <result>This is Translate Output</result>> </system>",
                },
              if (appSettings.llmContextOptimization)
                for (final entry in _historyMessage.entries)
                  {"role": "user", "content": "<history> ${entry.key} -> ${entry.value} </history>"},
              {"role": "user", "content": "<live>$fixedText</live>"},
            ],
            "temperature": appSettings.llmTemperature,
            "stream": true, // Enable streaming
            "max_tokens": appSettings.llmMaxTokens,
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
            .transform(const LineSplitter())
            .timeout(workingDur)) {
          // Split by "data: " for SSE format
          final lines = chunk.split('data: ');
          for (final line in lines) {
            if (line.trim().isEmpty || line.trim() == '[DONE]') continue;
            try {
              final jsonData = jsonDecode(line);
              final content = jsonData['choices']?[0]?['delta']?['content'] as String?;
              if (content != null) {
                partialTranslation += content;
              }
            } catch (e) {
              // Skip invalid JSON chunks
              continue;
            }
          }
        }
        // add text to history
        if (_historyMessage[fixedText] == null) {
          _historyMessage[fixedText] = "";
        }
        // Update the state with the final translation [partialTranslation] eg:<result>This is Translate Output</result>
        final resultRegex = RegExp(r'<result>(.*?)</result>', dotAll: true);
        final match = resultRegex.firstMatch(partialTranslation);
        if (match != null && match.groupCount >= 1) {
          state = match.group(1) ?? "";
          // add text to history
          _historyMessage[fixedText] = state;
        } else {
          state = partialTranslation;
          // add text to history
          _historyMessage[fixedText] = state;
        }
        if (_historyMessage.length > 2) {
          _historyMessage.remove(_historyMessage.keys.first);
        }
        debugPrint("_historyMessage len == ${_historyMessage.length}");
      } catch (e) {
        debugPrint("[TranslateProvider] Error: $e");
      }
    });
  }

  StreamTransformer<Uint8List, List<int>> unit8Transformer = StreamTransformer.fromHandlers(
    handleData: (List<int> data, sink) {
      sink.add(data);
    },
  );

  String _checkText(String text) {
    // 检测存在重复的字符或段落，数字优化，避免挤爆 Llm
    if (text.isEmpty) return text;

    // Check for simple repetitions of the same character
    final chars = text.split('');
    if (chars.length > 10) {
      final charCounts = <String, int>{};
      for (final char in chars) {
        charCounts[char] = (charCounts[char] ?? 0) + 1;
      }

      // If a single character is repeated more than 70% of the text
      final mostRepeatedChar = charCounts.entries.reduce((a, b) => a.value > b.value ? a : b);
      if (mostRepeatedChar.value > chars.length * 0.7) {
        return '${mostRepeatedChar.key} x ${mostRepeatedChar.value}';
      }
    }

    // Check for repeated words or phrases
    final words = text.split(' ');
    if (words.length >= 4) {
      // Look for exact repeated phrases of 2-4 words
      for (int phraseLength = 4; phraseLength >= 2; phraseLength--) {
        if (words.length < phraseLength * 2) continue;

        final phraseMap = <String, int>{};
        for (int i = 0; i <= words.length - phraseLength; i++) {
          final phrase = words.sublist(i, i + phraseLength).join(' ');
          phraseMap[phrase] = (phraseMap[phrase] ?? 0) + 1;
        }

        final mostRepeatedPhrase = phraseMap.entries
            .where((e) => e.value >= 3)
            .fold<MapEntry<String, int>?>(null, (a, b) => (a == null || a.value < b.value) ? b : a);

        if (mostRepeatedPhrase != null && mostRepeatedPhrase.value * phraseLength.toDouble() / words.length > 0.5) {
          return '${mostRepeatedPhrase.key} x ${mostRepeatedPhrase.value}';
        }
      }
    }

    return text;
  }
}
