import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../src/rust/api/app.dart' as rs_app;
import '../src/rust/api/caption.dart' as rs;
import '../src/rust/api/models.dart' as rs_models;
import 'captions.dart';
import 'i18n.dart';
import 'mobile_protocol.dart';
import 'models.dart';
import 'settings.dart';
import 'windows.dart';

/// The translator as the mobile app names it: `off`, `api` or a local
/// model id.
String translatorChoice(AppSettings s) => !s.translationEnabled
    ? 'off'
    : s.translator == TranslatorKind.api
    ? 'api'
    : s.localTranslator;

AppSettings withTranslatorChoice(AppSettings s, String choice) => switch (choice) {
  'off' => s.copyWith(translationEnabled: false),
  'api' => s.copyWith(translationEnabled: true, translator: TranslatorKind.api),
  _ => s.copyWith(translationEnabled: true, translator: TranslatorKind.local, localTranslator: choice),
};

/// The LAN addresses the phone can reach this computer at (private IPv4
/// first).
Future<List<String>> lanAddresses() async {
  final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
  final addresses = [
    for (final i in interfaces)
      for (final a in i.addresses)
        if (!a.isLoopback && !a.isLinkLocal) a.address,
  ];
  bool private(String a) =>
      a.startsWith('192.168.') || a.startsWith('10.') || RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(a);
  addresses.sort((a, b) => (private(a) ? 0 : 1).compareTo(private(b) ? 0 : 1));
  return addresses;
}

@immutable
class MobileServerState {
  const MobileServerState({
    this.running = false,
    this.port = 0,
    this.client = '',
    this.listening = false,
    this.error = '',
  });

  final bool running;
  final int port;

  /// The connected phone's name (empty: none).
  final String client;

  /// Captions run on the phone's audio.
  final bool listening;
  final String error;

  Map<String, dynamic> toMap() => {
    'running': running,
    'port': port,
    'client': client,
    'listening': listening,
    'error': error,
  };
}

/// The server the mobile app connects to; runs in the caption bar's window,
/// which owns the captions. One phone at a time: a new one replaces it.
class MobileServer extends Notifier<MobileServerState> {
  HttpServer? _server;
  WebSocket? _client;
  String _clientName = '';
  int _lastCaptionId = -1;
  String _lastCaption = '';

  /// Lines up to this id were shown before the phone started captions.
  int _captionFloor = 0;

  @override
  MobileServerState build() {
    ref.listen(settingsProvider, (previous, next) {
      if (previous == null || previous.mobileEnabled != next.mobileEnabled || previous.mobilePort != next.mobilePort) {
        _apply(next);
      }
      if (previous != null &&
          (previous.asrModel != next.asrModel ||
              translatorChoice(previous) != translatorChoice(next) ||
              previous.targetLanguage != next.targetLanguage ||
              previous.asrLanguage != next.asrLanguage)) {
        _send({'t': 'settings', 'settings': _settingsOf(next)});
      }
    });
    ref.listen(captionProvider, (previous, next) => _forward(previous, next));
    ref.onDispose(() => _server?.close(force: true));
    Future.microtask(() => _apply(ref.read(settingsProvider)));
    return const MobileServerState();
  }

  void _publish(MobileServerState next) {
    state = next;
    settingsChannel.invokeMethod('mobile_status', next.toMap()).catchError((_) => null);
  }

  Future<void> _apply(AppSettings s) async {
    if (s.mobileEnabled && (_server == null || _server!.port != s.mobilePort)) {
      await _close();
      try {
        final server = await HttpServer.bind(InternetAddress.anyIPv4, s.mobilePort);
        _server = server;
        server.listen(_onRequest);
        _publish(MobileServerState(running: true, port: server.port));
      } catch (error) {
        _publish(MobileServerState(error: '$error'));
      }
    } else if (!s.mobileEnabled && _server != null) {
      await _close();
      _publish(const MobileServerState());
    }
  }

  Future<void> _close() async {
    await _dropClient();
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _onRequest(HttpRequest request) async {
    if (request.uri.path != MobileProtocol.path || !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    var greeted = false;
    // The first message must be a valid hello, and soon.
    final timeout = Timer(const Duration(seconds: 10), () {
      if (!greeted) socket.close(WebSocketStatus.policyViolation);
    });
    socket.listen(
      (data) async {
        if (data is String) {
          final message = jsonDecode(data) as Map<String, dynamic>;
          if (!greeted) {
            greeted = await _greet(socket, message);
            timeout.cancel();
            if (!greeted) await socket.close(WebSocketStatus.policyViolation);
            return;
          }
          if (identical(socket, _client)) await _onMessage(message);
        } else if (greeted && identical(socket, _client) && data is List<int>) {
          rs.pushMobileAudio(pcm: data is Uint8List ? data : Uint8List.fromList(data));
        }
      },
      onDone: () {
        timeout.cancel();
        if (identical(socket, _client)) _onClientGone();
      },
      onError: (_) {},
      cancelOnError: true,
    );
  }

  Future<bool> _greet(WebSocket socket, Map<String, dynamic> hello) async {
    final s = ref.read(settingsProvider);
    if (hello['t'] != 'hello') return false;
    if ((hello['v'] as int? ?? 0) != MobileProtocol.version) {
      socket.add(jsonEncode({'t': 'denied', 'reason': 'version'}));
      return false;
    }
    if (s.mobilePassword.isNotEmpty && hello['password'] != s.mobilePassword) {
      socket.add(jsonEncode({'t': 'denied', 'reason': 'password'}));
      return false;
    }
    await _dropClient(replaced: true);
    _client = socket;
    _clientName = (hello['name'] as String?)?.trim().isNotEmpty == true ? hello['name'] as String : 'Android';
    socket.add(jsonEncode(await _welcome(s)));
    await ref.read(captionProvider.notifier).setPhone(_clientName);
    _publish(MobileServerState(running: true, port: _server?.port ?? 0, client: _clientName));
    return true;
  }

  Future<Map<String, dynamic>> _welcome(AppSettings s) async {
    final models = await ref.read(modelsProvider.future);
    String nameOf(rs_models.ModelInfo m) => m.name;
    return {
      't': 'welcome',
      'server': 'FL Caption',
      'asr': [
        for (final m in models)
          if (m.kind == rs_models.ModelCategory.asr && m.installed) {'id': m.id, 'name': nameOf(m)},
      ],
      'translators': [
        {'id': 'off', 'name': tr('不翻译', 'Off')},
        for (final m in models)
          if (m.kind == rs_models.ModelCategory.translator && m.installed) {'id': m.id, 'name': nameOf(m)},
        if (s.apiBaseUrl.isNotEmpty) {'id': 'api', 'name': '${tr('云端 API', 'Cloud API')} · ${s.apiModel}'},
      ],
      'languages': [
        for (final l in rs_app.languages()) {'code': l.code, 'name': '${l.native} · ${I18n.zh ? l.zh : l.en}'},
      ],
      'settings': _settingsOf(s),
    };
  }

  Map<String, dynamic> _settingsOf(AppSettings s) => {
    'asr': s.asrModel,
    'translator': translatorChoice(s),
    'target': s.targetLanguage,
    'spoken': s.asrLanguage,
  };

  Future<void> _onMessage(Map<String, dynamic> message) async {
    final captions = ref.read(captionProvider.notifier);
    switch (message['t']) {
      case 'start':
        _lastCaptionId = -1;
        final lines = ref.read(captionProvider).lines;
        _captionFloor = lines.isEmpty ? 0 : lines.last.id;
        await captions.start(remote: _clientName);
        _publish(MobileServerState(running: true, port: _server?.port ?? 0, client: _clientName, listening: true));
      case 'stop':
        if (captions.remote != null) await captions.stop();
        _publish(MobileServerState(running: true, port: _server?.port ?? 0, client: _clientName));
      case 'set':
        // The desktop's settings follow the phone's choice.
        ref.read(settingsProvider.notifier).update((s) {
          var next = s;
          if (message['asr'] is String) next = next.copyWith(asrModel: message['asr'] as String);
          if (message['translator'] is String) next = withTranslatorChoice(next, message['translator'] as String);
          if (message['target'] is String) next = next.copyWith(targetLanguage: message['target'] as String);
          if (message['spoken'] is String) next = next.copyWith(asrLanguage: message['spoken'] as String);
          return next;
        });
        // A phone session applies new models at once (no banner to press).
        if (captions.remote != null && captions.modelsPending) await captions.start();
    }
  }

  Future<void> _onClientGone() async {
    _client = null;
    await ref.read(captionProvider.notifier).setPhone(null);
    _publish(MobileServerState(running: _server != null, port: _server?.port ?? 0));
  }

  /// [replaced]: another phone takes its place (the computer's own
  /// captions stay off).
  Future<void> _dropClient({bool replaced = false}) async {
    final client = _client;
    if (client == null) return;
    _client = null;
    await client.close(WebSocketStatus.goingAway);
    if (!replaced) await ref.read(captionProvider.notifier).setPhone(null);
  }

  void _send(Map<String, dynamic> message) {
    final client = _client;
    if (client == null || client.readyState != WebSocket.open) return;
    client.add(jsonEncode(message));
  }

  /// The phone shows the line being spoken and its translation.
  void _forward(CaptionState? previous, CaptionState next) {
    if (_client == null || ref.read(captionProvider.notifier).remote == null) return;
    if (previous == null || previous.status != next.status || previous.message != next.message) {
      _send({'t': 'status', 'status': next.status.name, 'message': next.message, 'provider': next.provider});
    }
    final line = next.lines.isEmpty ? null : next.lines.last;
    if (line == null || line.id <= _captionFloor) return;
    final shown = '${line.source}\u0000${line.translation}\u0000${line.isFinal}';
    if (line.id == _lastCaptionId && shown == _lastCaption) return;
    _lastCaptionId = line.id;
    _lastCaption = shown;
    _send({
      't': 'caption',
      'id': line.id,
      'source': line.source,
      'translation': line.sameLanguage ? '' : line.translation,
      'final': line.isFinal,
    });
  }
}

final mobileServerProvider = NotifierProvider<MobileServer, MobileServerState>(MobileServer.new);
