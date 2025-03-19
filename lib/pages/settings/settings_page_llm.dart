import 'package:fl_caption/pages/settings/settings_provider.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SettingsLlmPage extends HookConsumerWidget {
  final TextEditingController apiUrlController;
  final TextEditingController apiKeyController;
  final TextEditingController apiModelController;
  final ValueNotifier<AppSettingsData?> appSettingsData;

  const SettingsLlmPage({
    super.key,
    required this.appSettingsData,
    required this.apiUrlController,
    required this.apiKeyController,
    required this.apiModelController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("LLM", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        InfoLabel(label: "API 调用地址"),
        TextBox(
          controller: apiUrlController,
          placeholder: "输入完整 completions URL ，例如：http://localhost:11434/v1/chat/completions",
        ),
        const SizedBox(height: 16),
        InfoLabel(label: "API 密钥"),
        TextBox(controller: apiKeyController, placeholder: "请输入 API 密钥 (Ollam 默认为空)", obscureText: true),
        const SizedBox(height: 16),
        InfoLabel(label: "模型名称"),
        TextBox(controller: apiModelController, placeholder: "例如：phi4:14b"),
        const SizedBox(height: 16),
        // llm_context_optimization
        ToggleSwitch(
          checked: appSettingsData.value?.llmContextOptimization ?? true,
          onChanged: (value) {
            appSettingsData.value = appSettingsData.value?.copyWith(llmContextOptimization: value);
          },
          content: const Text("启用上下文优化（使用更多 token）"),
        ),
      ],
    );
  }
}
