import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fl_caption/common/utils/window_util.dart';
import 'package:fl_caption/pages/settings/settings_page_captions.dart';
import 'package:fl_caption/pages/settings/settings_page_inference.dart';
import 'package:fl_caption/pages/settings/settings_page_llm.dart';
import 'package:fl_caption/pages/settings/settings_page_whisper.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'about_page.dart';
import 'settings_provider.dart';

class SettingsApp extends HookConsumerWidget {
  SettingsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrollController = useScrollController();
    final superSliverListController = useState(ListController());

    final selectedMenuIndex = useState(0);

    final appSettingsData = useState<AppSettingsData?>(null);
    final modelDirController = useTextEditingController();
    final apiUrlController = useTextEditingController();
    final apiKeyController = useTextEditingController();
    final apiModelController = useTextEditingController();

    // 推理设置相关控制器
    final whisperMaxAudioDurationController = useTextEditingController();
    final inferenceIntervalController = useTextEditingController();
    final whisperDefaultMaxDecodeTokensController = useTextEditingController();
    final whisperTemperatureController = useTextEditingController();
    final llmTemperatureController = useTextEditingController();
    final llmMaxTokensController = useTextEditingController();
    final llmPromptPrefixController = useTextEditingController();

    useEffect(() {
      DesktopMultiWindow.setMethodHandler(MultiWindowWindowUtil.windowMethodHandler);
      () async {
        final settings = await MultiWindowWindowUtil.getAppSettingsData();
        modelDirController.text = settings.modelWorkingDir;
        apiUrlController.text = settings.llmProviderUrl;
        apiKeyController.text = settings.llmProviderKey;
        apiModelController.text = settings.llmProviderModel;

        whisperMaxAudioDurationController.text = settings.whisperMaxAudioDuration.toString();
        inferenceIntervalController.text = settings.inferenceInterval.toString();
        whisperDefaultMaxDecodeTokensController.text = settings.whisperDefaultMaxDecodeTokens.toString();
        whisperTemperatureController.text = settings.whisperTemperature.toString();
        llmTemperatureController.text = settings.llmTemperature.toString();
        llmMaxTokensController.text = settings.llmMaxTokens.toString();
        llmPromptPrefixController.text = settings.llmPromptPrefix;

        appSettingsData.value = settings;
      }();
      return () {
        modelDirController.dispose();
        apiUrlController.dispose();
        apiKeyController.dispose();
        apiModelController.dispose();

        // 释放新增的控制器
        whisperMaxAudioDurationController.dispose();
        inferenceIntervalController.dispose();
        whisperDefaultMaxDecodeTokensController.dispose();
        whisperTemperatureController.dispose();
        llmTemperatureController.dispose();
        llmMaxTokensController.dispose();
      };
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
        content: Builder(
          builder: (BuildContext context) {
            if (appSettingsData.value == null) {
              return const Center(child: ProgressRing());
            }
            return Row(
              children: [
                _makeMenus(scrollController, superSliverListController.value, selectedMenuIndex),

                /// Settings Page
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: SuperListView(
                          controller: scrollController,
                          listController: superSliverListController.value,
                          padding: EdgeInsets.only(top: 12, left: 24, right: 16),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: VisibilityDetector(
                                key: Key("menu_base"),
                                onVisibilityChanged: (VisibilityInfo info) => _checkIndex(info, 0, selectedMenuIndex),
                                child: Column(
                                  children: [
                                    SettingsCaptionsPage(appSettingsData: appSettingsData),
                                    SizedBox(height: 12),
                                    SettingsWhisperPage(
                                      appSettingsData: appSettingsData,
                                      modelDirController: modelDirController,
                                    ),
                                    SizedBox(height: 12),
                                    SettingsLlmPage(
                                      apiUrlController: apiUrlController,
                                      apiKeyController: apiKeyController,
                                      apiModelController: apiModelController,
                                      appSettingsData: appSettingsData,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: VisibilityDetector(
                                key: Key("menu_Inference"),
                                onVisibilityChanged: (VisibilityInfo info) => _checkIndex(info, 1, selectedMenuIndex),
                                child: SettingsInferencePage(
                                  appSettingsData: appSettingsData,
                                  whisperMaxAudioDurationController: whisperMaxAudioDurationController,
                                  inferenceIntervalController: inferenceIntervalController,
                                  whisperDefaultMaxDecodeTokensController: whisperDefaultMaxDecodeTokensController,
                                  whisperTemperatureController: whisperTemperatureController,
                                  llmTemperatureController: llmTemperatureController,
                                  llmMaxTokensController: llmMaxTokensController,
                                  llmPromptPrefixController: llmPromptPrefixController,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: VisibilityDetector(
                                key: Key("menu_about"),
                                onVisibilityChanged: (VisibilityInfo info) => _checkIndex(info, 2, selectedMenuIndex),
                                child: const AboutPage(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
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
                                  whisperMaxAudioDuration: int.tryParse(whisperMaxAudioDurationController.text) ?? 12,
                                  inferenceInterval: int.tryParse(inferenceIntervalController.text) ?? 2,
                                  whisperDefaultMaxDecodeTokens:
                                      int.tryParse(whisperDefaultMaxDecodeTokensController.text) ?? 256,
                                  whisperTemperature: double.tryParse(whisperTemperatureController.text) ?? 0.0,
                                  llmTemperature: double.tryParse(llmTemperatureController.text) ?? 0.1,
                                  llmMaxTokens: int.tryParse(llmMaxTokensController.text) ?? 256,
                                  llmPromptPrefix: llmPromptPrefixController.text.trim(),
                                );
                                await MultiWindowWindowUtil.setAppSettingsData(newSettings!);
                                await MultiWindowWindowUtil.closeMineWindow();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _makeMenus(
    ScrollController scrollController,
    ListController listController,
    ValueNotifier<int> selectedMenuIndex,
  ) {
    final menuItems = [
      {'icon': FluentIcons.closed_caption, 'title': "基础设置", 'index': 0},
      {'icon': FontAwesomeIcons.lightbulb, 'title': "推理设置", 'index': 1},
      {'icon': FluentIcons.info, 'title': "关于", 'index': 2},
    ];

    return Container(
      width: 180,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(color: Colors.grey.withValues(alpha: .3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in menuItems) ...[
            _buildMenuItem(
              icon: item['icon'] as IconData,
              title: item['title'] as String,
              onTap: () => _scrollToIndex(item['index'] as int, scrollController, listController, selectedMenuIndex),
              isSelected: selectedMenuIndex.value == item['index'] as int,
            ),
            if (item != menuItems.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    required bool isSelected,
  }) {
    return HoverButton(
      onPressed: onTap,
      builder: (context, states) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color:
                (states.isHovered || isSelected)
                    ? isSelected
                        ? Colors.grey[150]
                        : Colors.grey[180].withValues(alpha: 0.3)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(fontSize: 16)),
            ],
          ),
        );
      },
    );
  }

  void _scrollToIndex(
    int i,
    ScrollController scrollController,
    ListController listController,
    ValueNotifier<int> selectedMenuIndex,
  ) {
    listController.animateToItem(
      index: i,
      scrollController: scrollController,
      alignment: 0,
      duration: (estimatedDistance) => Duration(milliseconds: 250),
      curve: (estimatedDistance) => Curves.easeInOut,
    );
    Future.delayed(const Duration(milliseconds: 300)).then((_) {
      selectedMenuIndex.value = i;
    });
  }

  final Map<int, double> visibleInfo = {};

  void _checkIndex(VisibilityInfo info, int i, ValueNotifier<int> selectedMenuIndex) {
    visibleInfo[i] = info.visibleFraction;
    final sorted = visibleInfo.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    selectedMenuIndex.value = sorted.first.key;
  }
}
