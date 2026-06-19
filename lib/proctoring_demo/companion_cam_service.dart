import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class CompanionCamFrame {
  const CompanionCamFrame({
    required this.bytes,
    required this.receivedAt,
    required this.frameNumber,
  });

  final Uint8List bytes;
  final DateTime receivedAt;
  final int frameNumber;
}

class CompanionCamSession {
  const CompanionCamSession({
    required this.pairingUrl,
    required this.host,
    required this.port,
    required this.token,
    required this.expiresAt,
  });

  final String pairingUrl;
  final String host;
  final int port;
  final String token;
  final DateTime expiresAt;
}

class CompanionCamService {
  CompanionCamService({
    required this.studentId,
    required this.examId,
    required this.attemptId,
  });

  final String studentId;
  final String examId;
  final String attemptId;

  final StreamController<CompanionCamFrame> _frames =
      StreamController<CompanionCamFrame>.broadcast();
  final StreamController<bool> _connection = StreamController<bool>.broadcast();

  HttpServer? _server;
  WebSocket? _socket;
  CompanionCamSession? _session;
  int _frameCounter = 0;
  String? _secret;

  Stream<CompanionCamFrame> get frames => _frames.stream;
  Stream<bool> get connectionChanges => _connection.stream;
  CompanionCamSession? get session => _session;
  bool get connected => _socket != null;

  Future<CompanionCamSession> start() async {
    await stop();
    final host = await _localIPv4();
    _secret = _randomToken(32);
    final token = _randomToken(24);
    final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 10));
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0, shared: false);
    _server = server;
    final sig = _sign('$token|$attemptId|${expiresAt.toIso8601String()}');
    final uri = Uri(
      scheme: 'http',
      host: host,
      port: server.port,
      path: '/cam',
      queryParameters: <String, String>{
        'token': token,
        'attempt': attemptId,
        'exp': expiresAt.millisecondsSinceEpoch.toString(),
        'sig': sig,
      },
    );
    _session = CompanionCamSession(
      pairingUrl: uri.toString(),
      host: host,
      port: server.port,
      token: token,
      expiresAt: expiresAt,
    );
    unawaited(_serve(server));
    return _session!;
  }

  Future<void> stop() async {
    await _socket?.close();
    _socket = null;
    await _server?.close(force: true);
    _server = null;
    _session = null;
    _connection.add(false);
  }

  Future<void> dispose() async {
    await stop();
    await _frames.close();
    await _connection.close();
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      try {
        if (request.uri.path == '/cam') {
          if (!_validRequest(request.uri)) {
            request.response.statusCode = HttpStatus.forbidden;
            request.response.write('Invalid or expired companion camera token.');
            await request.response.close();
            continue;
          }
          request.response.headers.contentType = ContentType.html;
          request.response.write(_htmlPage(request.uri));
          await request.response.close();
          continue;
        }

        if (request.uri.path == '/ws') {
          if (!_validRequest(request.uri)) {
            request.response.statusCode = HttpStatus.forbidden;
            await request.response.close();
            continue;
          }
          final socket = await WebSocketTransformer.upgrade(request);
          await _socket?.close();
          _socket = socket;
          _connection.add(true);
          socket.listen(
            (data) {
              if (data is List<int>) {
                _frameCounter++;
                _frames.add(
                  CompanionCamFrame(
                    bytes: Uint8List.fromList(data),
                    receivedAt: DateTime.now(),
                    frameNumber: _frameCounter,
                  ),
                );
              }
            },
            onDone: () {
              _socket = null;
              _connection.add(false);
            },
            onError: (_) {
              _socket = null;
              _connection.add(false);
            },
          );
          continue;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      } catch (_) {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } catch (_) {}
      }
    }
  }

  bool _validRequest(Uri uri) {
    final session = _session;
    if (session == null) return false;
    final token = uri.queryParameters['token'] ?? '';
    final attempt = uri.queryParameters['attempt'] ?? '';
    final expRaw = uri.queryParameters['exp'] ?? '';
    final sig = uri.queryParameters['sig'] ?? '';
    final expMs = int.tryParse(expRaw);
    if (token != session.token || attempt != attemptId || expMs == null) return false;
    if (DateTime.now().toUtc().millisecondsSinceEpoch > expMs) return false;
    final exp = DateTime.fromMillisecondsSinceEpoch(expMs, isUtc: true).toIso8601String();
    return sig == _sign('$token|$attempt|$exp');
  }

  String _sign(String payload) {
    final key = utf8.encode(_secret ?? 'missing-secret');
    final mac = Hmac(sha256, key).convert(utf8.encode(payload));
    return base64Url.encode(mac.bytes).replaceAll('=', '');
  }

  String _randomToken(int length) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Future<String> _localIPv4() async {
    final interfaces = await NetworkInterface.list(
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );
    for (final iface in interfaces) {
      for (final address in iface.addresses) {
        final value = address.address;
        if (!value.startsWith('127.') && !value.startsWith('169.254.')) {
          return value;
        }
      }
    }
    return '127.0.0.1';
  }

  String _htmlPage(Uri uri) {
    final wsUri = Uri(
      scheme: 'ws',
      host: uri.host,
      port: uri.port,
      path: '/ws',
      queryParameters: uri.queryParameters,
    );
    return '''
<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>K-SLAS Companion Camera</title>
<style>
body{font-family:Arial,sans-serif;background:#101828;color:#fff;margin:0;padding:18px}
.card{background:#1d2939;border-radius:18px;padding:18px;max-width:520px;margin:auto}
video{width:100%;border-radius:14px;background:#000;margin-top:12px}
.badge{display:inline-block;padding:8px 12px;border-radius:999px;background:#12b76a;color:#061a10;font-weight:700}
button{padding:12px 18px;border:0;border-radius:10px;font-weight:800;margin-top:12px}
</style>
</head>
<body>
<div class="card">
<div class="badge">Secure local companion camera</div>
<h2>K-SLAS secondary camera</h2>
<p>Place this phone behind or beside you to show your exam environment. Keep this page open until the exam ends.</p>
<video id="video" autoplay playsinline muted></video>
<canvas id="canvas" width="480" height="270" style="display:none"></canvas>
<p id="status">Starting camera...</p>
<button onclick="start()">Restart camera</button>
</div>
<script>
let ws; let stream; let timer; let frame=0;
async function start(){
  document.getElementById('status').innerText='Requesting camera...';
  stream = await navigator.mediaDevices.getUserMedia({video:{facingMode:'environment'}, audio:false});
  const video=document.getElementById('video'); video.srcObject=stream;
  ws = new WebSocket('${wsUri.toString()}'); ws.binaryType='arraybuffer';
  ws.onopen=()=>{document.getElementById('status').innerText='Connected to desktop. Streaming local camera angle.'; pump();};
  ws.onclose=()=>{document.getElementById('status').innerText='Disconnected. Keep phone on same Wi-Fi and restart.'; clearTimeout(timer);};
  ws.onerror=()=>{document.getElementById('status').innerText='Connection error. Check Wi-Fi/firewall.';};
}
function pump(){
  const video=document.getElementById('video'); const canvas=document.getElementById('canvas'); const ctx=canvas.getContext('2d');
  if(ws && ws.readyState===1 && video.videoWidth>0){
    ctx.drawImage(video,0,0,canvas.width,canvas.height);
    canvas.toBlob(blob=>{ if(blob && ws.readyState===1) ws.send(blob); }, 'image/jpeg', 0.62);
    frame++;
  }
  timer=setTimeout(pump, 1000);
}
start().catch(e=>{document.getElementById('status').innerText='Camera failed: '+e;});
</script>
</body>
</html>
''';
  }
}
