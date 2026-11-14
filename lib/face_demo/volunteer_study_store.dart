import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'protected_local_store.dart';
import 'volunteer_study_consent.dart';

/// The exam-photo sessions of the volunteer study
/// (`docs/identity/volunteer_calibration_protocol.md`).
///
/// Each session is exactly [photosPerSession] photos named `a1.jpg`..`a3.jpg`
/// and so on: `ai_runtime/face_identity_calibration.py` groups a device's
/// photos in threes, in file-name order, to simulate the pre-exam
/// "two of three" check.
enum StudySession {
  a(
    'a',
    'Session A: normal light',
    'Normal room light. The volunteer looks at the screen as when writing an '
        'exam.',
  ),
  b(
    'b',
    'Session B: harder light',
    'A dim room, or a window or lamp behind the volunteer.',
  ),
  c(
    'c',
    'Session C: another day',
    'On a different day from registration. If the volunteer wears glasses or '
        'a headscarf, change it (on or off) for this session.',
  );

  const StudySession(this.code, this.title, this.instruction);

  final String code;
  final String title;
  final String instruction;

  static const int photosPerSession = 3;

  List<String> get fileNames => <String>[
    for (var i = 1; i <= photosPerSession; i++) '$code$i.jpg',
  ];

  static StudySession? fromCode(String code) {
    for (final session in values) {
      if (session.code == code) return session;
    }
    return null;
  }
}

/// Study codes and device labels. Names are never stored: a volunteer is
/// only ever `v001`, `v002`, ...
abstract final class VolunteerStudy {
  static const String schema = 'kslas.volunteer_study.v1';

  /// Registration needs at least this many photos (the calibration tool's
  /// `MIN_REFERENCES`).
  static const int minRegistrationPhotos = 5;

  static final RegExp _code = RegExp(r'^v\d{3,4}$');
  static final RegExp _deviceLabel = RegExp(
    r'^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$',
  );

  /// `v001`-style code, or null if [input] is not one.
  static String? normalizeCode(String input) {
    final code = input.trim().toLowerCase();
    return _code.hasMatch(code) ? code : null;
  }

  /// Folder-safe device label, for example `laptop-dell-3520`.
  static String sanitizeDeviceLabel(String input) {
    final cleaned = input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
  }

  static bool isValidDeviceLabel(String label) => _deviceLabel.hasMatch(label);
}

class StudyRegistrationPhoto {
  const StudyRegistrationPhoto({
    required this.poseCode,
    required this.jpegBytes,
    required this.qualityScore,
  });

  final String poseCode;
  final Uint8List jpegBytes;
  final double qualityScore;
}

class StudySessionRecord {
  const StudySessionRecord({
    required this.capturedAt,
    required this.attempts,
    required this.rejected,
  });

  factory StudySessionRecord.fromJson(Map<String, Object?> json) =>
      StudySessionRecord(
        capturedAt: DateTime.parse(json['captured_at']! as String),
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        rejected: (json['rejected'] as num?)?.toInt() ?? 0,
      );

  final DateTime capturedAt;

  /// Photos taken, including ones the app's quality check rejected.
  final int attempts;
  final int rejected;

  Map<String, Object?> toJson() => <String, Object?>{
    'captured_at': capturedAt.toIso8601String(),
    'attempts': attempts,
    'rejected': rejected,
  };
}

class StudyRegistrationRecord {
  const StudyRegistrationRecord({
    required this.deviceLabel,
    required this.capturedAt,
    required this.quality,
  });

  factory StudyRegistrationRecord.fromJson(Map<String, Object?> json) =>
      StudyRegistrationRecord(
        deviceLabel: json['device']! as String,
        capturedAt: DateTime.parse(json['captured_at']! as String),
        quality: <String, double>{
          for (final entry in (json['quality'] as Map? ?? const {}).entries)
            entry.key.toString(): (entry.value as num).toDouble(),
        },
      );

  final String deviceLabel;
  final DateTime capturedAt;

  /// Quality score per pose code; the keys are the photos kept.
  final Map<String, double> quality;

  List<String> get poses => quality.keys.toList()..sort();

  Map<String, Object?> toJson() => <String, Object?>{
    'device': deviceLabel,
    'captured_at': capturedAt.toIso8601String(),
    'quality': quality,
  };
}

/// What this device holds for one volunteer. No names or other personal
/// details: only the study code, the consent record and capture metadata.
class VolunteerStudyRecord {
  const VolunteerStudyRecord({
    required this.code,
    required this.consentVersion,
    required this.consentConfirmedAt,
    required this.consentDeviceLabel,
    this.spoofTestConsent = false,
    this.registration,
    this.sessions = const <String, Map<String, StudySessionRecord>>{},
  });

  factory VolunteerStudyRecord.fromJson(Map<String, Object?> json) {
    final sessions = <String, Map<String, StudySessionRecord>>{};
    for (final device in (json['sessions'] as Map? ?? const {}).entries) {
      sessions[device.key.toString()] = <String, StudySessionRecord>{
        for (final session in (device.value as Map).entries)
          session.key.toString(): StudySessionRecord.fromJson(
            Map<String, Object?>.from(session.value as Map),
          ),
      };
    }
    final registration = json['registration'];
    return VolunteerStudyRecord(
      code: json['code']! as String,
      consentVersion: json['consent_version']! as String,
      consentConfirmedAt: DateTime.parse(
        json['consent_confirmed_at']! as String,
      ),
      consentDeviceLabel: json['consent_device']?.toString() ?? '',
      spoofTestConsent: json['spoof_test_consent'] == true,
      registration: registration is Map
          ? StudyRegistrationRecord.fromJson(
              Map<String, Object?>.from(registration),
            )
          : null,
      sessions: sessions,
    );
  }

  final String code;
  final String consentVersion;
  final DateTime consentConfirmedAt;
  final String consentDeviceLabel;

  /// Optional part of the consent: printed-photo and phone-video tries.
  final bool spoofTestConsent;
  final StudyRegistrationRecord? registration;

  /// Device label -> session code -> record.
  final Map<String, Map<String, StudySessionRecord>> sessions;

  bool hasSession(String deviceLabel, StudySession session) =>
      sessions[deviceLabel]?.containsKey(session.code) ?? false;

  int get sessionCount =>
      sessions.values.fold(0, (sum, device) => sum + device.length);

  VolunteerStudyRecord copyWith({
    StudyRegistrationRecord? registration,
    Map<String, Map<String, StudySessionRecord>>? sessions,
  }) => VolunteerStudyRecord(
    code: code,
    consentVersion: consentVersion,
    consentConfirmedAt: consentConfirmedAt,
    consentDeviceLabel: consentDeviceLabel,
    spoofTestConsent: spoofTestConsent,
    registration: registration ?? this.registration,
    sessions: sessions ?? this.sessions,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': VolunteerStudy.schema,
    'code': code,
    'consent_version': consentVersion,
    'consent_confirmed_at': consentConfirmedAt.toIso8601String(),
    'consent_device': consentDeviceLabel,
    'spoof_test_consent': spoofTestConsent,
    if (registration != null) 'registration': registration!.toJson(),
    'sessions': <String, Object?>{
      for (final device in sessions.entries)
        device.key: <String, Object?>{
          for (final session in device.value.entries)
            session.key: session.value.toJson(),
        },
    },
  };
}

class VolunteerStudyExport {
  const VolunteerStudyExport({
    required this.folder,
    required this.volunteers,
    required this.photos,
  });

  final Directory folder;
  final int volunteers;
  final int photos;
}

/// Thrown when a study action is not allowed (no consent, bad code, ...).
class VolunteerStudyException implements Exception {
  const VolunteerStudyException(this.message);

  final String message;

  @override
  String toString() => 'VolunteerStudyException: $message';
}

/// Volunteer-study photos on this device, encrypted at rest with the native
/// protected store (DPAPI, Android Keystore, iOS Keychain).
///
/// Layout inside the store:
///
///     index.json
///     v001/manifest.json
///     v001/registration/front_face.jpg.sealed
///     v001/probes/<device>/a1.jpg.sealed
///
/// [exportTo] writes plain JPEGs in the layout the calibration tool reads.
class VolunteerStudyStore {
  VolunteerStudyStore(this._store, {DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc());

  /// The store on this device, or null where protected storage is not
  /// available.
  static Future<VolunteerStudyStore?> openOnDevice() async {
    final root = await KslasPrivateDirectory.resolve('volunteer_study');
    if (root == null) return null;
    return VolunteerStudyStore(NativeProtectedLocalStore(root));
  }

  final ProtectedLocalStore _store;
  final DateTime Function() _clock;

  static const String _indexPath = 'index.json';
  static const String _indexPurpose = 'volunteer_study_index';
  static const String _manifestPurpose = 'volunteer_study_manifest';
  static const String _photoPurpose = 'volunteer_study_photo';
  static const String _sealedSuffix = '.sealed';

  static String _manifestPath(String code) => '$code/manifest.json';
  static String _registrationFolder(String code) => '$code/registration';
  static String _probeFolder(String code, String device) =>
      '$code/probes/$device';

  Future<Map<String, Object?>> _index() async {
    final raw = await _store.read(_indexPath, purpose: _indexPurpose);
    if (raw == null) return <String, Object?>{'volunteers': <String>[]};
    return Map<String, Object?>.from(jsonDecode(raw) as Map);
  }

  Future<void> _writeIndex(Map<String, Object?> index) async {
    if (!await _store.write(
      _indexPath,
      jsonEncode(index),
      purpose: _indexPurpose,
    )) {
      throw const VolunteerStudyException(
        'The study index could not be saved.',
      );
    }
  }

  Future<List<String>> volunteerCodes() async {
    final index = await _index();
    return (index['volunteers'] as List? ?? const [])
        .map((code) => code.toString())
        .toList()
      ..sort();
  }

  Future<String?> lastDeviceLabel() async =>
      (await _index())['last_device_label']?.toString();

  Future<void> rememberDeviceLabel(String label) async {
    if (!VolunteerStudy.isValidDeviceLabel(label)) {
      throw const VolunteerStudyException(
        'Use a device label like laptop-dell-3520.',
      );
    }
    final index = await _index();
    index['last_device_label'] = label;
    await _writeIndex(index);
  }

  Future<VolunteerStudyRecord?> volunteer(String code) async {
    final raw = await _store.read(
      _manifestPath(code),
      purpose: _manifestPurpose,
    );
    if (raw == null) return null;
    return VolunteerStudyRecord.fromJson(
      Map<String, Object?>.from(jsonDecode(raw) as Map),
    );
  }

  Future<void> _saveRecord(VolunteerStudyRecord record) async {
    if (!await _store.write(
      _manifestPath(record.code),
      jsonEncode(record.toJson()),
      purpose: _manifestPurpose,
    )) {
      throw const VolunteerStudyException(
        'The volunteer record could not be saved.',
      );
    }
  }

  /// Adds a volunteer after staff confirm the signed consent form. An
  /// existing volunteer is returned unchanged.
  Future<VolunteerStudyRecord> enrol({
    required String code,
    required String deviceLabel,
    required bool consentConfirmed,
    bool spoofTestConsent = false,
  }) async {
    final normalized = VolunteerStudy.normalizeCode(code);
    if (normalized == null) {
      throw const VolunteerStudyException(
        'Use a study code like v001, never a name.',
      );
    }
    if (!consentConfirmed) {
      throw const VolunteerStudyException(
        'Confirm the volunteer signed the consent form first.',
      );
    }
    final existing = await volunteer(normalized);
    if (existing != null) return existing;
    final record = VolunteerStudyRecord(
      code: normalized,
      consentVersion: VolunteerStudyConsent.version,
      consentConfirmedAt: _clock(),
      consentDeviceLabel: deviceLabel,
      spoofTestConsent: spoofTestConsent,
    );
    await _saveRecord(record);
    final index = await _index();
    final codes =
        (index['volunteers'] as List? ?? const [])
            .map((item) => item.toString())
            .toSet()
          ..add(normalized);
    index['volunteers'] = codes.toList()..sort();
    await _writeIndex(index);
    return record;
  }

  Future<VolunteerStudyRecord> _require(String code) async {
    final record = await volunteer(code);
    if (record == null) {
      throw VolunteerStudyException('$code has not been added with consent.');
    }
    return record;
  }

  Future<void> _writePhoto(String path, Uint8List jpeg) async {
    if (!await _store.write(
      '$path$_sealedSuffix',
      base64Encode(jpeg),
      purpose: _photoPurpose,
    )) {
      throw const VolunteerStudyException('A photo could not be saved.');
    }
  }

  Future<void> _clearFolder(String folder) async {
    for (final path in await _store.list(folder)) {
      await _store.delete(path);
    }
  }

  /// Stores the guided registration photos. Register each volunteer once,
  /// on one device; doing it again on this device replaces the photos.
  Future<VolunteerStudyRecord> saveRegistration(
    String code, {
    required String deviceLabel,
    required List<StudyRegistrationPhoto> photos,
  }) async {
    final record = await _require(code);
    final poses = photos.map((photo) => photo.poseCode).toSet();
    if (poses.length != photos.length ||
        photos.length < VolunteerStudy.minRegistrationPhotos) {
      throw const VolunteerStudyException(
        'Registration needs the guided photos, one per pose.',
      );
    }
    final folder = _registrationFolder(record.code);
    await _clearFolder(folder);
    for (final photo in photos) {
      await _writePhoto('$folder/${photo.poseCode}.jpg', photo.jpegBytes);
    }
    final updated = record.copyWith(
      registration: StudyRegistrationRecord(
        deviceLabel: deviceLabel,
        capturedAt: _clock(),
        quality: <String, double>{
          for (final photo in photos) photo.poseCode: photo.qualityScore,
        },
      ),
    );
    await _saveRecord(updated);
    return updated;
  }

  /// Stores one session's three exam photos taken on [deviceLabel],
  /// replacing an earlier capture of the same session on that device.
  Future<VolunteerStudyRecord> saveSession(
    String code, {
    required String deviceLabel,
    required StudySession session,
    required List<Uint8List> photos,
    required int attempts,
    required int rejected,
  }) async {
    if (!VolunteerStudy.isValidDeviceLabel(deviceLabel)) {
      throw const VolunteerStudyException('Set this device\'s label first.');
    }
    if (photos.length != StudySession.photosPerSession) {
      throw const VolunteerStudyException(
        'A session needs exactly ${StudySession.photosPerSession} photos.',
      );
    }
    final record = await _require(code);
    final folder = _probeFolder(record.code, deviceLabel);
    for (var i = 0; i < photos.length; i++) {
      await _writePhoto('$folder/${session.fileNames[i]}', photos[i]);
    }
    final sessions = <String, Map<String, StudySessionRecord>>{
      for (final entry in record.sessions.entries)
        entry.key: Map<String, StudySessionRecord>.of(entry.value),
    };
    (sessions[deviceLabel] ??=
        <String, StudySessionRecord>{})[session.code] = StudySessionRecord(
      capturedAt: _clock(),
      attempts: attempts,
      rejected: rejected,
    );
    final updated = record.copyWith(sessions: sessions);
    await _saveRecord(updated);
    return updated;
  }

  /// Writes every volunteer's photos as plain JPEGs into [folder], in the
  /// calibration tool's layout, plus `capture_log_<device>.json` (codes,
  /// consent versions, dates and quality counts; no names, no photos).
  ///
  /// Exports from several devices are merged by copying their contents into
  /// one study folder; their paths never collide.
  Future<VolunteerStudyExport> exportTo(
    Directory folder, {
    required String deviceLabel,
  }) async {
    var photos = 0;
    final log = <String, Object?>{
      'schema': VolunteerStudy.schema,
      'exported_at': _clock().toIso8601String(),
      'exported_from': deviceLabel,
      'volunteers': <String, Object?>{},
    };
    final codes = await volunteerCodes();
    for (final code in codes) {
      final record = await volunteer(code);
      if (record == null) continue;
      (log['volunteers']! as Map<String, Object?>)[code] = record.toJson();
      final folders = <String, String>{
        _registrationFolder(code): 'registration',
        for (final device in record.sessions.keys)
          _probeFolder(code, device): 'probes/$device',
      };
      for (final entry in folders.entries) {
        for (final path in await _store.list(entry.key)) {
          if (!path.endsWith(_sealedSuffix)) continue;
          final value = await _store.read(path, purpose: _photoPurpose);
          if (value == null) continue;
          final name = path
              .substring(path.lastIndexOf('/') + 1)
              .replaceAll(_sealedSuffix, '');
          final target = File(
            _join(folder.path, <String>[code, ...entry.value.split('/'), name]),
          );
          await target.parent.create(recursive: true);
          await target.writeAsBytes(base64Decode(value), flush: true);
          photos++;
        }
      }
    }
    await folder.create(recursive: true);
    await File(
      _join(folder.path, <String>['capture_log_$deviceLabel.json']),
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(log));
    return VolunteerStudyExport(
      folder: folder,
      volunteers: codes.length,
      photos: photos,
    );
  }

  /// Removes everything held for [code] on this device (for example when a
  /// volunteer withdraws).
  Future<void> deleteVolunteer(String code) async {
    final record = await volunteer(code);
    final folders = <String>[
      _registrationFolder(code),
      for (final device in record?.sessions.keys ?? const <String>[])
        _probeFolder(code, device),
    ];
    for (final folder in folders) {
      await _clearFolder(folder);
    }
    await _store.delete(_manifestPath(code));
    final index = await _index();
    index['volunteers'] = (index['volunteers'] as List? ?? const [])
        .map((item) => item.toString())
        .where((item) => item != code)
        .toList();
    await _writeIndex(index);
  }

  /// Removes every volunteer's photos and records from this device.
  Future<void> deleteAll() async {
    for (final code in await volunteerCodes()) {
      await deleteVolunteer(code);
    }
  }

  static String _join(String root, List<String> parts) =>
      <String>[root, ...parts].join(Platform.pathSeparator);
}
