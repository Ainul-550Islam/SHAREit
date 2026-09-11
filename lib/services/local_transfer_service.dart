import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart'
    show CryptoUtils, X509Utils, RSAPrivateKey, RSAPublicKey;
import 'package:crypto/crypto.dart';

import '../models/share_file.dart';
import '../models/transfer_models.dart';

class TlsIdentity {
  const TlsIdentity({
    required this.certificatePem,
    required this.privateKeyPem,
    required this.fingerprint,
  });

  final String certificatePem;
  final String privateKeyPem;
  final String fingerprint;

  static Future<TlsIdentity> generate() => Isolate.run(_generateTlsIdentity);
}

TlsIdentity _generateTlsIdentity() {
  final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final privateKey = pair.privateKey as RSAPrivateKey;
  final publicKey = pair.publicKey as RSAPublicKey;
  final csr = X509Utils.generateRsaCsrPem(
    <String, String>{'CN': 'ShareBondhu local session'},
    privateKey,
    publicKey,
  );
  final certificate = X509Utils.generateSelfSignedCertificate(
    privateKey,
    csr,
    1,
    cA: false,
    serialNumber: BigInt.parse(randomTransferId(), radix: 16).toString(),
    notBefore: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
  );
  final der = CryptoUtils.getBytesFromPEMString(certificate);
  return TlsIdentity(
    certificatePem: certificate,
    privateKeyPem: CryptoUtils.encodeRSAPrivateKeyToPem(privateKey),
    fingerprint: sha256.convert(der).toString(),
  );
}

Future<List<String>> localIpv4Addresses() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
    includeLinkLocal: true,
  );
  final addresses = <String>{};
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      if (isLocalIpv4(address.address)) {
        addresses.add(address.address);
      }
    }
  }
  return addresses.toList()..sort();
}

Future<Map<String, dynamic>> readBoundedJson(
  Stream<List<int>> source, {
  Duration timeout = const Duration(seconds: 15),
  int maxBytes = TransferLimits.maxMetadataBytes,
}) async {
  final iterator = StreamIterator<List<int>>(source);
  final bytes = BytesBuilder(copy: false);
  final clock = Stopwatch()..start();
  try {
    while (true) {
      final remaining = timeout - clock.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('Metadata deadline exceeded.');
      }
      if (!await iterator.moveNext().timeout(remaining)) {
        break;
      }
      if (bytes.length + iterator.current.length > maxBytes) {
        throw const TransferException('The metadata message is too large.');
      }
      bytes.add(iterator.current);
    }
    final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
    if (decoded is! Map<String, dynamic>) {
      throw const TransferException('Expected a JSON object.');
    }
    return decoded;
  } finally {
    await iterator.cancel();
  }
}

HttpClient createPinnedClient(
  PairingCode code, {
  Duration connectionTimeout = const Duration(seconds: 10),
}) {
  final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
  client.connectionTimeout = connectionTimeout;
  client.idleTimeout = const Duration(seconds: 15);
  client.maxConnectionsPerHost = 2;
  client.autoUncompress = false;
  client.findProxy = (_) => 'DIRECT';
  client.badCertificateCallback = (certificate, host, port) {
    return host == code.host &&
        port == code.port &&
        secretEquals(
          sha256.convert(certificate.der).toString(),
          code.fingerprint,
        );
  };
  return client;
}

class _DigestOutput implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

class _HttpFailure extends TransferException {
  const _HttpFailure(this.status, super.message);

  final int status;
}

class _ReceivingBatch {
  _ReceivingBatch({
    required this.offer,
    required this.token,
    required this.directory,
    required this.progressId,
  });

  final IncomingOffer offer;
  final String token;
  final Directory directory;
  final String progressId;
  int? currentFileIndex;
  int currentFileBytes = 0;
  int verifiedFiles = 0;
  final Map<String, String> digests = <String, String>{};
  HttpRequest? uploadRequest;
  Future<void> ioDone = Future<void>.value();
  Future<void>? cleanup;
  Timer? timer;
  Timer? idleTimer;
  bool cleanupSucceeded = true;
  bool canceled = false;
  bool uploading = false;
  bool committing = false;
  bool committed = false;
  int bytesReceived = 0;
}

class LocalReceiver {
  LocalReceiver({
    required this.storageRoot,
    required this.onOffer,
    this.onProgress,
    this.onReceived,
    this.onStopped,
    this.identityFactory = TlsIdentity.generate,
    this.inviteLifetime = const Duration(minutes: 10),
    this.approvalTimeout = const Duration(seconds: 60),
    this.idleTimeout = const Duration(seconds: 30),
    this.batchTimeout = const Duration(minutes: 30),
    this.allowLoopback = false,
  }) {
    for (final duration in <Duration>[
      inviteLifetime,
      approvalTimeout,
      idleTimeout,
      batchTimeout,
    ]) {
      if (duration <= Duration.zero) {
        throw ArgumentError('Timeouts must be positive.');
      }
    }
  }

  final Directory storageRoot;
  final Future<bool> Function(IncomingOffer offer) onOffer;
  final void Function(TransferProgress progress)? onProgress;
  final void Function(TransferReceipt receipt)? onReceived;
  final void Function(String reason)? onStopped;
  final Future<TlsIdentity> Function() identityFactory;
  final Duration inviteLifetime;
  final Duration approvalTimeout;
  final Duration idleTimeout;
  final Duration batchTimeout;
  final bool allowLoopback;

  HttpServer? _server;
  ReceiverSession? _session;
  _ReceivingBatch? _batch;
  TransferReceipt? _lastReceipt;
  String? _lastReceiptToken;
  Timer? _inviteTimer;
  Completer<bool>? _approval;
  Future<void>? _stopFuture;
  final Set<HttpRequest> _requests = <HttpRequest>{};
  bool _starting = false;
  bool _closed = false;
  bool _offerBusy = false;
  int _progressSequence = 0;

  bool get isRunning => _server != null && !_closed;
  ReceiverSession? get session => _session;
  bool get _invitationValid =>
      _session != null && DateTime.now().isBefore(_session!.expiresAt);

  Future<ReceiverSession> start({
    InternetAddress? bindAddress,
    List<String>? advertisedAddresses,
  }) async {
    if (_starting || _server != null || _closed) {
      throw const TransferException(
        'Create a new receiver to start another session.',
      );
    }
    _starting = true;
    try {
      final addresses = advertisedAddresses ?? await localIpv4Addresses();
      if (addresses.isEmpty ||
          addresses.any(
            (host) => !isLocalIpv4(host, allowLoopback: allowLoopback),
          )) {
        throw const TransferException(
          'No supported Wi-Fi address was found. Connect to a private IPv4 '
          'Wi-Fi or hotspot, then try again.',
        );
      }
      final identity = await identityFactory();
      if (_closed) {
        throw const TransferCancelled();
      }
      await storageRoot.create(recursive: true);
      await _removeOldStaging();
      final context = SecurityContext(withTrustedRoots: false)
        ..useCertificateChainBytes(utf8.encode(identity.certificatePem))
        ..usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));
      final server = await HttpServer.bindSecure(
        bindAddress ?? InternetAddress.anyIPv4,
        0,
        context,
        backlog: 16,
      );
      if (_closed) {
        await server.close(force: true);
        throw const TransferCancelled();
      }
      server.autoCompress = false;
      server.idleTimeout = idleTimeout;
      _server = server;
      final session = ReceiverSession(
        addresses: addresses,
        port: server.port,
        token: randomToken(),
        fingerprint: identity.fingerprint,
        expiresAt: DateTime.now().add(inviteLifetime),
        allowLoopback: allowLoopback,
      );
      _session = session;
      server.listen(
        (request) => unawaited(_handle(request)),
        onError: (Object error) {
          // A failed TLS connection must not terminate the whole listener.
        },
        cancelOnError: false,
      );
      _inviteTimer = Timer(inviteLifetime, () {
        if (_approval != null && !_approval!.isCompleted) {
          _approval!.complete(false);
        }
        _stopIfExpired();
      });
      _emit(
        const TransferProgress(
          phase: TransferPhase.waiting,
          message: 'Waiting for a sender. Every batch needs your approval.',
        ),
      );
      return session;
    } finally {
      _starting = false;
    }
  }

  Future<void> _removeOldStaging() async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    await for (final entity in storageRoot.list(followLinks: false)) {
      final name = entity.uri.pathSegments
          .where((part) => part.isNotEmpty)
          .last;
      if (entity is Directory &&
          RegExp(r'^\.incoming-sb1-[a-f0-9]{32}-[A-Za-z0-9]+$')
              .hasMatch(name)) {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete(recursive: true);
        }
      }
    }
  }

  void _emit(TransferProgress progress) =>
      onProgress?.call(progress.copyWith(sequence: ++_progressSequence));

  void _emitOffer(
    IncomingOffer offer,
    String progressId,
    TransferPhase phase,
    String message,
  ) {
    _emit(
      TransferProgress(
        phase: phase,
        message: message,
        transferId: offer.id,
        attemptId: progressId,
        manifest: offer.files,
        totalBytes: offer.totalBytes,
        totalFiles: offer.files.length,
      ),
    );
  }

  void _emitBatch(_ReceivingBatch batch, TransferProgress progress) {
    final index = batch.currentFileIndex;
    final file = index == null ? null : batch.offer.files[index];
    _emit(
      progress.copyWith(
        transferId: batch.offer.id,
        attemptId: batch.progressId,
        manifest: batch.offer.files,
        totalBytes: batch.offer.totalBytes,
        processedBytes: batch.bytesReceived,
        totalFiles: batch.offer.files.length,
        completedFiles: batch.digests.length,
        currentFileIndex: index,
        currentFileBytes: index == null ? null : batch.currentFileBytes,
        currentFileTotalBytes: file?.size,
        fileName: file?.name,
        verifiedFiles: batch.verifiedFiles,
        commitStarted: batch.committing || batch.committed,
      ),
    );
  }

  void _stopIfExpired() {
    if (isRunning && !_invitationValid && _batch == null && !_offerBusy) {
      unawaited(stop(reason: 'The pairing code expired. Start a new session.'));
    }
  }

  bool _authorized(HttpRequest request, String token) => secretEquals(
    request.headers.value(HttpHeaders.authorizationHeader) ?? '',
    'Bearer $token',
  );

  Future<void> _handle(HttpRequest request) async {
    _requests.add(request);
    unawaited(
      request.response.done.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {},
      ),
    );
    try {
      if (!isRunning) {
        throw const _HttpFailure(503, 'The receiver has stopped.');
      }
      final remote = request.connectionInfo?.remoteAddress.address ?? '';
      if (!isLocalIpv4(remote, allowLoopback: allowLoopback) ||
          request.headers.value('origin') != null ||
          request.uri.hasQuery) {
        throw const _HttpFailure(
          403,
          'Only native local-network requests are accepted.',
        );
      }
      final parts = request.uri.pathSegments;
      if (request.method == 'POST' && request.uri.path == '/v1/offer') {
        await _handleOffer(request, remote);
        return;
      }
      if (parts.length == 3 &&
          parts[0] == 'v1' &&
          parts[1] == 'status' &&
          request.method == 'GET') {
        final receipt = _lastReceipt;
        if (receipt == null ||
            receipt.id != parts[2] ||
            !_authorized(request, _lastReceiptToken ?? '')) {
          throw const _HttpFailure(404, 'No completed receipt is available.');
        }
        await _reply(request, 200, receipt.toJson());
        return;
      }
      final isUpload =
          parts.length == 4 &&
          parts[0] == 'v1' &&
          parts[1] == 'files' &&
          request.method == 'PUT';
      final isCommit =
          parts.length == 3 &&
          parts[0] == 'v1' &&
          parts[1] == 'commit' &&
          request.method == 'POST';
      final isCancel =
          parts.length == 3 &&
          parts[0] == 'v1' &&
          parts[1] == 'transfers' &&
          request.method == 'DELETE';
      if (!isUpload && !isCommit && !isCancel) {
        throw const _HttpFailure(404, 'Unknown endpoint.');
      }
      final batch = _batch;
      if (batch == null ||
          batch.offer.id != parts[2] ||
          !_authorized(request, batch.token)) {
        throw const _HttpFailure(401, 'This transfer is not authorized.');
      }
      if (batch.canceled) {
        throw const _HttpFailure(410, 'This transfer has ended.');
      }
      if (isUpload) {
        await _handleUpload(request, batch, parts[3]);
      } else if (isCommit) {
        await _handleCommit(request, batch);
      } else {
        await _discardBatch(batch);
        _emitBatch(
          batch,
          TransferProgress(
            phase: TransferPhase.canceled,
            message: batch.cleanupSucceeded
                ? 'Sender canceled. Uncommitted files were discarded.'
                : 'Sender canceled, but temporary-file cleanup needs attention.',
          ),
        );
        await _reply(request, 200, <String, Object>{
          'canceled': true,
          'cleanupComplete': batch.cleanupSucceeded,
        });
      }
    } on _HttpFailure catch (error) {
      await _reply(request, error.status, <String, Object>{
        'error': error.message,
      });
    } on TransferException catch (error) {
      await _reply(request, 422, <String, Object>{'error': error.message});
    } on TimeoutException {
      await _reply(request, 408, <String, Object>{
        'error': 'The request timed out.',
      });
    } catch (_) {
      await _reply(request, 500, <String, Object>{
        'error': 'Transfer failed. Check the connection and available storage.',
      });
    } finally {
      _requests.remove(request);
    }
  }

  Future<void> _handleOffer(HttpRequest request, String remote) async {
    if (!_authorized(request, _session!.token)) {
      throw const _HttpFailure(
        401,
        'The pairing code is not valid for this receiver.',
      );
    }
    if (!_invitationValid) {
      throw const _HttpFailure(410, 'The pairing code has expired.');
    }
    if (_offerBusy || _batch != null) {
      throw const _HttpFailure(
        409,
        'The receiver is busy with another request.',
      );
    }
    if (request.headers.contentType?.mimeType != 'application/json' ||
        request.contentLength > TransferLimits.maxMetadataBytes) {
      throw const _HttpFailure(400, 'Invalid offer content.');
    }
    _offerBusy = true;
    IncomingOffer? progressOffer;
    String? progressAttempt;
    var decisionEnded = false;
    try {
      final offer = IncomingOffer.fromJson(
        await readBoundedJson(request),
        remoteAddress: remote,
      );
      if (!isRunning || !_invitationValid) {
        throw const _HttpFailure(410, 'The receiving session has ended.');
      }
      final progressId = randomTransferId();
      progressOffer = offer;
      progressAttempt = progressId;
      _emitOffer(
        offer,
        progressId,
        TransferPhase.awaitingApproval,
        'An incoming batch is waiting for your decision.',
      );
      final decision = Completer<bool>();
      _approval = decision;
      Future<bool>.sync(() => onOffer(offer)).then(
        (accepted) {
          if (!decision.isCompleted) {
            decision.complete(accepted);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!decision.isCompleted) {
            decision.complete(false);
          }
        },
      );
      final accepted = await decision.future.timeout(
        approvalTimeout,
        onTimeout: () {
          if (!decision.isCompleted) {
            decision.complete(false);
          }
          return false;
        },
      );
      _approval = null;
      if (!accepted || !isRunning || !_invitationValid) {
        decisionEnded = true;
        _emitOffer(
          offer,
          progressId,
          TransferPhase.rejected,
          'The request was declined, expired, or closed.',
        );
        throw const _HttpFailure(
          403,
          'The receiver declined the request or it expired.',
        );
      }
      _emitOffer(
        offer,
        progressId,
        TransferPhase.approved,
        'Receiver approval granted.',
      );
      _emitOffer(
        offer,
        progressId,
        TransferPhase.preparing,
        'Preparing private staging storage.',
      );
      final directory = await storageRoot.createTemp(
        '.incoming-sb1-${randomTransferId()}-',
      );
      if (!isRunning) {
        await directory.delete(recursive: true);
        throw const _HttpFailure(410, 'The receiver has stopped.');
      }
      final batch = _ReceivingBatch(
        offer: offer,
        token: randomToken(),
        directory: directory,
        progressId: progressId,
      );
      _batch = batch;
      _armBatchIdleTimer(batch);
      batch.timer = Timer(batchTimeout, () {
        unawaited(
          _discardBatch(batch).then((_) {
            _emitBatch(
              batch,
              const TransferProgress(
                phase: TransferPhase.failed,
                message: 'Transfer deadline exceeded. Start again.',
              ),
            );
          }),
        );
      });
      _emitBatch(
        batch,
        TransferProgress(
          phase: TransferPhase.receiving,
          message: 'Approved. Waiting for file bytes.',
          totalBytes: offer.totalBytes,
          totalFiles: offer.files.length,
        ),
      );
      await _reply(request, 200, <String, Object>{
        'id': offer.id,
        'uploadToken': batch.token,
      });
    } catch (_) {
      if (!decisionEnded &&
          progressOffer != null &&
          progressAttempt != null &&
          _batch == null &&
          isRunning) {
        _emitOffer(
          progressOffer,
          progressAttempt,
          TransferPhase.failed,
          'The receiving batch could not be prepared. Check available storage.',
        );
      }
      rethrow;
    } finally {
      _offerBusy = false;
      _approval = null;
      _stopIfExpired();
    }
  }

  void _armBatchIdleTimer(_ReceivingBatch batch) {
    batch.idleTimer?.cancel();
    batch.idleTimer = Timer(idleTimeout, () {
      unawaited(
        _discardBatch(batch).then((_) {
          if (batch.cleanupSucceeded && !_closed) {
            _emitBatch(
              batch,
              const TransferProgress(
                phase: TransferPhase.failed,
                message: 'No transfer data arrived in time. Start again.',
              ),
            );
          }
        }),
      );
    });
  }

  Future<void> _handleUpload(
    HttpRequest request,
    _ReceivingBatch batch,
    String fileId,
  ) async {
    if (batch.uploading || batch.committing) {
      throw const _HttpFailure(409, 'Only one file can be uploaded at a time.');
    }
    final matches = batch.offer.files.where((file) => file.id == fileId);
    if (matches.isEmpty || batch.digests.containsKey(fileId)) {
      throw const _HttpFailure(
        409,
        'This file is unknown or already uploaded.',
      );
    }
    final file = matches.first;
    if (request.contentLength != file.size ||
        request.headers.contentType?.mimeType != 'application/octet-stream' ||
        request.headers.value(HttpHeaders.contentEncodingHeader) != null) {
      throw const _HttpFailure(
        400,
        'The upload length or content type is invalid.',
      );
    }
    batch.idleTimer?.cancel();
    batch.uploading = true;
    batch.currentFileIndex = batch.offer.files.indexOf(file);
    batch.currentFileBytes = 0;
    batch.uploadRequest = request;
    final io = Completer<void>();
    batch.ioDone = io.future;
    RandomAccessFile? output;
    final digestOutput = _DigestOutput();
    final digestInput = sha256.startChunkedConversion(digestOutput);
    var failed = true;
    var digestClosed = false;
    var count = 0;
    try {
      _emitBatch(
        batch,
        const TransferProgress(
          phase: TransferPhase.preparing,
          message: 'Opening the receiving file.',
        ),
      );
      output = await File('${batch.directory.path}/${file.id}.part')
          .open(mode: FileMode.write);
      _emitBatch(
        batch,
        const TransferProgress(
          phase: TransferPhase.receiving,
          message: 'Receiving encrypted file bytes.',
        ),
      );
      await for (final chunk in request.timeout(idleTimeout)) {
        if (batch.canceled || !isRunning) {
          throw const TransferCancelled();
        }
        count += chunk.length;
        if (count > file.size) {
          throw const TransferException(
            'The sender exceeded the approved file size.',
          );
        }
        await output.writeFrom(chunk);
        digestInput.add(chunk);
        batch.bytesReceived += chunk.length;
        batch.currentFileBytes = count;
        _emitBatch(
          batch,
          TransferProgress(
            phase: TransferPhase.receiving,
            message: 'Receiving encrypted file bytes.',
            totalBytes: batch.offer.totalBytes,
            processedBytes: batch.bytesReceived,
            totalFiles: batch.offer.files.length,
            completedFiles: batch.digests.length,
            fileName: file.name,
          ),
        );
      }
      if (batch.canceled || !isRunning || count != file.size) {
        throw const TransferException(
          'The file ended before all approved bytes arrived.',
        );
      }
      await output.flush();
      await output.close();
      output = null;
      digestInput.close();
      digestClosed = true;
      final digest = digestOutput.value!.toString();
      batch.digests[file.id] = digest;
      _emitBatch(
        batch,
        const TransferProgress(
          phase: TransferPhase.receiving,
          message: 'File staged. Final batch verification is still required.',
        ),
      );
      _armBatchIdleTimer(batch);
      failed = false;
      await _reply(request, 200, <String, Object>{
        'id': file.id,
        'size': count,
        'sha256': digest,
      });
    } finally {
      if (output != null) {
        try {
          await output.close();
        } catch (_) {}
      }
      if (!digestClosed) {
        digestInput.close();
      }
      batch.uploading = false;
      batch.uploadRequest = null;
      io.complete();
      if (failed) {
        await _discardBatch(batch);
        if (!_closed && batch.cleanupSucceeded) {
          _emitBatch(
            batch,
            const TransferProgress(
              phase: TransferPhase.failed,
              message: 'The upload stopped. Uncommitted files were discarded.',
            ),
          );
        }
      }
    }
  }

  Future<void> _handleCommit(HttpRequest request, _ReceivingBatch batch) async {
    if (batch.uploading ||
        batch.committing ||
        batch.digests.length != batch.offer.files.length) {
      throw const _HttpFailure(
        409,
        'All files must finish uploading before commit.',
      );
    }
    if (request.headers.contentType?.mimeType != 'application/json') {
      throw const _HttpFailure(400, 'Invalid commit content.');
    }
    batch.idleTimer?.cancel();
    batch.committing = true;
    final io = Completer<void>();
    batch.ioDone = io.future;
    var success = false;
    try {
      final data = await readBoundedJson(request);
      final hashes = data['sha256'];
      if (hashes is! Map<String, dynamic> ||
          hashes.length != batch.digests.length) {
        throw const TransferException('The final checksum list is invalid.');
      }
      _emitBatch(
        batch,
        const TransferProgress(
          phase: TransferPhase.verifying,
          message: 'Comparing the sender and receiver SHA-256 values.',
        ),
      );
      for (final file in batch.offer.files) {
        if (hashes[file.id] is! String ||
            !secretEquals(hashes[file.id] as String, batch.digests[file.id]!)) {
          throw const TransferException(
            'A file checksum did not match. Nothing was committed.',
          );
        }
        batch.verifiedFiles += 1;
        _emitBatch(
          batch,
          const TransferProgress(
            phase: TransferPhase.verifying,
            message: 'Checking file hashes before saving the complete batch.',
          ),
        );
      }
      if (batch.canceled || !isRunning) {
        throw const TransferCancelled();
      }
      _emitBatch(
        batch,
        TransferProgress(
          phase: TransferPhase.verifying,
          message: 'Checksums match. Saving the complete batch.',
          totalBytes: batch.offer.totalBytes,
          processedBytes: batch.bytesReceived,
          totalFiles: batch.offer.files.length,
          completedFiles: batch.offer.files.length,
        ),
      );
      final destination = '${storageRoot.path}/received-${randomTransferId()}';
      if (await Directory(destination).exists()) {
        throw const TransferException(
          'Choose a new transfer session and try again.',
        );
      }
      final received = <ReceivedFile>[];
      for (var index = 0; index < batch.offer.files.length; index += 1) {
        final file = batch.offer.files[index];
        final savedName =
            '${(index + 1).toString().padLeft(3, '0')}_${file.name}';
        await File('${batch.directory.path}/${file.id}.part')
            .rename('${batch.directory.path}/$savedName');
        received.add(
          ReceivedFile(
            id: file.id,
            name: file.name,
            size: file.size,
            digest: batch.digests[file.id]!,
            localPath: '$destination/$savedName',
          ),
        );
      }
      final receipt = TransferReceipt(
        id: batch.offer.id,
        senderName: batch.offer.senderName,
        completedAt: DateTime.now().toUtc(),
        files: received,
      );
      await File('${batch.directory.path}/transfer.json')
          .writeAsString(jsonEncode(receipt.toJson()), flush: true);
      await batch.directory.rename(destination);
      batch.committed = true;
      success = true;
      _lastReceipt = receipt;
      _lastReceiptToken = batch.token;
      _emitBatch(
        batch,
        TransferProgress(
          phase: TransferPhase.completed,
          message: 'Files saved. SHA-256 checksums match the sender.',
          receipt: receipt,
          totalBytes: receipt.totalBytes,
          processedBytes: receipt.totalBytes,
          totalFiles: receipt.files.length,
          completedFiles: receipt.files.length,
        ),
      );
      onReceived?.call(receipt);
      await _reply(request, 200, receipt.toJson());
    } finally {
      batch.committing = false;
      io.complete();
      if (!success) {
        await _discardBatch(batch);
        if (!_closed && batch.cleanupSucceeded) {
          _emitBatch(
            batch,
            const TransferProgress(
              phase: TransferPhase.failed,
              message:
                  'Verification or saving failed. The batch was not committed.',
            ),
          );
        }
      } else {
        batch.timer?.cancel();
        batch.idleTimer?.cancel();
        if (identical(_batch, batch)) {
          _batch = null;
        }
        _stopIfExpired();
      }
    }
  }

  Future<void> _discardBatch(_ReceivingBatch batch) {
    return batch.cleanup ??= _cleanBatch(batch);
  }

  Future<void> _cleanBatch(_ReceivingBatch batch) async {
    batch.canceled = true;
    batch.timer?.cancel();
    batch.idleTimer?.cancel();
    final request = batch.uploadRequest;
    if (request != null) {
      await _destroyRequest(request);
    }
    await batch.ioDone;
    if (!batch.committed) {
      try {
        if (await batch.directory.exists()) {
          await batch.directory.delete(recursive: true);
        }
      } on FileSystemException {
        batch.cleanupSucceeded = false;
        _emitBatch(
          batch,
          const TransferProgress(
            phase: TransferPhase.failed,
            message: 'Some temporary files could not be removed. Check device storage.',
          ),
        );
      }
    }
    if (identical(_batch, batch)) {
      _batch = null;
    }
    _stopIfExpired();
  }

  Future<void> stop({
    String reason = 'Receiving stopped. Start again for a new code.',
  }) {
    return _stopFuture ??= _stop(reason);
  }

  Future<void> _stop(String reason) async {
    _closed = true;
    _inviteTimer?.cancel();
    if (_approval != null && !_approval!.isCompleted) {
      _approval!.complete(false);
    }
    final server = _server;
    _server = null;
    final closing = server?.close(force: true);
    for (final request in _requests.toList()) {
      await _destroyRequest(request);
    }
    final batch = _batch;
    if (batch != null) {
      await _discardBatch(batch);
    }
    if (closing != null) {
      await closing;
    }
    _lastReceiptToken = null;
    onStopped?.call(reason);
  }

  Future<void> _reply(
    HttpRequest request,
    int status,
    Map<String, Object> data,
  ) async {
    try {
      final bytes = utf8.encode(jsonEncode(data));
      final response = request.response;
      response.statusCode = status;
      response.headers.contentType = ContentType.json;
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.headers.set('x-content-type-options', 'nosniff');
      if (status >= 400) {
        response.persistentConnection = false;
      }
      response.contentLength = bytes.length;
      response.add(bytes);
      await response.close();
    } catch (_) {
      await _destroyRequest(request);
    }
  }

  Future<void> _destroyRequest(HttpRequest request) async {
    try {
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.destroy();
    } catch (_) {
      // The socket may already have been closed by the peer or server.
    }
  }
}

class LocalSender {
  LocalSender({
    this.connectionTimeout = const Duration(seconds: 10),
    this.approvalTimeout = const Duration(seconds: 75),
    this.idleTimeout = const Duration(seconds: 30),
    this.batchTimeout = const Duration(minutes: 30),
  });

  final Duration connectionTimeout;
  final Duration approvalTimeout;
  final Duration idleTimeout;
  final Duration batchTimeout;

  HttpClient? _client;
  bool _sending = false;
  bool _canceled = false;
  HttpClientRequest? _activeRequest;
  StreamIterator<List<int>>? _sourceIterator;

  void cancel() {
    _canceled = true;
    try {
      _activeRequest?.abort(const TransferCancelled());
    } catch (_) {}
    _client?.close(force: true);
    final source = _sourceIterator;
    if (source != null) {
      unawaited(
        source.cancel().then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {},
        ),
      );
    }
  }

  void _checkCanceled() {
    if (_canceled) {
      throw const TransferCancelled();
    }
  }

  Future<TransferReceipt> send({
    required PairingCode code,
    required List<ShareFile> files,
    required String senderName,
    void Function(TransferProgress progress)? onProgress,
  }) async {
    if (_sending) {
      throw const TransferException('This sender is already busy.');
    }
    final selected = List<ShareFile>.unmodifiable(files);
    final offer = createOutgoingOffer(selected, senderName);
    _sending = true;
    _canceled = false;
    final client = createPinnedClient(
      code,
      connectionTimeout: connectionTimeout,
    );
    _client = client;
    String? uploadToken;
    var commitStarted = false;
    final digests = <String, String>{};
    final deadline = Timer(batchTimeout, cancel);
    var sentBytes = 0;
    var sequence = 0;
    TransferProgress? latest;
    void emitProgress(TransferProgress progress) {
      final enriched = progress.copyWith(
        transferId: offer.id,
        attemptId: offer.id,
        sequence: ++sequence,
        manifest: offer.files,
        totalBytes: offer.totalBytes,
        processedBytes: sentBytes,
        totalFiles: offer.files.length,
        completedFiles: digests.length,
        verifiedFiles: digests.length,
        currentFileIndex: progress.currentFileIndex ?? latest?.currentFileIndex,
        currentFileBytes: progress.currentFileBytes ?? latest?.currentFileBytes,
        currentFileTotalBytes:
            progress.currentFileTotalBytes ?? latest?.currentFileTotalBytes,
        fileName: progress.fileName ?? latest?.fileName,
        commitStarted: commitStarted,
      );
      latest = enriched;
      onProgress?.call(enriched);
    }

    try {
      emitProgress(
        TransferProgress(
          phase: TransferPhase.connecting,
          message: 'Checking the receiver certificate.',
          totalBytes: offer.totalBytes,
          totalFiles: offer.files.length,
        ),
      );
      final request = await _open(
        client,
        code,
        'POST',
        '/v1/offer',
        code.token,
      );
      request.headers.contentType = ContentType.json;
      final metadata = utf8.encode(jsonEncode(offer.toJson()));
      if (metadata.length > TransferLimits.maxMetadataBytes) {
        throw const TransferException(
          'Choose fewer files; the metadata is too large.',
        );
      }
      request.contentLength = metadata.length;
      request.add(metadata);
      emitProgress(
        TransferProgress(
          phase: TransferPhase.awaitingApproval,
          message: 'Ask the receiver to approve this batch within 60 seconds.',
          totalBytes: offer.totalBytes,
          totalFiles: offer.files.length,
        ),
      );
      final accepted = await _response(request, approvalTimeout);
      if (accepted['id'] != offer.id ||
          accepted['uploadToken'] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{43}$')
              .hasMatch(accepted['uploadToken'] as String)) {
        throw const TransferException(
          'The receiver returned an invalid approval.',
        );
      }
      uploadToken = accepted['uploadToken'] as String;
      _checkCanceled();
      emitProgress(
        const TransferProgress(
          phase: TransferPhase.approved,
          message: 'The receiver approved this batch.',
        ),
      );
      for (var index = 0; index < selected.length; index += 1) {
        final source = selected[index];
        final descriptor = offer.files[index];
        emitProgress(
          TransferProgress(
            phase: TransferPhase.preparing,
            message: 'Preparing the next selected file.',
            currentFileIndex: index,
            currentFileBytes: 0,
            currentFileTotalBytes: descriptor.size,
            fileName: descriptor.name,
          ),
        );
        final upload = await _open(
          client,
          code,
          'PUT',
          '/v1/files/${offer.id}/${descriptor.id}',
          uploadToken,
        );
        upload.headers.contentType = ContentType.binary;
        upload.contentLength = descriptor.size;
        final digestOutput = _DigestOutput();
        final digestInput = sha256.startChunkedConversion(digestOutput);
        var digestClosed = false;
        var fileBytes = 0;
        final iterator = StreamIterator<List<int>>(
          source.openRead().timeout(idleTimeout),
        );
        _sourceIterator = iterator;
        upload.bufferOutput = false;
        emitProgress(
          TransferProgress(
            phase: TransferPhase.sending,
            message: 'Streaming encrypted file bytes.',
            currentFileIndex: index,
            currentFileBytes: 0,
            currentFileTotalBytes: descriptor.size,
            fileName: descriptor.name,
          ),
        );
        try {
          while (await iterator.moveNext()) {
            _checkCanceled();
            final chunk = iterator.current;
            fileBytes += chunk.length;
            if (fileBytes > descriptor.size) {
              throw const TransferException(
                'A selected file changed size. Select it again.',
              );
            }
            digestInput.add(chunk);
            upload.add(chunk);
            await upload.flush().timeout(idleTimeout);
            _checkCanceled();
            sentBytes += chunk.length;
            emitProgress(
              TransferProgress(
                phase: TransferPhase.sending,
                message: 'Streaming encrypted bytes. Waiting for final confirmation.',
                totalBytes: offer.totalBytes,
                processedBytes: sentBytes,
                totalFiles: offer.files.length,
                completedFiles: index,
                currentFileIndex: index,
                currentFileBytes: fileBytes,
                currentFileTotalBytes: descriptor.size,
                fileName: descriptor.name,
              ),
            );
          }
          _checkCanceled();
          if (fileBytes != descriptor.size) {
            throw const TransferException(
              'A selected file could not be read completely. Select it again.',
            );
          }
          digestInput.close();
          digestClosed = true;
          final digest = digestOutput.value!.toString();
          final result = await _response(upload, idleTimeout);
          if (result['id'] != descriptor.id ||
              result['size'] != descriptor.size ||
              result['sha256'] is! String ||
              !secretEquals(result['sha256'] as String, digest)) {
            throw const TransferException(
              'The receiver checksum did not match. The batch was not committed.',
            );
          }
          digests[descriptor.id] = digest;
          emitProgress(
            TransferProgress(
              phase: TransferPhase.sending,
              message: 'Staged file checksum matched. Final receipt is still required.',
              currentFileIndex: index,
              currentFileBytes: fileBytes,
              currentFileTotalBytes: descriptor.size,
              fileName: descriptor.name,
            ),
          );
        } finally {
          try {
            await iterator.cancel().timeout(idleTimeout);
          } catch (_) {}
          if (identical(_sourceIterator, iterator)) {
            _sourceIterator = null;
          }
          if (!digestClosed) {
            digestInput.close();
          }
        }
      }
      _checkCanceled();
      emitProgress(
        TransferProgress(
          phase: TransferPhase.verifying,
          message: 'Bytes uploaded. Asking the receiver to verify and save.',
          totalBytes: offer.totalBytes,
          processedBytes: sentBytes,
          totalFiles: offer.files.length,
          completedFiles: offer.files.length,
        ),
      );
      final commit = await _open(
        client,
        code,
        'POST',
        '/v1/commit/${offer.id}',
        uploadToken,
      );
      commit.headers.contentType = ContentType.json;
      final body = utf8.encode(jsonEncode(<String, Object>{'sha256': digests}));
      commit.contentLength = body.length;
      _checkCanceled();
      // Conservatively mark the commit boundary before queuing its body.
      commitStarted = true;
      emitProgress(
        const TransferProgress(
          phase: TransferPhase.verifying,
          message:
              'Commit requested. Waiting for a validated delivery receipt.',
        ),
      );
      commit.add(body);
      _checkCanceled();
      commitStarted = true;
      final receipt = _verifyReceipt(
        await _response(commit, idleTimeout),
        offer,
        digests,
      );
      _emitCompleted(receipt, emitProgress);
      return receipt;
    } catch (error) {
      _activeRequest?.abort();
      client.close(force: true);
      if (commitStarted && uploadToken != null) {
        final recovered = await _recoverReceipt(
          code,
          uploadToken,
          offer,
          digests,
        );
        if (recovered != null) {
          _emitCompleted(recovered, emitProgress);
          return recovered;
        }
        throw const TransferException(
          'The final confirmation was lost. The receiver may already have saved '
          'the files. Check that device before sending again.',
          outcomeUncertain: true,
        );
      }
      if (uploadToken != null) {
        await _cancelRemote(code, uploadToken, offer.id);
      }
      if (_canceled) {
        throw const TransferCancelled();
      }
      if (error is TransferException) {
        rethrow;
      }
      if (error is HandshakeException) {
        throw const TransferException(
          'The receiver certificate did not match. Copy a fresh code directly from the receiver.',
        );
      }
      if (error is TimeoutException) {
        throw const TransferException(
          'The connection timed out. Keep both apps open and try again.',
        );
      }
      throw const TransferException(
        'Could not finish sending. Check Wi-Fi, storage, and the selected files.',
      );
    } finally {
      deadline.cancel();
      client.close(force: true);
      _client = null;
      _activeRequest = null;
      _sending = false;
    }
  }

  Future<HttpClientRequest> _open(
    HttpClient client,
    PairingCode code,
    String method,
    String path,
    String token,
  ) async {
    _checkCanceled();
    final request = await client
        .openUrl(method, code.endpoint(path))
        .timeout(connectionTimeout);
    _activeRequest = request;
    unawaited(
      request.done.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {},
      ),
    );
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    _checkCanceled();
    return request;
  }

  Future<Map<String, dynamic>> _response(
    HttpClientRequest request,
    Duration timeout,
  ) async {
    final response = await request.close().timeout(timeout);
    final data = await readBoundedJson(response, timeout: idleTimeout);
    if (response.statusCode != 200) {
      final message = data['error'];
      throw TransferException(
        message is String && message.length <= 240
            ? message
            : 'The receiver rejected this operation.',
      );
    }
    return data;
  }

  TransferReceipt _verifyReceipt(
    Map<String, dynamic> data,
    IncomingOffer offer,
    Map<String, String> digests,
  ) {
    final receipt = TransferReceipt.fromJson(data);
    if (receipt.id != offer.id ||
        receipt.files.length != offer.files.length ||
        receipt.files.map((file) => file.id).toSet().length !=
            offer.files.length) {
      throw const TransferException(
        'The final receipt does not match this batch.',
      );
    }
    for (final expected in offer.files) {
      final matches = receipt.files.where((file) => file.id == expected.id);
      if (matches.isEmpty ||
          matches.first.size != expected.size ||
          matches.first.name != expected.name ||
          !secretEquals(matches.first.digest, digests[expected.id] ?? '')) {
        throw const TransferException(
          'The final receipt checksum does not match.',
        );
      }
    }
    return receipt;
  }

  void _emitCompleted(
    TransferReceipt receipt,
    void Function(TransferProgress)? callback,
  ) {
    callback?.call(
      TransferProgress(
        phase: TransferPhase.completed,
        message: 'Receiver confirmed every file is saved and verified.',
        receipt: receipt,
        totalBytes: receipt.totalBytes,
        processedBytes: receipt.totalBytes,
        totalFiles: receipt.files.length,
        completedFiles: receipt.files.length,
      ),
    );
  }

  Future<TransferReceipt?> _recoverReceipt(
    PairingCode code,
    String token,
    IncomingOffer offer,
    Map<String, String> digests,
  ) async {
    final client = createPinnedClient(
      code,
      connectionTimeout: const Duration(seconds: 3),
    );
    try {
      final request = await client
          .getUrl(code.endpoint('/v1/status/${offer.id}'))
          .timeout(const Duration(seconds: 3));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      return _verifyReceipt(
        await _response(request, const Duration(seconds: 3)),
        offer,
        digests,
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _cancelRemote(PairingCode code, String token, String id) async {
    final client = createPinnedClient(
      code,
      connectionTimeout: const Duration(seconds: 3),
    );
    try {
      final request = await client
          .deleteUrl(code.endpoint('/v1/transfers/$id'))
          .timeout(const Duration(seconds: 3));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      await response.drain<void>().timeout(const Duration(seconds: 3));
    } catch (_) {
      // The receiver also removes an interrupted upload and expires abandoned batches.
    } finally {
      client.close(force: true);
    }
  }
}
