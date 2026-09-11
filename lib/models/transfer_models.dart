import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'share_file.dart';

abstract final class TransferLimits {
  static const int protocolVersion = 1;
  static const int maxFiles = 50;
  static const int maxFileBytes = 2 * 1024 * 1024 * 1024;
  static const int maxBatchBytes = 4 * 1024 * 1024 * 1024;
  static const int maxMetadataBytes = 64 * 1024;
  static const int maxNameBytes = 180;
}

class TransferException implements Exception {
  const TransferException(this.message, {this.outcomeUncertain = false});

  final String message;
  final bool outcomeUncertain;

  @override
  String toString() => message;
}

class TransferCancelled extends TransferException {
  const TransferCancelled()
    : super('Transfer canceled. Files already confirmed as saved are kept.');
}

String randomToken([int byteCount = 32]) {
  final random = Random.secure();
  final bytes = List<int>.generate(byteCount, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

String randomTransferId() {
  final random = Random.secure();
  return List<String>.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

bool secretEquals(String first, String second) {
  if (first.length != second.length) {
    return false;
  }
  var difference = 0;
  for (var i = 0; i < first.length; i += 1) {
    difference |= first.codeUnitAt(i) ^ second.codeUnitAt(i);
  }
  return difference == 0;
}

bool isLocalIpv4(String host, {bool allowLoopback = false}) {
  final address = InternetAddress.tryParse(host);
  if (address == null ||
      address.type != InternetAddressType.IPv4 ||
      address.address != host) {
    return false;
  }
  final bytes = address.rawAddress;
  if (allowLoopback && bytes[0] == 127) {
    return true;
  }
  return bytes[0] == 10 ||
      (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
      (bytes[0] == 192 && bytes[1] == 168) ||
      (bytes[0] == 169 && bytes[1] == 254);
}

String _boundedText(String value, int maxBytes) {
  final buffer = StringBuffer();
  var byteCount = 0;
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    final length = utf8.encode(character).length;
    if (byteCount + length > maxBytes) {
      break;
    }
    buffer.write(character);
    byteCount += length;
  }
  return buffer.toString();
}

String safeFileName(String input) {
  var name = input
      .replaceAll(RegExp(r'[\x00-\x1f\x7f/\\:*?"<>|]'), '_')
      .replaceAll(RegExp('[\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff]'), '')
      .trim()
      .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
  name = _boundedText(name, TransferLimits.maxNameBytes).trim();
  if (name.isEmpty) {
    name = 'file';
  }
  final stem = name.split('.').first.toUpperCase();
  if (RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$').hasMatch(stem)) {
    name = '_$name';
  }
  return _boundedText(
    name,
    TransferLimits.maxNameBytes,
  ).replaceAll(RegExp(r'[. ]+$'), '');
}

String safeDeviceName(String input) {
  final cleaned = input
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
      .replaceAll(RegExp('[\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff]'), '')
      .trim();
  final name = _boundedText(cleaned, 80);
  return name.isEmpty ? 'Nearby device' : name;
}

class PairingCode {
  PairingCode({
    required this.host,
    required this.port,
    required this.token,
    required this.fingerprint,
    bool allowLoopback = false,
  }) {
    if (!isLocalIpv4(host, allowLoopback: allowLoopback) ||
        port < 1 ||
        port > 65535 ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token) ||
        base64Url.decode(base64Url.normalize(token)).length != 32 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint)) {
      throw const TransferException(
        'That pairing code is invalid. Copy it again.',
      );
    }
  }

  final String host;
  final int port;
  final String token;
  final String fingerprint;

  factory PairingCode.parse(String input, {bool allowLoopback = false}) {
    try {
      final value = input.trim();
      if (!value.startsWith('SB1.') || value.length != 98) {
        throw const FormatException();
      }
      final bytes = base64Url.decode(base64Url.normalize(value.substring(4)));
      if (bytes.length != 70) {
        throw const FormatException();
      }
      final data = ByteData.sublistView(bytes);
      return PairingCode(
        host: bytes.sublist(0, 4).join('.'),
        port: data.getUint16(4),
        token: base64Url.encode(bytes.sublist(6, 38)).replaceAll('=', ''),
        fingerprint: bytes
            .sublist(38)
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(),
        allowLoopback: allowLoopback,
      );
    } catch (_) {
      throw const TransferException(
        'Use the complete SB1 pairing code from a nearby receiver. '
        'Only private IPv4 Wi-Fi or hotspot addresses are supported.',
      );
    }
  }

  String encode() {
    final bytes = Uint8List(70);
    bytes.setRange(0, 4, InternetAddress(host).rawAddress);
    ByteData.sublistView(bytes).setUint16(4, port);
    bytes.setRange(6, 38, base64Url.decode(base64Url.normalize(token)));
    for (var i = 0; i < 32; i += 1) {
      bytes[38 + i] = int.parse(
        fingerprint.substring(i * 2, i * 2 + 2),
        radix: 16,
      );
    }
    return 'SB1.${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  Uri endpoint(String path) =>
      Uri(scheme: 'https', host: host, port: port, path: path);

  @override
  String toString() => 'PairingCode($host:$port, credentials redacted)';
}

class ReceiverSession {
  ReceiverSession({
    required Iterable<String> addresses,
    required this.port,
    required this.token,
    required this.fingerprint,
    required this.expiresAt,
    this.allowLoopback = false,
  }) : addresses = List<String>.unmodifiable(addresses);

  final List<String> addresses;
  final int port;
  final String token;
  final String fingerprint;
  final DateTime expiresAt;
  final bool allowLoopback;

  PairingCode codeFor(String host) {
    if (!addresses.contains(host)) {
      throw const TransferException('Choose an address from this device.');
    }
    return PairingCode(
      host: host,
      port: port,
      token: token,
      fingerprint: fingerprint,
      allowLoopback: allowLoopback,
    );
  }
}

class OfferedFile {
  OfferedFile({required this.id, required String name, required this.size})
    : name = safeFileName(name) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        name.trim().isEmpty ||
        utf8.encode(name).length > 1024 ||
        size < 0 ||
        size > TransferLimits.maxFileBytes) {
      throw const TransferException(
        'Invalid file metadata. Each file must be at most 2 GiB.',
      );
    }
  }

  final String id;
  final String name;
  final int size;

  factory OfferedFile.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['id'] is! String ||
        value['name'] is! String ||
        value['size'] is! int) {
      throw const TransferException('Invalid file metadata.');
    }
    return OfferedFile(
      id: value['id'] as String,
      name: value['name'] as String,
      size: value['size'] as int,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'name': name,
    'size': size,
  };
}

class IncomingOffer {
  IncomingOffer({
    required this.id,
    required String senderName,
    required this.remoteAddress,
    required Iterable<OfferedFile> files,
  }) : senderName = safeDeviceName(senderName),
       files = List<OfferedFile>.unmodifiable(files) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        this.files.isEmpty ||
        this.files.length > TransferLimits.maxFiles ||
        this.files.map((file) => file.id).toSet().length != this.files.length ||
        totalBytes > TransferLimits.maxBatchBytes) {
      throw const TransferException(
        'Choose 1 to 50 files, at most 2 GiB each and 4 GiB in total.',
      );
    }
  }

  final String id;
  final String senderName;
  final String remoteAddress;
  final List<OfferedFile> files;

  int get totalBytes => files.fold<int>(0, (sum, file) => sum + file.size);

  factory IncomingOffer.fromJson(
    Map<String, dynamic> value, {
    required String remoteAddress,
  }) {
    if (value['version'] != TransferLimits.protocolVersion ||
        value['id'] is! String ||
        value['senderName'] is! String ||
        value['files'] is! List ||
        (value['files'] as List).length > TransferLimits.maxFiles) {
      throw const TransferException('Unsupported or invalid transfer request.');
    }
    return IncomingOffer(
      id: value['id'] as String,
      senderName: value['senderName'] as String,
      remoteAddress: remoteAddress,
      files: (value['files'] as List).map(OfferedFile.fromJson),
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'version': TransferLimits.protocolVersion,
    'id': id,
    'senderName': senderName,
    'files': files.map((file) => file.toJson()).toList(),
  };
}

enum TransferPhase {
  waiting,
  connecting,
  awaitingApproval,
  sending,
  receiving,
  verifying,
  completed,
  rejected,
  canceled,
  failed,
  idle,
  approved,
  preparing,
}

class TransferProgress {
  const TransferProgress({
    required this.phase,
    required this.message,
    this.totalBytes = 0,
    this.processedBytes = 0,
    this.totalFiles = 0,
    this.completedFiles = 0,
    this.fileName,
    this.transferId,
    this.attemptId,
    this.sequence = 0,
    this.manifest,
    this.currentFileIndex,
    this.currentFileBytes,
    this.currentFileTotalBytes,
    this.verifiedFiles = 0,
    this.commitStarted = false,
    this.receipt,
  });

  final TransferPhase phase;
  final String message;
  final int totalBytes;
  final int processedBytes;
  final int totalFiles;
  final int completedFiles;
  final String? fileName;
  // Local telemetry only. These fields are never added to the wire protocol.
  final String? transferId;
  final String? attemptId;
  final int sequence;
  final List<OfferedFile>? manifest;
  final int? currentFileIndex;
  final int? currentFileBytes;
  final int? currentFileTotalBytes;
  final int verifiedFiles;
  final bool commitStarted;
  final TransferReceipt? receipt;

  TransferProgress copyWith({
    TransferPhase? phase,
    String? message,
    int? totalBytes,
    int? processedBytes,
    int? totalFiles,
    int? completedFiles,
    String? fileName,
    String? transferId,
    String? attemptId,
    int? sequence,
    List<OfferedFile>? manifest,
    int? currentFileIndex,
    int? currentFileBytes,
    int? currentFileTotalBytes,
    int? verifiedFiles,
    bool? commitStarted,
    TransferReceipt? receipt,
  }) => TransferProgress(
    phase: phase ?? this.phase,
    message: message ?? this.message,
    totalBytes: totalBytes ?? this.totalBytes,
    processedBytes: processedBytes ?? this.processedBytes,
    totalFiles: totalFiles ?? this.totalFiles,
    completedFiles: completedFiles ?? this.completedFiles,
    fileName: fileName ?? this.fileName,
    transferId: transferId ?? this.transferId,
    attemptId: attemptId ?? this.attemptId,
    sequence: sequence ?? this.sequence,
    manifest: manifest ?? this.manifest,
    currentFileIndex: currentFileIndex ?? this.currentFileIndex,
    currentFileBytes: currentFileBytes ?? this.currentFileBytes,
    currentFileTotalBytes: currentFileTotalBytes ?? this.currentFileTotalBytes,
    verifiedFiles: verifiedFiles ?? this.verifiedFiles,
    commitStarted: commitStarted ?? this.commitStarted,
    receipt: receipt ?? this.receipt,
  );

  double get fraction {
    if (phase == TransferPhase.completed) {
      return 1;
    }
    return totalBytes == 0 ? 0 : (processedBytes / totalBytes).clamp(0.0, 1.0);
  }

  bool get indeterminate =>
      phase == TransferPhase.connecting ||
      phase == TransferPhase.awaitingApproval ||
      phase == TransferPhase.preparing ||
      phase == TransferPhase.verifying;
}

class ReceivedFile {
  const ReceivedFile({
    required this.id,
    required this.name,
    required this.size,
    required this.digest,
    this.localPath,
  });

  final String id;
  final String name;
  final int size;
  final String digest;
  final String? localPath;

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'name': name,
    'size': size,
    'sha256': digest,
  };
}

class TransferReceipt {
  TransferReceipt({
    required this.id,
    required this.senderName,
    required this.completedAt,
    required Iterable<ReceivedFile> files,
  }) : files = List<ReceivedFile>.unmodifiable(files);

  final String id;
  final String senderName;
  final DateTime completedAt;
  final List<ReceivedFile> files;

  int get totalBytes => files.fold<int>(0, (sum, file) => sum + file.size);

  Map<String, Object> toJson() => <String, Object>{
    'version': TransferLimits.protocolVersion,
    'id': id,
    'senderName': senderName,
    'completedAt': completedAt.toUtc().toIso8601String(),
    'files': files.map((file) => file.toJson()).toList(),
  };

  factory TransferReceipt.fromJson(Map<String, dynamic> data) {
    final entries = data['files'];
    if (data['version'] != TransferLimits.protocolVersion ||
        data['id'] is! String ||
        data['senderName'] is! String ||
        data['completedAt'] is! String ||
        entries is! List ||
        entries.isEmpty ||
        entries.length > TransferLimits.maxFiles) {
      throw const TransferException(
        'The receiver returned an invalid receipt.',
      );
    }
    final files = <ReceivedFile>[];
    for (final entry in entries) {
      final descriptor = OfferedFile.fromJson(entry);
      if (entry is! Map<String, dynamic> ||
          entry['sha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(entry['sha256'] as String)) {
        throw const TransferException(
          'The receiver returned an invalid checksum.',
        );
      }
      files.add(
        ReceivedFile(
          id: descriptor.id,
          name: descriptor.name,
          size: descriptor.size,
          digest: entry['sha256'] as String,
        ),
      );
    }
    return TransferReceipt(
      id: data['id'] as String,
      senderName: safeDeviceName(data['senderName'] as String),
      completedAt: DateTime.parse(data['completedAt'] as String),
      files: files,
    );
  }
}

IncomingOffer createOutgoingOffer(List<ShareFile> files, String senderName) {
  return IncomingOffer(
    id: randomTransferId(),
    senderName: senderName,
    remoteAddress: '',
    files: files.map(
      (file) =>
          OfferedFile(id: randomTransferId(), name: file.name, size: file.size),
    ),
  );
}
