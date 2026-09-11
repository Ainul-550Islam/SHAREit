import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/saved_transfer.dart';
import '../models/transfer_models.dart';

class TransferHistoryService {
  TransferHistoryService(
    this.storageRoot, {
    this.maxBatches = 250,
    this.maxDirectoryEntries = 2000,
    this.readTimeout = const Duration(seconds: 30),
  }) {
    if (maxBatches < 1 ||
        maxDirectoryEntries < 1 ||
        readTimeout <= Duration.zero) {
      throw ArgumentError('History limits and read timeout must be positive.');
    }
  }

  final Directory storageRoot;
  final int maxBatches;
  final int maxDirectoryEntries;
  final Duration readTimeout;

  static Directory rootForDocuments(Directory documents) =>
      Directory(p.join(documents.path, 'ShareBondhu', 'Received'));

  Future<HistorySnapshot> load({HistoryCancellation? cancellation}) async {
    final token = cancellation ?? HistoryCancellation();
    token.throwIfCanceled();
    final root = await _safeRoot();
    if (root == null) {
      return HistorySnapshot(transfers: const <SavedTransfer>[]);
    }
    final candidates = <({String name, DateTime modified})>[];
    var inspected = 0;
    var skipped = 0;
    var truncated = false;
    try {
      await for (final entity in Directory(root).list(followLinks: false)) {
        token.throwIfCanceled();
        inspected += 1;
        if (inspected > maxDirectoryEntries) {
          truncated = true;
          break;
        }
        final name = p.basename(entity.path);
        if (!isReceivedFolderName(name)) {
          continue;
        }
        if (entity is! Directory) {
          skipped += 1;
          continue;
        }
        try {
          final stat = await entity.stat();
          candidates.add((name: name, modified: stat.modified));
        } on FileSystemException {
          skipped += 1;
        }
      }
    } on FileSystemException {
      throw const HistoryException(
        'Saved-file storage could not be listed. Try again.',
      );
    }
    candidates.sort((a, b) {
      final byTime = b.modified.compareTo(a.modified);
      return byTime == 0 ? a.name.compareTo(b.name) : byTime;
    });
    final transfers = <SavedTransfer>[];
    for (var index = 0; index < candidates.length; index += 1) {
      token.throwIfCanceled();
      if (transfers.length >= maxBatches) {
        truncated = true;
        break;
      }
      try {
        transfers.add(await _loadFolder(candidates[index].name, token));
      } on HistoryCancelled {
        rethrow;
      } on HistoryException {
        skipped += 1;
      } on FileSystemException {
        skipped += 1;
      } on TimeoutException {
        skipped += 1;
      }
    }
    transfers.sort((a, b) {
      final byTime = b.receipt.completedAt.compareTo(a.receipt.completedAt);
      return byTime == 0 ? a.id.compareTo(b.id) : byTime;
    });
    token.throwIfCanceled();
    return HistorySnapshot(
      transfers: transfers,
      skippedEntries: skipped,
      truncated: truncated,
    );
  }

  Future<SavedTransfer> verify(
    SavedTransfer transfer, {
    HistoryCancellation? cancellation,
    void Function(HistoryCheckProgress)? onProgress,
  }) async {
    final token = cancellation ?? HistoryCancellation();
    final fresh = await _reloadUnchanged(transfer, token);
    final indices = List<int>.generate(fresh.files.length, (index) => index);
    return _check(fresh, indices, token, onProgress);
  }

  Future<List<HistoryShareFile>> prepareShare(
    SavedTransfer transfer, {
    int? fileIndex,
    HistoryCancellation? cancellation,
    void Function(HistoryCheckProgress)? onProgress,
  }) async {
    final token = cancellation ?? HistoryCancellation();
    final fresh = await _reloadUnchanged(transfer, token);
    if (fileIndex != null &&
        (fileIndex < 0 || fileIndex >= fresh.files.length)) {
      throw const HistoryException(
        'That saved file is no longer in this batch.',
      );
    }
    final indices = fileIndex == null
        ? List<int>.generate(fresh.files.length, (index) => index)
        : <int>[fileIndex];
    final checked = await _check(fresh, indices, token, onProgress);
    if (indices.any(
      (index) => checked.files[index].status != SavedFileStatus.verified,
    )) {
      throw const HistoryException(
        'Some selected copies are missing, changed, or unreadable. '
        'Refresh and check the file details before sharing.',
      );
    }
    final directory = await _safeBatchDirectory(checked.folderName);
    final result = <HistoryShareFile>[];
    for (final index in indices) {
      token.throwIfCanceled();
      final file = checked.files[index];
      final probe = await _regularFile(directory, file.storedName);
      if (probe.stat.size != file.receipt.size) {
        throw const HistoryException(
          'A saved copy changed after checking. Try again.',
        );
      }
      result.add(HistoryShareFile(path: probe.path, name: file.receipt.name));
    }
    token.throwIfCanceled();
    return List<HistoryShareFile>.unmodifiable(result);
  }

  Future<SavedTransfer> _check(
    SavedTransfer fresh,
    List<int> indices,
    HistoryCancellation token,
    void Function(HistoryCheckProgress)? onProgress,
  ) async {
    final files = fresh.files.toList();
    final totalBytes = indices.fold<int>(
      0,
      (sum, index) => sum + files[index].receipt.size,
    );
    var bytesChecked = 0;
    var filesChecked = 0;
    for (final index in indices) {
      token.throwIfCanceled();
      final file = files[index];
      files[index] = await _checkFile(fresh.folderName, file, token, (count) {
        bytesChecked += count;
        onProgress?.call(
          HistoryCheckProgress(
            filesChecked: filesChecked,
            totalFiles: indices.length,
            bytesChecked: bytesChecked,
            totalBytes: totalBytes,
            fileName: file.receipt.name,
          ),
        );
      });
      filesChecked += 1;
      onProgress?.call(
        HistoryCheckProgress(
          filesChecked: filesChecked,
          totalFiles: indices.length,
          bytesChecked: bytesChecked,
          totalBytes: totalBytes,
          fileName: file.receipt.name,
        ),
      );
    }
    token.throwIfCanceled();
    // A receipt changed during checking is not silently accepted as a new truth.
    await _reloadUnchanged(fresh, token);
    return fresh.withFiles(files, checkedAt: DateTime.now().toUtc());
  }

  Future<SavedFile> _checkFile(
    String folder,
    SavedFile saved,
    HistoryCancellation token,
    void Function(int count) onBytes,
  ) async {
    token.throwIfCanceled();
    StreamIterator<List<int>>? iterator;
    void Function()? unlisten;
    ByteConversionSink? hashInput;
    var hashClosed = false;
    try {
      final directory = await _safeBatchDirectory(folder);
      final before = await _regularFile(directory, saved.storedName);
      if (before.stat.size != saved.receipt.size) {
        return saved.withStatus(
          SavedFileStatus.sizeChanged,
          size: before.stat.size,
        );
      }
      final output = _HistoryDigestOutput();
      hashInput = sha256.startChunkedConversion(output);
      final reader = StreamIterator<List<int>>(File(before.path).openRead());
      iterator = reader;
      unlisten = token.onCancel(() {
        unawaited(
          reader.cancel().then<void>(
            (_) {},
            onError: (Object error, StackTrace stack) {},
          ),
        );
      });
      var count = 0;
      while (await reader.moveNext().timeout(readTimeout)) {
        token.throwIfCanceled();
        final chunk = reader.current;
        count += chunk.length;
        if (count > saved.receipt.size) {
          return saved.withStatus(SavedFileStatus.sizeChanged, size: count);
        }
        hashInput.add(chunk);
        onBytes(chunk.length);
      }
      token.throwIfCanceled();
      hashInput.close();
      hashClosed = true;
      final afterDirectory = await _safeBatchDirectory(folder);
      final after = await _regularFile(afterDirectory, saved.storedName);
      if (count != saved.receipt.size ||
          after.stat.size != saved.receipt.size ||
          after.stat.modified != before.stat.modified ||
          !p.equals(after.path, before.path)) {
        return saved.withStatus(
          SavedFileStatus.sizeChanged,
          size: after.stat.size,
        );
      }
      final matches = secretEquals(
        output.value!.toString(),
        saved.receipt.digest,
      );
      return saved.withStatus(
        matches ? SavedFileStatus.verified : SavedFileStatus.checksumMismatch,
        size: count,
      );
    } on HistoryCancelled {
      rethrow;
    } on _FileProblem catch (problem) {
      return saved.withStatus(problem.status);
    } on FileSystemException {
      return saved.withStatus(SavedFileStatus.unreadable);
    } on TimeoutException {
      return saved.withStatus(SavedFileStatus.unreadable);
    } finally {
      unlisten?.call();
      if (iterator != null) {
        try {
          await iterator.cancel().timeout(readTimeout);
        } catch (_) {}
      }
      if (hashInput != null && !hashClosed) {
        hashInput.close();
      }
    }
  }

  Future<SavedTransfer> _reloadUnchanged(
    SavedTransfer transfer,
    HistoryCancellation token,
  ) async {
    final fresh = await _loadFolder(transfer.folderName, token);
    if (!secretEquals(fresh.manifestDigest, transfer.manifestDigest)) {
      throw const HistoryException(
        'The saved receipt changed. Refresh the list before continuing.',
      );
    }
    return fresh;
  }

  Future<SavedTransfer> _loadFolder(
    String name,
    HistoryCancellation token,
  ) async {
    token.throwIfCanceled();
    final directory = await _safeBatchDirectory(name);
    late Uint8List bytes;
    try {
      final probe = await _regularFile(directory, 'transfer.json');
      if (probe.stat.size > TransferLimits.maxMetadataBytes) {
        throw const HistoryException('A saved receipt is too large.');
      }
      bytes = await _readReceipt(probe.path, token);
      final after = await _regularFile(directory, 'transfer.json');
      if (after.stat.size != bytes.length ||
          after.stat.modified != probe.stat.modified) {
        throw const HistoryException(
          'The saved receipt changed while loading.',
        );
      }
    } on _FileProblem {
      throw const HistoryException('The saved receipt is missing or unsafe.');
    }
    token.throwIfCanceled();
    late TransferReceipt receipt;
    try {
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map<String, dynamic>) {
        throw const FormatException();
      }
      receipt = parseSavedReceipt(data);
    } catch (_) {
      throw const HistoryException(
        'A saved receipt is invalid or unsupported.',
      );
    }
    final files = <SavedFile>[];
    for (var index = 0; index < receipt.files.length; index += 1) {
      token.throwIfCanceled();
      final file = SavedFile(
        index: index,
        receipt: receipt.files[index],
        status: SavedFileStatus.available,
      );
      try {
        final probe = await _regularFile(directory, file.storedName);
        files.add(
          file.withStatus(
            probe.stat.size == file.receipt.size
                ? SavedFileStatus.available
                : SavedFileStatus.sizeChanged,
            size: probe.stat.size,
          ),
        );
      } on _FileProblem catch (problem) {
        files.add(file.withStatus(problem.status));
      } on FileSystemException {
        files.add(file.withStatus(SavedFileStatus.unreadable));
      }
    }
    return SavedTransfer(
      folderName: name,
      receipt: receipt,
      manifestDigest: sha256.convert(bytes).toString(),
      files: files,
    );
  }

  Future<Uint8List> _readReceipt(String path, HistoryCancellation token) async {
    final reader = StreamIterator<List<int>>(File(path).openRead());
    final builder = BytesBuilder(copy: false);
    final clock = Stopwatch()..start();
    final unlisten = token.onCancel(() {
      unawaited(
        reader.cancel().then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {},
        ),
      );
    });
    try {
      while (true) {
        token.throwIfCanceled();
        final remaining = readTimeout - clock.elapsed;
        if (remaining <= Duration.zero) {
          throw TimeoutException('Receipt read deadline exceeded.');
        }
        if (!await reader.moveNext().timeout(remaining)) {
          break;
        }
        if (builder.length + reader.current.length >
            TransferLimits.maxMetadataBytes) {
          throw const HistoryException('A saved receipt is too large.');
        }
        builder.add(reader.current);
      }
      token.throwIfCanceled();
      return builder.takeBytes();
    } finally {
      unlisten();
      try {
        await reader.cancel().timeout(readTimeout);
      } catch (_) {}
    }
  }

  Future<String?> _safeRoot() async {
    final type = await FileSystemEntity.type(
      storageRoot.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) {
      return null;
    }
    if (type != FileSystemEntityType.directory) {
      throw const HistoryException(
        'Saved-file storage is not a regular app directory.',
      );
    }
    final root = p.normalize(await storageRoot.resolveSymbolicLinks());
    if (p.equals(p.dirname(root), root)) {
      throw const HistoryException(
        'Refusing to inspect the filesystem root as app history.',
      );
    }
    return root;
  }

  Future<String> _safeBatchDirectory(String name) async {
    if (!isReceivedFolderName(name)) {
      throw const HistoryException('Invalid saved-transfer folder.');
    }
    final root = await _safeRoot();
    if (root == null) {
      throw const HistoryException(
        'Saved-file storage is no longer available.',
      );
    }
    final directory = p.join(root, name);
    if (await FileSystemEntity.type(directory, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const HistoryException('The saved batch is missing or is a link.');
    }
    final resolved = p.normalize(
      await Directory(directory).resolveSymbolicLinks(),
    );
    if (!p.equals(resolved, directory) ||
        !p.equals(p.dirname(resolved), root)) {
      throw const HistoryException('A saved batch points outside app storage.');
    }
    return resolved;
  }

  Future<({String path, FileStat stat})> _regularFile(
    String directory,
    String name,
  ) async {
    if (p.basename(name) != name || name == '.' || name == '..') {
      throw const _FileProblem(SavedFileStatus.unsafe);
    }
    if (await FileSystemEntity.type(directory, followLinks: false) !=
            FileSystemEntityType.directory ||
        !p.equals(
          p.normalize(await Directory(directory).resolveSymbolicLinks()),
          directory,
        )) {
      throw const _FileProblem(SavedFileStatus.unsafe);
    }
    final path = p.join(directory, name);
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw const _FileProblem(SavedFileStatus.missing);
    }
    if (type != FileSystemEntityType.file) {
      throw const _FileProblem(SavedFileStatus.unsafe);
    }
    final resolved = p.normalize(await File(path).resolveSymbolicLinks());
    if (!p.equals(resolved, path) ||
        !p.equals(p.dirname(resolved), directory)) {
      throw const _FileProblem(SavedFileStatus.unsafe);
    }
    final stat = await File(path).stat();
    if (stat.type != FileSystemEntityType.file) {
      throw const _FileProblem(SavedFileStatus.unreadable);
    }
    return (path: resolved, stat: stat);
  }
}

class _HistoryDigestOutput implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

class _FileProblem implements Exception {
  const _FileProblem(this.status);

  final SavedFileStatus status;
}
