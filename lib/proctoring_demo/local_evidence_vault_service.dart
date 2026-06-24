import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class LocalEvidenceFileRecord {
  const LocalEvidenceFileRecord({
    required this.id,
    required this.studentId,
    required this.examId,
    required this.attemptId,
    required this.eventType,
    required this.fileType,
    required this.filePath,
    required this.sha256Digest,
    required this.sizeBytes,
    required this.createdAt,
    required this.reviewReason,
    required this.metadata,
  });

  final String id;
  final String studentId;
  final String examId;
  final String attemptId;
  final String eventType;
  final String fileType;
  final String filePath;
  final String sha256Digest;
  final int sizeBytes;
  final DateTime createdAt;
  final String reviewReason;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'student_id': studentId,
        'exam_id': examId,
        'attempt_id': attemptId,
        'event_type': eventType,
        'file_type': fileType,
        'file_path': filePath,
        'sha256': sha256Digest,
        'size_bytes': sizeBytes,
        'created_at': createdAt.toUtc().toIso8601String(),
        'review_reason': reviewReason,
        'metadata': metadata,
      };
}

class LocalEvidenceBundle {
  const LocalEvidenceBundle({
    required this.studentId,
    required this.examId,
    required this.attemptId,
    required this.directoryPath,
    required this.records,
    required this.updatedAt,
  });

  final String studentId;
  final String examId;
  final String attemptId;
  final String directoryPath;
  final List<LocalEvidenceFileRecord> records;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'student_id': studentId,
        'exam_id': examId,
        'attempt_id': attemptId,
        'directory_path': directoryPath,
        'records': records.map((record) => record.toJson()).toList(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };
}

class LocalEvidenceVaultService {
  const LocalEvidenceVaultService({String? baseDirectoryPath})
      : _baseDirectoryPath = baseDirectoryPath;

  final String? _baseDirectoryPath;

  Future<LocalEvidenceFileRecord> saveJsonEvidence({
    required String studentId,
    required String examId,
    required String attemptId,
    required String eventType,
    required String reviewReason,
    required Map<String, Object?> payload,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final encoded = const JsonEncoder.withIndent('  ').convert(payload);
    return saveBytesEvidence(
      studentId: studentId,
      examId: examId,
      attemptId: attemptId,
      eventType: eventType,
      fileType: 'json',
      reviewReason: reviewReason,
      bytes: Uint8List.fromList(utf8.encode(encoded)),
      metadata: metadata,
    );
  }

  Future<LocalEvidenceFileRecord> saveTextEvidence({
    required String studentId,
    required String examId,
    required String attemptId,
    required String eventType,
    required String reviewReason,
    required String text,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return saveBytesEvidence(
      studentId: studentId,
      examId: examId,
      attemptId: attemptId,
      eventType: eventType,
      fileType: 'txt',
      reviewReason: reviewReason,
      bytes: Uint8List.fromList(utf8.encode(text)),
      metadata: metadata,
    );
  }

  Future<LocalEvidenceFileRecord> saveBytesEvidence({
    required String studentId,
    required String examId,
    required String attemptId,
    required String eventType,
    required String fileType,
    required String reviewReason,
    required Uint8List bytes,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final now = DateTime.now();
    final directory = await _bundleDirectory(
      studentId: studentId,
      examId: examId,
      attemptId: attemptId,
    );
    await directory.create(recursive: true);

    final safeEvent = _safeName(eventType);
    final extension = _safeName(fileType).isEmpty ? 'bin' : _safeName(fileType);
    final id = '${now.microsecondsSinceEpoch}_$safeEvent';
    final evidenceFile = File('${directory.path}${Platform.pathSeparator}$id.$extension');
    await evidenceFile.writeAsBytes(bytes, flush: true);

    final digest = sha256.convert(bytes).toString();
    final record = LocalEvidenceFileRecord(
      id: id,
      studentId: studentId,
      examId: examId,
      attemptId: attemptId,
      eventType: eventType,
      fileType: extension,
      filePath: evidenceFile.path,
      sha256Digest: digest,
      sizeBytes: bytes.length,
      createdAt: now,
      reviewReason: reviewReason,
      metadata: metadata,
    );

    await _appendRecord(directory: directory, record: record);
    return record;
  }

  Future<LocalEvidenceBundle> readBundle({
    required String studentId,
    required String examId,
    required String attemptId,
  }) async {
    final directory = await _bundleDirectory(
      studentId: studentId,
      examId: examId,
      attemptId: attemptId,
    );
    final manifest = File('${directory.path}${Platform.pathSeparator}manifest.json');
    if (!await manifest.exists()) {
      return LocalEvidenceBundle(
        studentId: studentId,
        examId: examId,
        attemptId: attemptId,
        directoryPath: directory.path,
        records: const <LocalEvidenceFileRecord>[],
        updatedAt: DateTime.now(),
      );
    }

    final json = jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    final recordsJson = json['records'];
    final records = <LocalEvidenceFileRecord>[];
    if (recordsJson is List) {
      for (final item in recordsJson) {
        if (item is Map) records.add(_recordFromJson(Map<String, dynamic>.from(item)));
      }
    }

    return LocalEvidenceBundle(
      studentId: studentId,
      examId: examId,
      attemptId: attemptId,
      directoryPath: directory.path,
      records: records,
      updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()) ?? DateTime.now(),
    );
  }

  Future<void> _appendRecord({
    required Directory directory,
    required LocalEvidenceFileRecord record,
  }) async {
    final manifest = File('${directory.path}${Platform.pathSeparator}manifest.json');
    final records = <Map<String, Object?>>[];
    if (await manifest.exists()) {
      try {
        final decoded = jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
        final existingRecords = decoded['records'];
        if (existingRecords is List) {
          records.addAll(existingRecords.whereType<Map>().map((item) => Map<String, Object?>.from(item)));
        }
      } catch (_) {
        records.clear();
      }
    }

    records.add(record.toJson());
    final bundle = <String, Object?>{
      'student_id': record.studentId,
      'exam_id': record.examId,
      'attempt_id': record.attemptId,
      'directory_path': directory.path,
      'records': records,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await manifest.writeAsString(const JsonEncoder.withIndent('  ').convert(bundle), flush: true);
  }

  LocalEvidenceFileRecord _recordFromJson(Map<String, dynamic> json) {
    return LocalEvidenceFileRecord(
      id: (json['id'] ?? '').toString(),
      studentId: (json['student_id'] ?? '').toString(),
      examId: (json['exam_id'] ?? '').toString(),
      attemptId: (json['attempt_id'] ?? '').toString(),
      eventType: (json['event_type'] ?? '').toString(),
      fileType: (json['file_type'] ?? '').toString(),
      filePath: (json['file_path'] ?? '').toString(),
      sha256Digest: (json['sha256'] ?? '').toString(),
      sizeBytes: int.tryParse((json['size_bytes'] ?? '0').toString()) ?? 0,
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ?? DateTime.now(),
      reviewReason: (json['review_reason'] ?? '').toString(),
      metadata: json['metadata'] is Map
          ? Map<String, Object?>.from(json['metadata'] as Map)
          : const <String, Object?>{},
    );
  }

  Future<Directory> _bundleDirectory({
    required String studentId,
    required String examId,
    required String attemptId,
  }) async {
    final root = _baseDirectoryPath ?? _defaultEvidenceRoot();
    return Directory(
      [
        root,
        _safeName(studentId),
        _safeName(examId),
        _safeName(attemptId),
      ].join(Platform.pathSeparator),
    );
  }

  String _defaultEvidenceRoot() {
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.trim().isNotEmpty) {
        return '$localAppData${Platform.pathSeparator}KSLAS${Platform.pathSeparator}EvidenceVault';
      }
    }
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    return '$home${Platform.pathSeparator}.kslas${Platform.pathSeparator}evidence_vault';
  }

  String _safeName(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
}
