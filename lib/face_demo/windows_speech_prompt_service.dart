import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Crash-isolated spoken prompts for the Windows enrollment flow.
///
/// Speech runs outside the Flutter process. A Windows speech-engine failure
/// therefore cannot terminate an exam or the student application.
class WindowsSpeechPromptService {
  Process? _process;
  Future<bool>? _initialization;

  Future<bool> initialize() => _initialization ??= _start();

  Future<bool> _start() async {
    if (!Platform.isWindows) return false;
    const script = r'''
Add-Type -AssemblyName System.Speech
$voice = New-Object System.Speech.Synthesis.SpeechSynthesizer
$voice.Rate = 0
$voice.Volume = 100
[Console]::Out.WriteLine('READY')
while (($line = [Console]::In.ReadLine()) -ne $null) {
  if ($line -eq '__EXIT__') { break }
  $voice.SpeakAsyncCancelAll()
  if ($line -eq '__STOP__') { continue }
  try {
    $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($line))
    $null = $voice.SpeakAsync($text)
  } catch {}
}
$voice.SpeakAsyncCancelAll()
$voice.Dispose()
''';
    try {
      final process = await Process.start('powershell.exe', const <String>[
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-Command',
        script,
      ]);
      _process = process;
      final ready = await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 4));
      return ready == 'READY';
    } catch (_) {
      _process?.kill();
      _process = null;
      return false;
    }
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty || !await initialize()) return;
    final process = _process;
    if (process == null) return;
    process.stdin.writeln(base64Encode(utf8.encode(text)));
    await process.stdin.flush();
  }

  Future<void> stop() async {
    final process = _process;
    if (process == null) return;
    process.stdin.writeln('__STOP__');
    await process.stdin.flush();
  }

  Future<void> dispose() async {
    final process = _process;
    _process = null;
    _initialization = null;
    if (process == null) return;
    try {
      process.stdin.writeln('__EXIT__');
      await process.stdin.flush();
      await process.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {
      process.kill();
    }
  }
}
