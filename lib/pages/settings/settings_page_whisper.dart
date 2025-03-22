import 'package:fl_caption/common/dialog_utils.dart';
import 'package:fl_caption/common/whisper/models.dart';
import 'package:fl_caption/dialogs/model_download_dialog.dart';
import 'package:fl_caption/dialogs/model_download_provider.dart';
import 'package:fl_caption/pages/settings/settings_provider.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SettingsWhisperPage extends HookConsumerWidget {
  final ValueNotifier<AppSettingsData?> appSettingsData;
  final TextEditingController modelDirController;

  const SettingsWhisperPage({super.key, required this.appSettingsData, required this.modelDirController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Whisper", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Row(
          children: [
            // Model folder settings section
            Flexible(flex: 3, child: _buildModelFolderSection(modelDirController)),
            const SizedBox(width: 16),
            // Model selection section
            Flexible(flex: 1, child: _buildModelSelectionSection(appSettingsData, ref, modelDirController)),
          ],
        ),
        const SizedBox(height: 16),
        // CUDA toggle
        ToggleSwitch(
          checked: appSettingsData.value?.tryWithCuda ?? true,
          onChanged: (value) {
            appSettingsData.value = appSettingsData.value?.copyWith(tryWithCuda: value);
          },
          content: const Text("启用 CUDA 加速 (需要 NVIDIA 显卡)"),
        ),
        const SizedBox(height: 16),
        ToggleSwitch(
          checked: appSettingsData.value?.withVAD ?? true,
          onChanged: (value) {
            appSettingsData.value = appSettingsData.value?.copyWith(withVAD: value);
          },
          content: const Text("使用 VAD 模型过滤音频 (减少非文字音频产生的幻觉，增加些许推理时间)"),
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
            Expanded(child: TextBox(controller: modelDirController, placeholder: "请选择模型文件夹路径")),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(FluentIcons.folder_search),
              onPressed: () async {
                // TODO pick folder use main window
                // final path = await FilePicker.platform.getDirectoryPath(
                //   lockParentWindow: true,
                //   initialDirectory: modelDirController.text.trim(),
                //   dialogTitle: "请选择文件夹路径",
                // );
                // if (path != null) {
                //   modelDirController.text = path;
                // }
              },
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
                    whisperModels.keys.map((model) => ComboBoxItem<String>(value: model, child: Text(model))).toList(),
                onChanged: (value) {
                  if (value != null) {
                    appSettingsData.value = appSettingsData.value?.copyWith(whisperModel: value);
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
          modelDownloadStateProvider(appSettingsData.value?.whisperModel ?? "", modelDirController.text),
        );
        if (modelState.isReady) {
          return Icon(FluentIcons.check_mark);
        }
        return IconButton(
          icon: const Icon(FluentIcons.download),
          onPressed: () async {
            final modelName = appSettingsData.value!.whisperModel;
            final modelData = whisperModels[modelName];
            final ok = await showConfirmDialogs(context, "确认开始下载模型 $modelName？", Text("这将占用大约 ${modelData?.size} 空间"));
            if (ok) {
              if (!context.mounted) return;
              final downloadOK = await showDialog(
                context: context,
                builder: (BuildContext context) {
                  return ModelDownloadDialog(model: modelData!, savePath: modelDirController.text);
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
}
