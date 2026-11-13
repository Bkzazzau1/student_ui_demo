import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../exam_demo/continuous_identity_policy.dart';
import 'face_embedding_pipeline.dart';
import 'face_identity_verification_service.dart';
import 'identity_evidence.dart';
import 'official_identity_session.dart';

/// Turns one encoded camera frame into a 1:1 outcome. Abstracted so the
/// in-exam schedule and policy can be tested without camera or models.
abstract class InExamFrameEvaluator {
  Future<FaceIdentityCheckOutcome> evaluate(
    Uint8List encodedFrame,
    OfficialFaceTemplateContext template,
  );
}

class PipelineFrameEvaluator implements InExamFrameEvaluator {
  PipelineFrameEvaluator({
    FaceEmbeddingPipeline? pipeline,
    this.verification = const FaceIdentityVerificationService(),
  }) : _pipeline = pipeline ?? FaceEmbeddingPipeline();

  final FaceEmbeddingPipeline _pipeline;
  final FaceIdentityVerificationService verification;

  @override
  Future<FaceIdentityCheckOutcome> evaluate(
    Uint8List encodedFrame,
    OfficialFaceTemplateContext template,
  ) async {
    final available = await _pipeline.initialize();
    final sample = available
        ? await _pipeline.processEncodedImage(encodedFrame)
        : null;
    return verification.evaluateSample(
      aiAvailable: available,
      sample: sample,
      pipelineFailureReason: _pipeline.lastFailureReason,
      template: template,
    );
  }
}

/// Silent, unannounced identity checks during an exam.
///
/// The exam monitor already has camera frames (a live stream on Android, one
/// still per second on Windows). At random times this checker takes a few of
/// those frames, matches them 1:1 against the official template on the
/// device, records the result as evidence, and asks the exam to pause when
/// the policy says so. Nothing is shown to the student while it runs.
class InExamIdentityChecker {
  InExamIdentityChecker({
    required this.studentId,
    required this.examId,
    required this.attemptId,
    required this.onPauseForRecheck,
    InExamFrameEvaluator? evaluator,
    FaceIdentityVerificationService? verification,
    ContinuousIdentityPolicy? policy,
    IdentityCheckScheduler? scheduler,
    Future<OfficialFaceTemplateContext?> Function()? templateLoader,
    Future<IdentityEvidenceOutbox?> Function()? outbox,
    DateTime Function()? clock,
    this.framesPerCheck = 3,
    this.frameGap = const Duration(milliseconds: 700),
    this.collectTimeout = const Duration(seconds: 8),
  }) : _verification = verification ?? const FaceIdentityVerificationService(),
       _policy = policy ?? ContinuousIdentityPolicy(),
       _scheduler = scheduler ?? IdentityCheckScheduler(),
       _clock = clock ?? DateTime.now {
    _evaluator =
        evaluator ?? PipelineFrameEvaluator(verification: _verification);
    _templateLoader = templateLoader ?? _defaultTemplate;
    _outbox = outbox ?? _defaultOutbox;
    _nextCheckAt = _clock().add(_scheduler.first());
  }

  final String studentId;
  final String examId;
  final String attemptId;
  final void Function() onPauseForRecheck;
  final int framesPerCheck;
  final Duration frameGap;
  final Duration collectTimeout;

  final FaceIdentityVerificationService _verification;
  final ContinuousIdentityPolicy _policy;
  final IdentityCheckScheduler _scheduler;
  final DateTime Function() _clock;
  late final InExamFrameEvaluator _evaluator;
  late final Future<OfficialFaceTemplateContext?> Function() _templateLoader;
  late final Future<IdentityEvidenceOutbox?> Function() _outbox;

  final List<Uint8List> _frames = <Uint8List>[];
  late DateTime _nextCheckAt;
  DateTime? _collectingSince;
  DateTime? _lastFrameAt;
  Timer? _timeout;
  bool _evaluating = false;
  bool _followUp = false;
  bool _stopped = false;

  DateTime get nextCheckAt => _nextCheckAt;
  bool get stopped => _stopped;
  ContinuousIdentityPolicy get policy => _policy;

  /// Whether the monitor should hand over its current frame. Cheap; call it
  /// on every frame before doing any conversion work.
  bool get wantsFrame {
    if (_stopped || _evaluating) return false;
    final now = _clock();
    final collectingSince = _collectingSince;
    if (collectingSince == null) return !now.isBefore(_nextCheckAt);
    final last = _lastFrameAt;
    return last == null || now.difference(last) >= frameGap;
  }

  /// Offers the current frame. [encode] runs only if the frame is wanted.
  void offerFrame(Uint8List? Function() encode) {
    if (!wantsFrame) return;
    final encoded = encode();
    if (encoded == null || encoded.isEmpty) return;
    final now = _clock();
    if (_collectingSince == null) {
      _collectingSince = now;
      _timeout?.cancel();
      _timeout = Timer(collectTimeout, () => unawaited(_evaluate()));
    }
    _lastFrameAt = now;
    _frames.add(encoded);
    if (_frames.length >= framesPerCheck) unawaited(_evaluate());
  }

  void dispose() {
    _stopped = true;
    _timeout?.cancel();
    _frames.clear();
  }

  Future<void> _evaluate() async {
    if (_evaluating || _stopped || _frames.isEmpty) return;
    _evaluating = true;
    _timeout?.cancel();
    final frames = List<Uint8List>.of(_frames);
    _frames.clear();
    _collectingSince = null;
    _lastFrameAt = null;
    final kind = _followUp
        ? IdentityCheckKind.inExamFollowUp
        : IdentityCheckKind.inExamRandom;
    try {
      final template = await _templateLoader();
      if (_stopped) return;
      final FaceIdentityCheckOutcome outcome;
      if (template == null) {
        outcome = FaceIdentityCheckOutcome.aiUnavailable(
          'The official Face ID is not loaded on this device.',
        );
      } else if (_hasRepeatedFrame(frames)) {
        // Real cameras never produce byte-identical frames seconds apart;
        // a frozen or injected feed does.
        outcome = FaceIdentityCheckOutcome.livenessFailed(
          'The camera picture did not change between checks.',
        );
      } else {
        final outcomes = <FaceIdentityCheckOutcome>[];
        for (final frame in frames) {
          outcomes.add(await _evaluator.evaluate(frame, template));
          if (_stopped) return;
        }
        outcome = _verification.evaluateConsensus(
          outcomes: outcomes,
          requiredMatches: frames.length >= 2 ? 2 : 1,
        );
      }
      final decision = outcome.verified
          ? PassiveIdentityDecision.verified
          : outcome.countsAsFailure
          ? PassiveIdentityDecision.mismatch
          : PassiveIdentityDecision.inconclusive;
      final snapshot = _policy.record(decision);
      await _record(kind, outcome, frames, template, snapshot);
      if (_stopped) return;
      if (snapshot.requiresExplicitCheck) {
        _stopped = true;
        onPauseForRecheck();
        return;
      }
      _followUp = snapshot.action == IdentityMonitorAction.followUpSoon;
      _nextCheckAt = _clock().add(_scheduler.after(snapshot.action));
    } catch (_) {
      // A runtime failure is inconclusive; try again at the next random time.
      _nextCheckAt = _clock().add(_scheduler.after(IdentityMonitorAction.none));
    } finally {
      _evaluating = false;
    }
  }

  Future<void> _record(
    IdentityCheckKind kind,
    FaceIdentityCheckOutcome outcome,
    List<Uint8List> frames,
    OfficialFaceTemplateContext? template,
    PassiveIdentitySnapshot snapshot,
  ) async {
    try {
      final outbox = await _outbox();
      if (outbox == null) return;
      await outbox.record(
        IdentityEvidenceDraft(
          kind: kind,
          studentId: studentId,
          examId: examId,
          attemptId: attemptId,
          outcome: outcome,
          samplesAttempted: frames.length,
          template: template,
          reviewPhotoJpeg: frames.first,
          policy: <String, Object?>{
            'match_threshold': _verification.matchThreshold,
            'min_signal_quality': _verification.minSignalQuality,
            'consecutive_mismatches': snapshot.mismatchOccasions,
            'inconclusive_streak': snapshot.inconclusiveStreak,
            'action': snapshot.action.name,
          },
        ),
      );
      final school = await SchoolIdentityServices.instance.school();
      unawaited(outbox.flush(school).catchError((Object _) => 0));
    } catch (_) {
      // Evidence storage must never change the identity decision.
    }
  }

  Future<OfficialFaceTemplateContext?> _defaultTemplate() async {
    final session = OfficialIdentitySession.instance;
    return session.activeFor(studentId) ??
        await session.restoreCached(studentId);
  }

  static Future<IdentityEvidenceOutbox?> _defaultOutbox() async {
    try {
      return await SchoolIdentityServices.instance.outbox();
    } catch (_) {
      return null;
    }
  }

  static bool _hasRepeatedFrame(List<Uint8List> frames) {
    if (frames.length < 2) return false;
    final digests = frames.map((frame) => sha256.convert(frame).toString());
    return digests.toSet().length < frames.length;
  }
}
