import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fl_caption/common/dialog_utils.dart';
import 'package:fl_caption/common/utils/window_util.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'common/settings_provider.dart';
import 'common/whisper/language.dart';
import 'common/whisper/models.dart';
import 'dialogs/model_download_dialog.dart';
import 'dialogs/model_download_provider.dart';

class SettingsApp extends HookConsumerWidget {
  const SettingsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appSettingsData = useState<AppSettingsData?>(null);
    final modelDirController = useTextEditingController();
    final apiUrlController = useTextEditingController();
    final apiKeyController = useTextEditingController();
    final apiModelController = useTextEditingController();

    useEffect(() {
      DesktopMultiWindow.setMethodHandler(
        MultiWindowWindowUtil.windowMethodHandler,
      );
      () async {
        final settings = await MultiWindowWindowUtil.getAppSettingsData();
        modelDirController.text = settings.modelWorkingDir;
        apiUrlController.text = settings.llmProviderUrl;
        apiKeyController.text = settings.llmProviderKey;
        apiModelController.text = settings.llmProviderModel;
        appSettingsData.value = settings;
      }();
      return null;
    }, const []);

    return FluentApp(
      debugShowCheckedModeBanner: false,
      title: '设置',
      theme: FluentThemeData(
        brightness: Brightness.dark,
        fontFamily: "SourceHanSansCN-Regular",
        scaffoldBackgroundColor: Colors.black.withValues(alpha: 0.6),
      ),
      home: ScaffoldPage(
        header: const PageHeader(title: Text('FL Caption 设置')),
        content: _buildContent(
          appSettingsData: appSettingsData,
          modelDirController: modelDirController,
          apiUrlController: apiUrlController,
          apiKeyController: apiKeyController,
          apiModelController: apiModelController,
          ref: ref,
        ),
      ),
    );
  }

  Widget _buildContent({
    required ValueNotifier<AppSettingsData?> appSettingsData,
    required TextEditingController modelDirController,
    required TextEditingController apiUrlController,
    required TextEditingController apiKeyController,
    required TextEditingController apiModelController,
    required WidgetRef ref,
  }) {
    if (appSettingsData.value == null) {
      return const Center(child: ProgressRing());
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSubtitleSettingsSection(appSettingsData),
            const SizedBox(height: 32),
            _buildWhisperSection(
              appSettingsData: appSettingsData,
              modelDirController: modelDirController,
              ref: ref,
            ),
            const SizedBox(height: 32),
            _buildLlmProviderSection(
              apiUrlController: apiUrlController,
              apiKeyController: apiKeyController,
              apiModelController: apiModelController,
            ),
            const SizedBox(height: 32),
            _buildSaveButton(
              appSettingsData: appSettingsData,
              modelDirController: modelDirController,
              apiUrlController: apiUrlController,
              apiKeyController: apiKeyController,
              apiModelController: apiModelController,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubtitleSettingsSection(
    ValueNotifier<AppSettingsData?> appSettingsData,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "字幕设置",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InfoLabel(label: "音频语言:"),
                  ComboBox<String?>(
                    placeholder: const Text('自动检测'),
                    isExpanded: true,
                    value: appSettingsData.value?.audioLanguage,
                    items: [
                      const ComboBoxItem<String?>(
                        value: null,
                        child: Text('自动检测'),
                      ),
                      ...whisperLanguages.entries.map(
                        (e) => ComboBoxItem<String?>(
                          value: e.key,
                          child: Text(
                            "${e.value.displayLocaleName} (${e.value.displayName})",
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      appSettingsData.value = appSettingsData.value?.copyWith(
                        audioLanguage: value,
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InfoLabel(label: "字幕语言:"),
                  ComboBox<String?>(
                    placeholder: const Text('无字幕'),
                    isExpanded: true,
                    value: appSettingsData.value?.captionLanguage,
                    items: [
                      const ComboBoxItem<String?>(
                        value: null,
                        child: Text('无字幕'),
                      ),
                      ...whisperLanguages.entries.map(
                        (e) => ComboBoxItem<String?>(
                          value: e.key,
                          child: Text(
                            "${e.value.displayLocaleName} (${e.value.displayName})",
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      appSettingsData.value = appSettingsData.value?.copyWith(
                        captionLanguage: value,
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWhisperSection({
    required ValueNotifier<AppSettingsData?> appSettingsData,
    required TextEditingController modelDirController,
    required WidgetRef ref,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Whisper",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            // Model folder settings section
            Flexible(
              flex: 3,
              child: _buildModelFolderSection(modelDirController),
            ),
            const SizedBox(width: 16),
            // Model selection section
            Flexible(
              flex: 1,
              child: _buildModelSelectionSection(
                appSettingsData,
                ref,
                modelDirController,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // CUDA toggle
        ToggleSwitch(
          checked: appSettingsData.value?.tryWithCuda ?? true,
          onChanged: (value) {
            appSettingsData.value = appSettingsData.value?.copyWith(
              tryWithCuda: value,
            );
          },
          content: const Text("启用 CUDA 加速 (需要 NVIDIA 显卡)"),
        ),
      ],
    );
  }

  Widget _buildModelFolderSection(TextEditingController modelDirController) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoLabel(label: "模型文件夹路径："),
        Row(
          children: [
            Expanded(
              child: TextBox(
                controller: modelDirController,
                placeholder: "请选择模型文件夹路径",
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(FluentIcons.folder_search),
              onPressed: () {},
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModelSelectionSection(
    ValueNotifier<AppSettingsData?> appSettingsData,
    WidgetRef ref,
    TextEditingController modelDirController,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoLabel(label: "语音识别模型："),
        Row(
          children: [
            Expanded(
              child: ComboBox<String>(
                placeholder: const Text('选择模型'),
                isExpanded: true,
                value: appSettingsData.value?.whisperModel,
                items:
                    whisperModels.keys
                        .map(
                          (model) => ComboBoxItem<String>(
                            value: model,
                            child: Text(model),
                          ),
                        )
                        .toList(),
                onChanged: (value) {
                  if (value != null) {
                    appSettingsData.value = appSettingsData.value?.copyWith(
                      whisperModel: value,
                    );
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            _buildModelDownloadButton(appSettingsData, ref, modelDirController),
          ],
        ),
      ],
    );
  }

  Widget _buildModelDownloadButton(
    ValueNotifier<AppSettingsData?> appSettingsData,
    WidgetRef ref,
    TextEditingController modelDirController,
  ) {
    return Consumer(
      builder: (BuildContext context, WidgetRef ref, Widget? child) {
        final modelState = ref.watch(
          modelDownloadStateProvider(
            appSettingsData.value?.whisperModel ?? "",
            modelDirController.text,
          ),
        );
        if (modelState.isReady) {
          return Icon(FluentIcons.check_mark);
        }
        return IconButton(
          icon: const Icon(FluentIcons.download),
          onPressed: () async {
            final modelName = appSettingsData.value!.whisperModel;
            final modelData = whisperModels[modelName];
            final ok = await showConfirmDialogs(
              context,
              "确认开始下载模型 $modelName？",
              Text("这将占用大约 ${modelData?.size} 空间"),
            );
            if (ok) {
              if (!context.mounted) return;
              final downloadOK = await showDialog(
                context: context,
                builder: (BuildContext context) {
                  return ModelDownloadDialog(
                    model: modelData!,
                    savePath: modelDirController.text,
                  );
                },
              );
              if (downloadOK != true) {
                if (!context.mounted) return;
                showToast(context, "下载失败：${modelState.errorText}");
              }
            }
          },
        );
      },
    );
  }

  Widget _buildLlmProviderSection({
    required TextEditingController apiUrlController,
    required TextEditingController apiKeyController,
    required TextEditingController apiModelController,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "LLM",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        InfoLabel(label: "API 调用地址"),
        TextBox(
          controller: apiUrlController,
          placeholder: "例如：http://localhost:11434/v1/chat/completions",
        ),
        const SizedBox(height: 16),
        InfoLabel(label: "API 密钥"),
        TextBox(
          controller: apiKeyController,
          placeholder: "请输入 API 密钥 (Ollam 默认为空)",
          obscureText: true,
        ),
        const SizedBox(height: 16),
        InfoLabel(label: "模型名称"),
        TextBox(controller: apiModelController, placeholder: "例如：qwen2.5:32b"),
      ],
    );
  }

  Widget _buildSaveButton({
    required ValueNotifier<AppSettingsData?> appSettingsData,
    required TextEditingController modelDirController,
    required TextEditingController apiUrlController,
    required TextEditingController apiKeyController,
    required TextEditingController apiModelController,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FilledButton(
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4, horizontal: 12),
            child: Text("保存设置"),
          ),
          onPressed: () async {
            final newSettings = appSettingsData.value?.copyWith(
              modelWorkingDir: modelDirController.text,
              llmProviderUrl: apiUrlController.text,
              llmProviderKey: apiKeyController.text,
              llmProviderModel: apiModelController.text,
              whisperModel: appSettingsData.value!.whisperModel,
            );
            await MultiWindowWindowUtil.setAppSettingsData(newSettings!);
            await MultiWindowWindowUtil.closeMineWindow();
          },
        ),
      ],
    );
  }
}
