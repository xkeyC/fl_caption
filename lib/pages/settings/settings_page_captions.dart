import 'package:fl_caption/common/whisper/language.dart';
import 'package:fl_caption/pages/settings/settings_provider.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SettingsCaptionsPage extends HookConsumerWidget {
  final ValueNotifier<AppSettingsData?> appSettingsData;

  const SettingsCaptionsPage({required this.appSettingsData, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("字幕设置", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                      const ComboBoxItem<String?>(value: null, child: Text('自动检测')),
                      ...whisperLanguages.entries.map(
                        (e) => ComboBoxItem<String?>(
                          value: e.key,
                          child: Text("${e.value.displayLocaleName} (${e.value.displayName})"),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      appSettingsData.value = appSettingsData.value?.copyWith(audioLanguage: value);
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
                      const ComboBoxItem<String?>(value: null, child: Text('无字幕')),
                      ...captionLanguages.entries.map(
                        (e) => ComboBoxItem<String?>(
                          value: e.key,
                          child: Text("${e.value.displayLocaleName} (${e.value.displayName})"),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      appSettingsData.value = appSettingsData.value?.copyWith(captionLanguage: value);
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
}
