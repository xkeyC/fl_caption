import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../app/i18n.dart';
import '../app/mobile_protocol.dart';

enum Link { idle, connecting, connected, denied, failed }

/// What the phone captions: its microphone, or what its apps play.
enum AudioInput { microphone, system }

/// System audio capture (Android 10+), in MainActivity / PlaybackCaptureService.
const _playback = MethodChannel('fl_caption/playback');
const _playbackAudio = EventChannel('fl_caption/playback_audio');

/// The floating caption window (CaptionOverlay.kt).
const _overlay = MethodChannel('fl_caption/overlay');

@immutable
class Option {
  const Option(this.id, this.name);

  final String id;
  final String name;
}

@immutable
class MobileState {
  const MobileState({
    this.link = Link.idle,
    this.error = '',
    this.host = '',
    this.port = MobileProtocol.defaultPort,
    this.password = '',
    this.asr = const [],
    this.translators = const [],
    this.languages = const [],
    this.settings = const {},
    this.captioning = false,
    this.status = '',
    this.source = '',
    this.translation = '',
    this.overlay = false,
    this.input = AudioInput.microphone,
    this.lines = const [],
    this.overlayHistory = 1,
    this.overlayFontSize = 19,
    this.autoConnect = true,
  });

  final Link link;
  final String error;
  final String host;
  final int port;
  final String password;
  final List<Option> asr;
  final List<Option> translators;
  final List<Option> languages;

  /// asr, translator, target, spoken (see MobileProtocol).
  final Map<String, String> settings;

  /// The microphone is streaming to the computer.
  final bool captioning;

  /// The computer's caption status: idle, loading, running, failed.
  final String status;
  final String source;
  final String translation;
  final bool overlay;
  final AudioInput input;

  /// The last lines, oldest first: (id, source, translation).
  final List<(int, String, String)> lines;

  /// Earlier lines the floating window shows above the current one.
  final int overlayHistory;

  /// The floating window's translation size in sp (the source is 0.75 of it).
  final double overlayFontSize;

  /// Connect to the saved computer when the app opens.
  final bool autoConnect;

  MobileState copyWith({
    Link? link,
    String? error,
    String? host,
    int? port,
    String? password,
    List<Option>? asr,
    List<Option>? translators,
    List<Option>? languages,
    Map<String, String>? settings,
    bool? captioning,
    String? status,
    String? source,
    String? translation,
    bool? overlay,
    AudioInput? input,
    List<(int, String, String)>? lines,
    int? overlayHistory,
    double? overlayFontSize,
    bool? autoConnect,
  }) => MobileState(
    link: link ?? this.link,
    error: error ?? this.error,
    host: host ?? this.host,
    port: port ?? this.port,
    password: password ?? this.password,
    asr: asr ?? this.asr,
    translators: translators ?? this.translators,
    languages: languages ?? this.languages,
    settings: settings ?? this.settings,
    captioning: captioning ?? this.captioning,
    status: status ?? this.status,
    source: source ?? this.source,
    translation: translation ?? this.translation,
    overlay: overlay ?? this.overlay,
    input: input ?? this.input,
    lines: lines ?? this.lines,
    overlayHistory: overlayHistory ?? this.overlayHistory,
    overlayFontSize: overlayFontSize ?? this.overlayFontSize,
    autoConnect: autoConnect ?? this.autoConnect,
  );
}

/// The phone side of the link: connects to the desktop, streams the
/// microphone while captions run, shows what comes back.
class MobileClient extends Notifier<MobileState> {
  WebSocketChannel? _channel;
  StreamSubscription? _messages;
  final _recorder = AudioRecorder();
  StreamSubscription<dynamic>? _audio;
  Timer? _welcomeTimer;

  @override
  MobileState build() {
    // Closed with its ✕.
    _overlay.setMethodCallHandler((call) async {
      if (call.method == 'closed') state = state.copyWith(overlay: false);
    });
    ref.onDispose(() {
      _audio?.cancel();
      _recorder.dispose();
      _messages?.cancel();
      _channel?.sink.close();
    });
    _restore();
    return const MobileState();
  }

  Future<void> _restore() async {
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (error) {
      debugPrint('no saved computer: $error');
      return;
    }
    state = state.copyWith(
      host: prefs.getString('host') ?? '',
      port: prefs.getInt('port') ?? MobileProtocol.defaultPort,
      password: prefs.getString('password') ?? '',
      input: prefs.getString('input') == 'system' ? AudioInput.system : AudioInput.microphone,
      overlayHistory: prefs.getInt('overlayHistory') ?? 1,
      overlayFontSize: prefs.getDouble('overlayFontSize') ?? 19,
      autoConnect: prefs.getBool('autoConnect') ?? true,
    );
    if (state.autoConnect && state.host.isNotEmpty && state.link == Link.idle) {
      await connect(state.host, state.port, state.password);
    }
  }

  Future<void> _save(Future<bool> Function(SharedPreferences prefs) write) async {
    try {
      await write(await SharedPreferences.getInstance());
    } catch (error) {
      debugPrint('could not save a setting: $error');
    }
  }

  Future<void> setAutoConnect(bool on) async {
    state = state.copyWith(autoConnect: on);
    await _save((p) => p.setBool('autoConnect', on));
  }

  /// The floating window's layout: earlier lines and text size.
  Future<void> setOverlayLayout({int? history, double? fontSize}) async {
    state = state.copyWith(overlayHistory: history, overlayFontSize: fontSize);
    await _save((p) => p.setInt('overlayHistory', state.overlayHistory));
    await _save((p) => p.setDouble('overlayFontSize', state.overlayFontSize));
    await _configureOverlay();
    if (state.overlay) await _sendOverlay();
  }

  Future<void> _configureOverlay() =>
      _overlay.invokeMethod('configure', {'history': state.overlayHistory, 'fontSize': state.overlayFontSize});

  /// The earlier lines and the current one.
  Future<void> _sendOverlay() => _overlay.invokeMethod('update', {
    'lines': [
      for (final (_, source, translation) in state.lines) {'source': source, 'translation': translation},
    ],
  });

  Future<void> setInput(AudioInput input) async {
    if (state.captioning) await stopCaptions();
    state = state.copyWith(input: input);
    await _save((p) => p.setString('input', input.name));
  }

  Future<void> connect(String host, int port, String password) async {
    await disconnect();
    state = state.copyWith(link: Link.connecting, error: '', host: host, port: port, password: password);
    try {
      final channel = WebSocketChannel.connect(Uri.parse('ws://$host:$port${MobileProtocol.path}'));
      await channel.ready.timeout(const Duration(seconds: 6));
      _channel = channel;
      _messages = channel.stream.listen(
        (data) async {
          if (data is! String) return;
          try {
            await _onMessage(jsonDecode(data) as Map<String, dynamic>);
          } catch (error) {
            state = state.copyWith(
              link: state.link == Link.connecting ? Link.failed : state.link,
              error: '${tr('处理电脑消息时出错', 'Could not handle a message from the computer')}: $error',
            );
          }
        },
        onDone: () => _onClosed(),
        onError: (_) => _onClosed(),
      );
      channel.sink.add(
        jsonEncode({'t': 'hello', 'v': MobileProtocol.version, 'name': 'Android', 'password': password}),
      );
      _welcomeTimer?.cancel();
      _welcomeTimer = Timer(const Duration(seconds: 10), () {
        if (state.link != Link.connecting) return;
        disconnect();
        state = state.copyWith(link: Link.failed, error: tr('电脑没有响应', 'The computer did not answer'));
      });
    } catch (error) {
      state = state.copyWith(link: Link.failed, error: '$error');
    }
  }

  Future<void> disconnect() async {
    await stopCaptions(notify: false);
    await _messages?.cancel();
    _messages = null;
    await _channel?.sink.close();
    _channel = null;
    if (state.link == Link.connected) state = state.copyWith(link: Link.idle);
  }

  void _send(Map<String, dynamic> message) => _channel?.sink.add(jsonEncode(message));

  Future<void> _onMessage(Map<String, dynamic> m) async {
    List<Option> options(String key, String id) => [
      for (final o in (m[key] as List? ?? const []).cast<Map>()) Option(o[id] as String, o['name'] as String),
    ];
    switch (m['t']) {
      case 'welcome':
        _welcomeTimer?.cancel();
        state = state.copyWith(
          link: Link.connected,
          error: '',
          asr: options('asr', 'id'),
          translators: options('translators', 'id'),
          languages: options('languages', 'code'),
          settings: Map<String, String>.from(m['settings'] as Map),
        );
        // Remembered for the next start (a failure here must not stop the session).
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('host', state.host);
          await prefs.setInt('port', state.port);
          await prefs.setString('password', state.password);
        } catch (error) {
          debugPrint('could not remember the computer: $error');
        }
      case 'denied':
        _welcomeTimer?.cancel();
        state = state.copyWith(
          link: Link.denied,
          error: m['reason'] == 'password'
              ? tr('密码不正确', 'Wrong password')
              : tr('电脑端版本不同，请更新', 'The desktop app is a different version: update it'),
        );
      case 'settings':
        state = state.copyWith(settings: Map<String, String>.from(m['settings'] as Map));
      case 'status':
        state = state.copyWith(
          status: m['status'] as String? ?? '',
          error: m['status'] == 'failed' ? '${m['message']}' : '',
        );
      case 'caption':
        final id = m['id'] as int? ?? 0;
        final line = (id, m['source'] as String? ?? '', m['translation'] as String? ?? '');
        final lines = [...state.lines];
        final at = lines.indexWhere((l) => l.$1 == id);
        if (at >= 0) {
          lines[at] = line;
        } else {
          lines.add(line);
          if (lines.length > 4) lines.removeRange(0, lines.length - 4);
        }
        state = state.copyWith(source: line.$2, translation: line.$3, lines: lines);
        if (state.overlay) await _sendOverlay();
      case 'error':
        state = state.copyWith(error: m['message'] as String? ?? '');
    }
  }

  void _onClosed() {
    _audio?.cancel();
    _audio = null;
    _recorder.stop();
    FlutterForegroundTask.stopService();
    _playback.invokeMethod('stop');
    if (state.link == Link.connected || state.link == Link.connecting) {
      state = state.copyWith(
        link: Link.failed,
        captioning: false,
        error: tr('与电脑的连接已断开', 'The connection to the computer closed'),
      );
    }
  }

  /// Streams the microphone or the system audio to the computer, which
  /// starts captions on it.
  Future<void> startCaptions() async {
    if (state.link != Link.connected || state.captioning) return;
    // Playback capture needs the record-audio permission too.
    if (!await _recorder.hasPermission()) {
      state = state.copyWith(error: tr('需要麦克风权限', 'Microphone permission is needed'));
      return;
    }
    if (state.input == AudioInput.system) return _startSystemAudio();
    // Recording keeps going in the background only from a microphone
    // foreground service.
    if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    await FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.microphone],
      notificationTitle: 'FL Caption',
      notificationText: tr('正在把麦克风声音发给电脑识别', 'Sending the microphone to the computer for captions'),
    );
    _send({'t': 'start'});
    final stream = await _recorder.startStream(
      const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: MobileProtocol.sampleRate, numChannels: 1),
    );
    _audio = stream.listen((chunk) => _channel?.sink.add(chunk));
    state = state.copyWith(captioning: true, error: '', source: '', translation: '', lines: const []);
  }

  /// What other apps play: asks for the screen capture consent (the system
  /// dialog), then the native service streams 16 kHz PCM.
  Future<void> _startSystemAudio() async {
    if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    _audio = _playbackAudio.receiveBroadcastStream().listen(
      (chunk) => _channel?.sink.add(chunk as Uint8List),
      onError: (Object error) {
        state = state.copyWith(error: error is PlatformException ? (error.message ?? '$error') : '$error');
        stopCaptions();
      },
    );
    bool started;
    try {
      started = await _playback.invokeMethod<bool>('start') ?? false;
    } on PlatformException catch (error) {
      started = false;
      state = state.copyWith(error: error.message ?? '$error');
    }
    if (!started) {
      await _audio?.cancel();
      _audio = null;
      if (state.error.isEmpty) {
        state = state.copyWith(error: tr('未获得录制系统声音的授权', 'System audio capture was not allowed'));
      }
      return;
    }
    _send({'t': 'start'});
    state = state.copyWith(captioning: true, error: '', source: '', translation: '', lines: const []);
  }

  Future<void> stopCaptions({bool notify = true}) async {
    await _audio?.cancel();
    _audio = null;
    await _playback.invokeMethod('stop');
    if (await _recorder.isRecording()) await _recorder.stop();
    if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
    if (state.captioning && notify) _send({'t': 'stop'});
    state = state.copyWith(captioning: false);
  }

  /// Picks a model or language; the computer applies it (its settings
  /// follow).
  void choose(String key, String value) {
    _send({'t': 'set', key: value});
    state = state.copyWith(settings: {...state.settings, key: value});
  }

  Future<void> toggleOverlay() async {
    try {
      if (state.overlay) {
        await _overlay.invokeMethod('hide');
        state = state.copyWith(overlay: false);
        return;
      }
      if (await _overlay.invokeMethod<bool>('allowed') != true) {
        // Opens the system page; the user comes back and taps again.
        await _overlay.invokeMethod('requestPermission');
        state = state.copyWith(
          error: tr('请允许“显示在其他应用上层”，然后再点一次悬浮窗', 'Allow “display over other apps”, then tap Floating again'),
        );
        return;
      }
      await _configureOverlay();
      if (await _overlay.invokeMethod<bool>('show') == true) {
        state = state.copyWith(overlay: true, error: '');
        await _sendOverlay();
      }
    } catch (error) {
      state = state.copyWith(error: '${tr('悬浮窗打开失败', 'The floating window failed')}: $error');
    }
  }
}

final mobileClientProvider = NotifierProvider<MobileClient, MobileState>(MobileClient.new);
