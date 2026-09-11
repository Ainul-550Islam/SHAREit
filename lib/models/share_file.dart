enum FileCategory { image, video, audio, document, archive, other }

typedef PickShareFiles = Future<FileSelection> Function();

class FileSelection {
  FileSelection({required Iterable<ShareFile> files, this.unavailableCount = 0})
    : files = List<ShareFile>.unmodifiable(files) {
    if (unavailableCount < 0) {
      throw ArgumentError.value(unavailableCount, 'unavailableCount');
    }
  }

  final List<ShareFile> files;
  final int unavailableCount;
}

class ShareFile {
  ShareFile({
    required this.name,
    required this.size,
    required this.sourceUri,
    required this.readStream,
  }) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'A file must have a name.');
    }
    if (size < 0) {
      throw ArgumentError.value(size, 'size', 'File size cannot be negative.');
    }
    if (!sourceUri.hasScheme) {
      throw ArgumentError.value(
        sourceUri,
        'sourceUri',
        'A source URI must include its scheme.',
      );
    }
  }

  final String name;
  final int size;
  final Uri sourceUri;
  final Stream<List<int>> Function() readStream;

  String get id => sourceUri.toString();

  String get formattedSize => formatBytes(size);

  String get extension {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == name.length - 1) {
      return '';
    }
    return name.substring(dotIndex + 1).toLowerCase();
  }

  FileCategory get category => switch (extension) {
    'jpg' ||
    'jpeg' ||
    'png' ||
    'gif' ||
    'webp' ||
    'heic' ||
    'heif' ||
    'bmp' ||
    'avif' ||
    'svg' => FileCategory.image,
    'mp4' ||
    'mov' ||
    'mkv' ||
    'avi' ||
    'webm' ||
    'm4v' ||
    '3gp' => FileCategory.video,
    'mp3' ||
    'wav' ||
    'm4a' ||
    'aac' ||
    'ogg' ||
    'opus' ||
    'flac' ||
    'aiff' => FileCategory.audio,
    'pdf' ||
    'doc' ||
    'docx' ||
    'ppt' ||
    'pptx' ||
    'xls' ||
    'xlsx' ||
    'txt' ||
    'csv' ||
    'md' ||
    'rtf' ||
    'odt' ||
    'epub' => FileCategory.document,
    'zip' ||
    'rar' ||
    '7z' ||
    'tar' ||
    'gz' ||
    'tgz' ||
    'bz2' ||
    'xz' => FileCategory.archive,
    _ => FileCategory.other,
  };

  String get categoryLabel => switch (category) {
    FileCategory.image => 'Image',
    FileCategory.video => 'Video',
    FileCategory.audio => 'Audio',
    FileCategory.document => 'Document',
    FileCategory.archive => 'Archive',
    FileCategory.other => 'File',
  };

  /// Opens a fresh byte stream only when a caller needs the content.
  /// Selection, sizing and removal do not call this method.
  Stream<List<int>> openRead() => readStream();
}

String formatBytes(int bytes) {
  if (bytes < 0) {
    throw ArgumentError.value(bytes, 'bytes', 'Byte count cannot be negative.');
  }
  if (bytes < 1024) {
    return '$bytes B';
  }

  const units = <String>['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB', 'EiB'];
  var value = bytes.toDouble();
  var unitIndex = 0;

  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }

  final decimalPlaces = value == value.truncateToDouble() ? 0 : 1;
  return '${value.toStringAsFixed(decimalPlaces)} ${units[unitIndex]}';
}
