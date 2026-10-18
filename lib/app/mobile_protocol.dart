/// The link between the desktop app and the mobile app.
///
/// One WebSocket at `ws://<host>:<port>/fl_caption`. Text frames are JSON
/// objects with a type `t`; binary frames are the phone's microphone audio,
/// 16 kHz mono 16-bit little-endian PCM, sent while captions run.
///
/// - phone → desktop: `hello` {v, name, password}, `start`, `stop`,
///   `set` {asr?, translator?, target?, spoken?}
/// - desktop → phone: `welcome` {server, asr: [{id, name}], translators:
///   [{id, name}], languages: [{code, name}], settings}, `denied` {reason:
///   password | version}, `settings` {settings}, `status` {status, message,
///   provider}, `caption` {id, source, translation, final}, `error` {message}
///
/// `settings` is {asr, translator, target, spoken}: the speech model id,
/// the translator (`off`, `api` or a local model id), the target language
/// and the spoken language (empty: detected).
abstract final class MobileProtocol {
  static const path = '/fl_caption';
  static const version = 1;
  static const sampleRate = 16000;
  static const defaultPort = 47720;

  /// What the desktop's QR code holds (no password: that is typed once).
  static String pairingUri(String host, int port) => 'flcaption://$host:$port';

  /// Host and port of a pairing URI (or a plain `host:port`).
  static (String, int)? parsePairing(String text) {
    var rest = text.trim();
    if (rest.startsWith('flcaption://')) rest = rest.substring('flcaption://'.length);
    rest = rest.split('/').first;
    final colon = rest.lastIndexOf(':');
    if (colon <= 0) return rest.isEmpty ? null : (rest, defaultPort);
    final port = int.tryParse(rest.substring(colon + 1));
    if (port == null || port <= 0 || port > 65535) return null;
    return (rest.substring(0, colon), port);
  }
}
