import 'dart:convert';

import 'transfer_models.dart';

class HistoryException extends TransferException {
  const HistoryException(super.message);
}

class HistoryCancelled extends HistoryException {
  const HistoryCancelled()
    : super('File checking canceled. Saved files are unchanged.');
}

class HistoryCancellation {
  bool _canceled = false;
  final Set<void Function()> _listeners = <void Function()>{};

  bool get isCanceled => _canceled;

  void throwIfCanceled() {
    if (_canceled) {
      throw const HistoryCancelled();
    }
  }

  void Function() onCancel(void Function() listener) {
    if (_canceled) {
      listener();
    } else {
      _listeners.add(listener);
    }
    return () => _listeners.remove(listener);
  }

  void cancel() {
    if (_canceled) {
      return;
    }
    _canceled = true;
    final listeners = _listeners.toList();
    _listeners.clear();
    for (final listener in listeners) {
      try {
        listener();
      } catch (_) {
        // Cancellation must still reach the remaining owned operations.
      }
    }
  }
}

enum SavedFileStatus {
  available,
  verified,
  missing,
  sizeChanged,
  checksumMismatch,
  unsafe,
  unreadable,
}

class SavedFile {
  const SavedFile({
    required this.index,
    required this.receipt,
    required this.status,
    this.currentSize,
  });

  final int index;
  final ReceivedFile receipt;
  final SavedFileStatus status;
  final int? currentSize;

  String get storedName =>
      '${(index + 1).toString().padLeft(3, '0')}_${receipt.name}';

  bool get canCheck =>
      status == SavedFileStatus.available ||
      status == SavedFileStatus.verified ||
      status == SavedFileStatus.checksumMismatch;

  bool get hasIssue =>
      status != SavedFileStatus.available && status != SavedFileStatus.verified;

  String get statusLabel => switch (status) {
    SavedFileStatus.available => 'Size matches · not rechecked',
    SavedFileStatus.verified => 'Checksum verified this session',
    SavedFileStatus.missing => 'Saved copy is missing',
    SavedFileStatus.sizeChanged => 'File size changed',
    SavedFileStatus.checksumMismatch => 'Checksum does not match',
    SavedFileStatus.unsafe => 'Unsafe file reference blocked',
    SavedFileStatus.unreadable => 'File could not be read',
  };

  SavedFile withStatus(SavedFileStatus value, {int? size}) => SavedFile(
    index: index,
    receipt: receipt,
    status: value,
    currentSize: size ?? currentSize,
  );
}

class SavedTransfer {
  SavedTransfer({
    required this.folderName,
    required this.receipt,
    required this.manifestDigest,
    required Iterable<SavedFile> files,
    this.verifiedAt,
  }) : files = List<SavedFile>.unmodifiable(files) {
    if (!isReceivedFolderName(folderName) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(manifestDigest)) {
      throw const HistoryException('Invalid saved-transfer reference.');
    }
  }

  final String folderName;
  final TransferReceipt receipt;
  final String manifestDigest;
  final List<SavedFile> files;
  final DateTime? verifiedAt;

  // Folder identity is receiver-generated. A sender can repeat a wire batch ID.
  String get id => folderName;
  int get totalBytes => receipt.totalBytes;
  bool get hasIssues => files.any((file) => file.hasIssue);
  bool get allVerified =>
      files.isNotEmpty &&
      files.every((file) => file.status == SavedFileStatus.verified);

  SavedTransfer withFiles(Iterable<SavedFile> updated, {DateTime? checkedAt}) =>
      SavedTransfer(
        folderName: folderName,
        receipt: receipt,
        manifestDigest: manifestDigest,
        files: updated,
        verifiedAt: checkedAt,
      );
}

class HistorySnapshot {
  HistorySnapshot({
    required Iterable<SavedTransfer> transfers,
    this.skippedEntries = 0,
    this.truncated = false,
  }) : transfers = List<SavedTransfer>.unmodifiable(transfers);

  final List<SavedTransfer> transfers;
  final int skippedEntries;
  final bool truncated;

  int get fileCount =>
      transfers.fold<int>(0, (count, batch) => count + batch.files.length);
  int get recordedBytes =>
      transfers.fold<int>(0, (count, batch) => count + batch.totalBytes);
}

class HistoryCheckProgress {
  const HistoryCheckProgress({
    required this.filesChecked,
    required this.totalFiles,
    required this.bytesChecked,
    required this.totalBytes,
    required this.fileName,
  });

  final int filesChecked;
  final int totalFiles;
  final int bytesChecked;
  final int totalBytes;
  final String fileName;

  double get fraction => totalBytes == 0
      ? (filesChecked == totalFiles ? 1 : 0)
      : (bytesChecked / totalBytes).clamp(0.0, 1.0);
}

class HistoryShareFile {
  const HistoryShareFile({required this.path, required this.name});

  final String path;
  final String name;
}

bool isReceivedFolderName(String value) =>
    RegExp(r'^received-[a-f0-9]{32}$').hasMatch(value);

TransferReceipt parseSavedReceipt(Map<String, dynamic> data) {
  try {
    final id = data['id'];
    final sender = data['senderName'];
    final completed = data['completedAt'];
    final entries = data['files'];
    if (data['version'] != TransferLimits.protocolVersion ||
        id is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        sender is! String ||
        utf8.encode(sender).length > 80 ||
        completed is! String ||
        completed.length > 40 ||
        entries is! List ||
        entries.isEmpty ||
        entries.length > TransferLimits.maxFiles) {
      throw const FormatException();
    }
    final timestamp = DateTime.tryParse(completed);
    if (timestamp == null || !timestamp.isUtc) {
      throw const FormatException();
    }
    final ids = <String>{};
    var total = 0;
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException();
      }
      final name = entry['name'];
      final descriptor = OfferedFile.fromJson(entry);
      if (name is! String ||
          utf8.encode(name).length > TransferLimits.maxNameBytes ||
          safeFileName(name) != name ||
          !ids.add(descriptor.id)) {
        throw const FormatException();
      }
      total += descriptor.size;
      if (total > TransferLimits.maxBatchBytes) {
        throw const FormatException();
      }
    }
    // The v1 parser discards serialized localPath fields. Disk paths are derived
    // separately from the checked folder, list position and safe display name.
    return TransferReceipt.fromJson(data);
  } catch (_) {
    throw const HistoryException('A saved receipt is invalid or unsupported.');
  }
}
