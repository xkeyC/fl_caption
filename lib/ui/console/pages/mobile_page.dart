import 'dart:math';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/i18n.dart';
import '../../../app/mobile_protocol.dart';
import '../../../app/mobile_server.dart' show lanAddresses;
import '../../../app/settings.dart';
import '../../../app/windows.dart';
import '../../theme.dart';
import '../../widgets.dart';

/// The mobile server's state as the settings window sees it (pushed by the
/// caption bar's window, which runs the server).
class MobileStatus {
  const MobileStatus({this.running = false, this.port = 0, this.client = '', this.listening = false, this.error = ''});

  final bool running;
  final int port;
  final String client;
  final bool listening;
  final String error;

  factory MobileStatus.fromMap(Map<String, dynamic> m) => MobileStatus(
    running: m['running'] as bool? ?? false,
    port: m['port'] as int? ?? 0,
    client: m['client'] as String? ?? '',
    listening: m['listening'] as bool? ?? false,
    error: m['error'] as String? ?? '',
  );
}

class MobileStatusNotifier extends Notifier<MobileStatus> {
  @override
  MobileStatus build() => const MobileStatus();

  void receive(Map<String, dynamic> map) => state = MobileStatus.fromMap(map);

  Future<void> refresh() async {
    try {
      final map = await mainChannel.invokeMethod<Map>('mobile_status');
      if (map != null) receive(Map<String, dynamic>.from(map));
    } catch (_) {}
  }
}

final mobileStatusProvider = NotifierProvider<MobileStatusNotifier, MobileStatus>(MobileStatusNotifier.new);

final _addressesProvider = FutureProvider.autoDispose<List<String>>((ref) => lanAddresses());

String _newPassword() {
  final random = Random.secure();
  return List.generate(6, (_) => random.nextInt(10)).join();
}

class MobilePage extends HookConsumerWidget {
  const MobilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final update = ref.read(settingsProvider.notifier).update;
    final status = ref.watch(mobileStatusProvider);
    final addresses = ref.watch(_addressesProvider).value ?? const <String>[];
    final chosen = useState<String?>(null);
    useEffect(() {
      ref.read(mobileStatusProvider.notifier).refresh();
      return null;
    }, const []);
    final address = addresses.contains(chosen.value) ? chosen.value! : addresses.firstOrNull;

    return PageScaffold(
      title: tr('移动 App', 'Mobile app'),
      subtitle: tr(
        '手机 App 内录声音，使用这台电脑的算力识别和翻译，在手机上显示双语字幕。手机接入期间电脑暂停自己的录音。手机和电脑需在同一局域网。',
        'The phone app records what it plays, this computer recognizes and translates it, and the phone shows bilingual captions. While a phone is connected, this computer stops recording its own audio. Both must be on the same network.',
      ),
      children: [
        Section(
          title: tr('连接', 'Connection'),
          children: [
            SwitchRow(
              label: tr('允许手机连接', 'Accept phone connections'),
              description: tr(
                '首次开启时 Windows 可能询问是否允许网络访问，请允许“专用网络”',
                'Windows may ask whether to allow network access the first time: allow private networks',
              ),
              value: s.mobileEnabled,
              onChanged: (v) => update(
                (s) =>
                    s.copyWith(mobileEnabled: v, mobilePassword: v && s.mobilePassword.isEmpty ? _newPassword() : null),
              ),
            ),
            SettingRow(
              label: tr('端口', 'Port'),
              child: SizedBox(
                width: 120,
                child: CommitTextField(
                  value: '${s.mobilePort}',
                  onCommit: (v) {
                    final port = int.tryParse(v.trim());
                    if (port != null && port > 1024 && port < 65536) update((s) => s.copyWith(mobilePort: port));
                  },
                ),
              ),
            ),
            SettingRow(
              label: tr('连接密码', 'Password'),
              description: tr('手机首次连接时输入；留空则不需要密码', 'Typed on the phone the first time; empty: none'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 160,
                    child: CommitTextField(
                      value: s.mobilePassword,
                      onCommit: (v) => update((s) => s.copyWith(mobilePassword: v.trim())),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Button(
                    onPressed: () => update((s) => s.copyWith(mobilePassword: _newPassword())),
                    child: Text(tr('重新生成', 'New')),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (s.mobileEnabled)
          Section(
            title: tr('扫码连接', 'Scan to connect'),
            children: [
              if (status.error.isNotEmpty)
                InfoBar(
                  title: Text(tr('服务未能启动', 'The server did not start')),
                  content: Text(status.error),
                  severity: InfoBarSeverity.error,
                  isLong: true,
                )
              else if (address == null)
                Text(tr('未找到局域网地址', 'No LAN address found'), style: TextStyle(color: muted(context)))
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                      child: QrImageView(
                        data: MobileProtocol.pairingUri(address, s.mobilePort),
                        size: 180,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('用 FL Caption 手机 App 扫描二维码', 'Scan the code with the FL Caption phone app'),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          SelectableText('$address:${s.mobilePort}', style: const TextStyle(fontSize: 16)),
                          const SizedBox(height: 12),
                          if (addresses.length > 1)
                            Choice<String>(
                              value: address,
                              items: [for (final a in addresses) (a, a)],
                              onChanged: (v) => chosen.value = v,
                            ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(
                                status.client.isNotEmpty ? FluentIcons.completed_solid : FluentIcons.cell_phone,
                                size: 16,
                                color: status.client.isNotEmpty ? Colors.green.lighter : muted(context),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                status.client.isEmpty
                                    ? tr('等待手机连接', 'Waiting for a phone')
                                    : status.listening
                                    ? tr('${status.client} 已连接，正在识别', '${status.client} connected, captioning')
                                    : tr('${status.client} 已连接', '${status.client} connected'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
      ],
    );
  }
}
