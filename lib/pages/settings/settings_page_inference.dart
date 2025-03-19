import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'settings_provider.dart';

class SettingsInferencePage extends HookWidget {
  final ValueNotifier<AppSettingsData?> appSettingsData;
  final TextEditingController whisperMaxAudioDurationController;
  final TextEditingController inferenceIntervalController;
  final TextEditingController whisperDefaultMaxDecodeTokensController;
  final TextEditingController whisperTemperatureController;
  final TextEditingController llmTemperatureController;
  final TextEditingController llmMaxTokensController;

  const SettingsInferencePage({
    super.key,
    required this.appSettingsData,
    required this.whisperMaxAudioDurationController,
    required this.inferenceIntervalController,
    required this.whisperDefaultMaxDecodeTokensController,
    required this.whisperTemperatureController,
    required this.llmTemperatureController,
    required this.llmMaxTokensController,
  });

  @override
  Widget build(BuildContext context) {
    if (appSettingsData.value == null) {
      return const Center(child: ProgressRing());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('推理设置', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),

        // Whisper 相关设置
        const Text('Whisper', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),

        _buildSettingRow(
          label: '音频长度 (秒)：',
          tooltip: '音频长度越长推理压力越大 (默认: 12秒)',
          controller: whisperMaxAudioDurationController,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),

        _buildSettingRow(
          label: '推理周期间隔 (秒)：',
          tooltip: '间隔越小延迟越低，但不要超过显卡推理时间 (默认: 2秒)',
          controller: inferenceIntervalController,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),

        _buildSettingRow(
          label: '最大推理Token长度：',
          tooltip: '限制此值可防止whisper进入幻觉循环太久 (默认: 256)',
          controller: whisperDefaultMaxDecodeTokensController,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),

        _buildSettingRow(
          label: 'Whisper温度：',
          tooltip: '较低的值可以使输出更加确定，较高的值输出越有创造性 (0.0-1.0, 默认: 0.0)',
          controller: whisperTemperatureController,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
            _TemperatureTextInputFormatter(),
          ],
        ),

        const SizedBox(height: 24),

        // LLM 相关设置
        const Text('LLM', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),

        _buildSettingRow(
          label: 'LLM温度：',
          tooltip: '较低的值使输出更加确定，较高的值输出越有创造性 (0.0-1.0, 默认: 0.1)',
          controller: llmTemperatureController,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
            _TemperatureTextInputFormatter(),
          ],
        ),

        _buildSettingRow(
          label: 'LLM最大输出Token：',
          tooltip: '限制LLM输出的最大长度 (默认: 256)',
          controller: llmMaxTokensController,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
      ],
    );
  }

  Widget _buildSettingRow({
    required String label,
    required String tooltip,
    required TextEditingController controller,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(width: 180, child: Text(label)),
              Expanded(child: TextFormBox(controller: controller, inputFormatters: inputFormatters)),
            ],
          ),
          SizedBox(height: 4),
          Text(tooltip, style: TextStyle(color: Colors.white.withValues(alpha: .6))),
        ],
      ),
    );
  }
}

class _TemperatureTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) {
      return newValue;
    }
    // 解析浮点值
    double? value = double.tryParse(newValue.text);
    if (value == null) {
      return oldValue;
    }

    // 确保值在0.0到1.0之间
    if (value < 0.0) {
      return const TextEditingValue(text: "0.0");
    } else if (value > 1.0) {
      return const TextEditingValue(text: "1.0");
    }

    return newValue;
  }
}
