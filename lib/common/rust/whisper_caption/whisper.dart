// This file is automatically generated, so please do not edit it.
// @generated by `flutter_rust_bridge`@ 2.10.0.

// ignore_for_file: invalid_use_of_internal_member, unused_import, unnecessary_import

import '../frb_generated.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

class DecodingResult {
  final Uint32List tokens;
  final String text;
  final double avgLogprob;
  final double noSpeechProb;
  final double temperature;
  final double compressionRatio;

  const DecodingResult({
    required this.tokens,
    required this.text,
    required this.avgLogprob,
    required this.noSpeechProb,
    required this.temperature,
    required this.compressionRatio,
  });

  @override
  int get hashCode =>
      tokens.hashCode ^
      text.hashCode ^
      avgLogprob.hashCode ^
      noSpeechProb.hashCode ^
      temperature.hashCode ^
      compressionRatio.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DecodingResult &&
          runtimeType == other.runtimeType &&
          tokens == other.tokens &&
          text == other.text &&
          avgLogprob == other.avgLogprob &&
          noSpeechProb == other.noSpeechProb &&
          temperature == other.temperature &&
          compressionRatio == other.compressionRatio;
}

class Segment {
  final double start;
  final double duration;
  final DecodingResult dr;
  final BigInt? reasoningDuration;
  final String? reasoningLang;
  final BigInt? audioDuration;
  final WhisperStatus status;

  const Segment({
    required this.start,
    required this.duration,
    required this.dr,
    this.reasoningDuration,
    this.reasoningLang,
    this.audioDuration,
    required this.status,
  });

  @override
  int get hashCode =>
      start.hashCode ^
      duration.hashCode ^
      dr.hashCode ^
      reasoningDuration.hashCode ^
      reasoningLang.hashCode ^
      audioDuration.hashCode ^
      status.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Segment &&
          runtimeType == other.runtimeType &&
          start == other.start &&
          duration == other.duration &&
          dr == other.dr &&
          reasoningDuration == other.reasoningDuration &&
          reasoningLang == other.reasoningLang &&
          audioDuration == other.audioDuration &&
          status == other.status;
}

enum WhisperStatus { loading, ready, error, working, exit }
