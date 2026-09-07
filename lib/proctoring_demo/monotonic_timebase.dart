/// Process-local monotonic timebase shared by live proctoring producers.
///
/// The Edge AI event contract aligns evidence by monotonic capture time rather
/// than wall-clock time. Dart's [Stopwatch] is monotonic, so it is safe from
/// wall-clock corrections while the exam client is running.
///
/// `nowNs` is represented in nanoseconds for the language-neutral event
/// contract. The underlying Dart clock is microsecond-resolution on platforms
/// where `Stopwatch.elapsedMicroseconds` is the available precision, so the
/// final three digits may be zero. Ordering and duration semantics remain
/// monotonic.
class MonotonicTimebase {
  MonotonicTimebase._() : _stopwatch = Stopwatch()..start();

  static final MonotonicTimebase instance = MonotonicTimebase._();

  final Stopwatch _stopwatch;

  int get nowNs => _stopwatch.elapsedMicroseconds * 1000;
}
