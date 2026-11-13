import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'native_face_embedding_runtime.dart';

/// Encrypted-at-rest storage for biometric data kept on this device: face
/// photos, signed templates, and identity evidence.
///
/// Paths are relative to a private root. Each value is bound to its path and
/// purpose (DPAPI entropy on Windows, AES-GCM associated data on Android), so
/// a file copied to another student's path does not decrypt.
abstract class ProtectedLocalStore {
  Future<bool> write(
    String relativePath,
    String value, {
    required String purpose,
  });

  Future<String?> read(String relativePath, {required String purpose});

  Future<void> delete(String relativePath);

  /// Relative paths of files directly inside [relativeDirectory].
  Future<List<String>> list(String relativeDirectory);
}

/// Private per-app root directory for K-SLAS data on supported platforms.
abstract final class KslasPrivateDirectory {
  static Future<Directory?> resolve(String child) async {
    if (Platform.isWindows) {
      final root = Platform.environment['LOCALAPPDATA'];
      if (root == null || root.isEmpty) return null;
      return Directory(_join(_join(root, 'KSLAS'), child));
    }
    if (Platform.isAndroid) {
      final support = await getApplicationSupportDirectory();
      return Directory(_join(support.path, child));
    }
    return null;
  }

  static String _join(String left, String right) =>
      '$left${Platform.pathSeparator}$right';
}

/// [ProtectedLocalStore] backed by the native face runtime's protected
/// storage (Windows DPAPI / Android Keystore AES-GCM).
class NativeProtectedLocalStore implements ProtectedLocalStore {
  NativeProtectedLocalStore(this.root, {NativeFaceEmbeddingRuntime? runtime})
    : _runtime = runtime ?? NativeFaceEmbeddingRuntime();

  final Directory root;
  final NativeFaceEmbeddingRuntime _runtime;

  @override
  Future<bool> write(
    String relativePath,
    String value, {
    required String purpose,
  }) async {
    final file = File(_absolute(relativePath));
    await file.parent.create(recursive: true);
    return _runtime.storeProtectedString(
      path: file.path,
      value: value,
      entropy: _entropy(relativePath, purpose),
    );
  }

  @override
  Future<String?> read(String relativePath, {required String purpose}) async {
    final file = File(_absolute(relativePath));
    if (!await file.exists()) return null;
    return _runtime.loadProtectedString(
      path: file.path,
      entropy: _entropy(relativePath, purpose),
    );
  }

  @override
  Future<void> delete(String relativePath) async {
    final file = File(_absolute(relativePath));
    if (await file.exists()) await file.delete();
  }

  @override
  Future<List<String>> list(String relativeDirectory) async {
    final directory = Directory(_absolute(relativeDirectory));
    if (!await directory.exists()) return const <String>[];
    final names = <String>[];
    await for (final entity in directory.list()) {
      if (entity is File) {
        names.add('$relativeDirectory/${entity.uri.pathSegments.last}');
      }
    }
    names.sort();
    return names;
  }

  String _absolute(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    if (normalized.split('/').any((part) => part == '..' || part.isEmpty)) {
      throw ArgumentError.value(relativePath, 'relativePath', 'is not safe');
    }
    return '${root.path}${Platform.pathSeparator}'
        '${normalized.replaceAll('/', Platform.pathSeparator)}';
  }

  static String _entropy(String relativePath, String purpose) =>
      'kslas-protected-v1:$purpose:${relativePath.replaceAll('\\', '/')}';
}

/// In-memory store for tests and unsupported platforms. Nothing is written to
/// disk, so nothing outlives the process.
class InMemoryProtectedLocalStore implements ProtectedLocalStore {
  final Map<String, String> _values = <String, String>{};
  final Map<String, String> _purposes = <String, String>{};

  @override
  Future<bool> write(
    String relativePath,
    String value, {
    required String purpose,
  }) async {
    _values[relativePath] = value;
    _purposes[relativePath] = purpose;
    return true;
  }

  @override
  Future<String?> read(String relativePath, {required String purpose}) async {
    if (_purposes[relativePath] != purpose) return null;
    return _values[relativePath];
  }

  @override
  Future<void> delete(String relativePath) async {
    _values.remove(relativePath);
    _purposes.remove(relativePath);
  }

  @override
  Future<List<String>> list(String relativeDirectory) async {
    final prefix = '$relativeDirectory/';
    return _values.keys
        .where(
          (key) =>
              key.startsWith(prefix) &&
              !key.substring(prefix.length).contains('/'),
        )
        .toList()
      ..sort();
  }
}
