# ShareBondhu — Part 1 (File 1–5)

## সম্পূর্ণ কোড + বাংলা সেটআপ গাইড

Flutter দিয়ে নিজের ব্র্যান্ডের Android ও iPhone file-sharing অ্যাপ তৈরির প্রথম ধাপ। এই অংশ একটি চালানো যায় এমন **file-selection foundation**; এখনো কোনো ফাইল পাঠায় বা গ্রহণ করে না।

## এই Part-এ কাজ করে

- নিজস্ব Home / Files / Guide ইন্টারফেস।
- নেটিভ system picker দিয়ে একাধিক ফাইল নির্বাচন।
- ফাইলের নাম, ধরন, সাইজ ও নির্বাচিত ফাইলের মোট সাইজ দেখা।
- একই source URI/reference পুনরাবৃত্তি হলে বাদ দেওয়া। একই নামের ভিন্ন source URI-র ফাইল রাখা হয়। এটি content-hash দিয়ে duplicate detection নয়।
- ফাইলের reference সরানো এবং নিশ্চিত করার পরে পুরো তালিকা পরিষ্কার করা। মূল ফাইল কখনো মুছে ফেলা হয় না।
- Picker cancellation, unavailable files, permission errors ও repeated taps সামলানো।
- Light/dark theme; তালিকা ও theme choice শুধু চলতি session-এ থাকে।
- ২৮টি model/widget test।

## চালু করুন

এই প্রজেক্ট Flutter **3.47.2** এবং Dart **3.13.2** দিয়ে static analysis ও automated test করা হয়েছে। `pubspec.yaml`-এর সর্বনিম্ন সংস্করণ Flutter 3.47.0 / Dart 3.13.0। `file_picker` 12.2.0 এবং `flutter_lints` 6.0.0 pin করা আছে; `pubspec.lock` রাখা হয়েছে।

Flutter install: https://docs.flutter.dev/install

Android Studio: https://developer.android.com/studio

ZIP খুলে `sharebondhu` ফোল্ডারে terminal খুলুন। Flutter SDK PATH-এ থাকতে হবে।

```bash
flutter --version
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run
```

Android: Android Studio-এর SDK/toolchain প্রস্তুত করুন। নিজের Android ফোনে Developer options ও USB debugging চালু করে কম্পিউটারের debugging অনুমতি দিন, অথবা Android emulator চালান। এই runner-এর জন্য Java 17 বা নতুন compatible JDK দরকার; Java 11 ব্যবহার করবেন না। Android Studio-এর bundled JDK ব্যবহার করা সবচেয়ে সহজ। একাধিক device থাকলে `flutter run`-এর তালিকা থেকে Android device বেছে নিন।

নিজের কম্পিউটারে debug APK তৈরি করতে:

```bash
flutter build apk --debug
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`। এটি development APK, store-ready release নয়। এই বিতরণে কোনো তৈরি APK/IPA নেই।

iPhone: iOS build-এর জন্য Mac, compatible Xcode এবং তার toolchain দরকার। Mac-এ Simulator চালাতে:

```bash
open -a Simulator
flutter devices
flutter run
```

বাস্তব iPhone-এ চালাতে Xcode-এ নিজের signing team সেট করতে হবে। এই generated iOS project-এর deployment target 15.0। Windows/Linux থেকে স্থানীয়ভাবে iOS binary build হবে না।

## সম্পূর্ণ কোড ও ফাইল তালিকা

- `docs/PART_01_FULL_CODE.md`: File 1–5-এর শুরু থেকে শেষ পর্যন্ত সম্পূর্ণ কোড এবং বাংলা নির্দেশনা।
- `docs/FILE_INDEX.md`: স্থায়ী file number ও পরের Part-এ আগের logic রক্ষার নোট।
- `docs/FILE_INVENTORY.txt`: ZIP-এর সব ফাইলের পথ।
- `docs/TEST_RESULTS.txt`: এই পরিবেশের analysis ও test output।
- `docs/part01-preview.png`: Flutter test renderer থেকে UI preview; নির্বাচিত ফাইলগুলো শুধু পরীক্ষার sample metadata।

পাঁচটি নিজস্ব source/test ফাইলের পাশাপাশি ZIP-এ standard Android/iOS runner, configuration, launcher assets, Gradle wrapper ও lockfile আছে। Flutter SDK, package caches, compiled build output এবং machine-specific generated configuration বিতরণে রাখা হয়নি। `flutter pub get` ও `flutter run` প্রয়োজনমতো সেগুলো তৈরি করবে।

## কী এখনো হয়নি

- Local-network discovery, pairing, real sending/receiving, receiver approval, byte progress ও cancellation।
- Received-file storage, transfer history ও background transfer।
- Final launcher icon/name configuration, production signing, store privacy/compliance এবং বিজ্ঞাপন।
- Physical Android/iPhone-এ native file-picker verification বা APK/IPA compilation। এখানে automated tests-এ picker result inject করা হয়েছে; আসল OS picker চালানো হয়নি।

এই Part-এর UI ইংরেজি; গাইড বাংলায়। বাংলা UI পরে যোগ করা যাবে। প্রথম transfer সংস্করণের লক্ষ্য একই Wi-Fi বা device-to-device traffic অনুমোদন করে এমন hotspot। Android-এর Wi-Fi Direct API iPhone-এ একইভাবে পাওয়া যায় না; automatic hotspot setup প্রতিশ্রুত নয়।

ShareBondhu নাম ও `com.sharebondhu.sharebondhu` application ID অস্থায়ী। প্রকাশের আগে brand availability, নিজের unique application ID, launcher branding ও release signing ঠিক করতে হবে। Android release template বর্তমানে debug signing ব্যবহার করে; সেটি প্রকাশ করবেন না।


## এই Part-এর পাঁচটি ফাইল

| File number | সম্পূর্ণ পথ | কাজ |
|---|---|---|
| File 1 | `pubspec.yaml` | SDK, dependencies ও version |
| File 2 | `lib/main.dart` | App entry ও light/dark theme |
| File 3 | `lib/models/share_file.dart` | File model, stream factory ও size formatting |
| File 4 | `lib/screens/home_screen.dart` | সম্পূর্ণ interface, native picker adapter ও selection logic |
| File 5 | `test/widget_test.dart` | ২৮টি সম্পূর্ণ automated test |

এই পাঁচটি authored source/test ফাইলের সম্পূর্ণ কোড নিচে আছে। প্রতিটি code block সেই ফাইলের শুরু থেকে শেষ পর্যন্ত হুবহু দেওয়া হয়েছে। ZIP-এর কোডের সঙ্গে এগুলো মিলিয়ে যাচাই করা হয়েছে। Flutter-এর standard Android/iOS runner ও configuration-ও ZIP-এ সম্পূর্ণ আছে; সেগুলোর তালিকা `docs/FILE_INVENTORY.txt`-এ পাবেন।

### ZIP ব্যবহার না করে নতুন প্রজেক্টে কোড বসাতে চাইলে

শুধু নতুন, খালি working folder-এ এই command চালাবেন। আগে থেকে থাকা কোনো প্রজেক্টের ওপর এই command চালাবেন না। ZIP ব্যবহার করলে এই ধাপ লাগবে না।

```bash
flutter create --empty --platforms=android,ios --org com.sharebondhu --project-name sharebondhu sharebondhu
cd sharebondhu
```

তারপর নিচের পাঁচটি ফাইল একই relative path-এ সম্পূর্ণ লিখুন। `lib/models`, `lib/screens` ও `test` folder না থাকলে তৈরি করুন। নতুন project-এর standard runner files রেখে দিন। এরপর `flutter pub get`, `flutter analyze`, `flutter test` ও `flutter run` চালান। পুনরুৎপাদনযোগ্য একই dependency set পেতে ZIP-এর `pubspec.lock` ব্যবহার করা উত্তম।

## Full Code — কোনো অংশ সংক্ষিপ্ত করা হয়নি

### File 1 — `pubspec.yaml`

SDK, dependencies ও version। সম্পূর্ণ ফাইল:

```yaml
name: sharebondhu
description: "ShareBondhu - nearby file sharing, built step by step."
publish_to: "none"
version: 0.1.0+1

environment:
  sdk: ">=3.13.0 <4.0.0"
  flutter: ">=3.47.0"

dependencies:
  flutter:
    sdk: flutter
  file_picker: 12.2.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: 6.0.0

flutter:
  uses-material-design: true
```

### File 2 — `lib/main.dart`

App entry ও light/dark theme। সম্পূর্ণ ফাইল:

```dart
import 'package:flutter/material.dart';

import 'models/share_file.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShareBondhuApp());
}

class ShareBondhuApp extends StatefulWidget {
  const ShareBondhuApp({super.key, this.pickFiles});

  final PickShareFiles? pickFiles;

  @override
  State<ShareBondhuApp> createState() => _ShareBondhuAppState();
}

class _ShareBondhuAppState extends State<ShareBondhuApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _toggleTheme() {
    final currentlyDark = switch (_themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark,
    };

    setState(() {
      _themeMode = currentlyDark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xFF176B52),
      brightness: brightness,
    );
    final background = isDark
        ? const Color(0xFF101C18)
        : const Color(0xFFF6F8F5);

    final baseTheme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colors,
    );

    return baseTheme.copyWith(
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 88,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.primaryContainer,
        height: 76,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: colors.onSurface,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: baseTheme.textTheme.labelLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: baseTheme.textTheme.labelLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: DividerThemeData(color: colors.outlineVariant),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShareBondhu',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _themeMode,
      home: HomeScreen(
        pickFiles: widget.pickFiles ?? pickDeviceFiles,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}
```

### File 3 — `lib/models/share_file.dart`

File model, stream factory ও size formatting। সম্পূর্ণ ফাইল:

```dart
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
```

### File 4 — `lib/screens/home_screen.dart`

সম্পূর্ণ interface, native picker adapter ও selection logic। সম্পূর্ণ ফাইল:

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/share_file.dart';

Future<FileSelection> pickDeviceFiles() async {
  final pickedFiles = await FilePicker.pickFiles(
    type: FileType.any,
    dialogTitle: 'Choose files for ShareBondhu',
  );
  final files = <ShareFile>[];
  var unavailableCount = 0;

  for (final picked in pickedFiles) {
    try {
      final byteCount = await picked.length();
      files.add(
        ShareFile(
          name: picked.name,
          size: byteCount,
          sourceUri: picked.uri,
          readStream: picked.readAsByteStream,
        ),
      );
    } catch (_) {
      unavailableCount += 1;
    }
  }

  return FileSelection(files: files, unavailableCount: unavailableCount);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.pickFiles,
    required this.onToggleTheme,
  });

  final PickShareFiles pickFiles;
  final VoidCallback onToggleTheme;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<ShareFile> _files = <ShareFile>[];
  int _selectedIndex = 0;
  bool _isPicking = false;
  String? _errorMessage;

  int get _totalSize => _files.fold<int>(0, (sum, file) => sum + file.size);

  String get _selectionSummary {
    final noun = _files.length == 1 ? 'file' : 'files';
    return '${_files.length} $noun · ${formatBytes(_totalSize)}';
  }

  Future<void> _selectFiles() async {
    if (_isPicking) {
      return;
    }
    setState(() {
      _isPicking = true;
      _errorMessage = null;
    });

    try {
      final selection = await widget.pickFiles();
      if (!mounted) {
        return;
      }
      if (selection.files.isEmpty && selection.unavailableCount == 0) {
        return;
      }

      final knownIds = _files.map((file) => file.id).toSet();
      final additions = <ShareFile>[];
      var duplicateCount = 0;

      for (final file in selection.files) {
        if (knownIds.add(file.id)) {
          additions.add(file);
        } else {
          duplicateCount += 1;
        }
      }

      setState(() {
        _files.addAll(additions);
        if (additions.isNotEmpty) {
          _selectedIndex = 1;
        }
      });

      final messages = <String>[];
      if (additions.isNotEmpty) {
        final noun = additions.length == 1 ? 'file' : 'files';
        messages.add('Added ${additions.length} $noun.');
      }
      if (duplicateCount > 0) {
        final noun = duplicateCount == 1 ? 'reference' : 'references';
        messages.add('$duplicateCount duplicate $noun skipped.');
      }
      if (selection.unavailableCount > 0) {
        final count = selection.unavailableCount;
        final noun = count == 1 ? 'file was' : 'files were';
        messages.add('$count $noun unavailable. Save locally and try again.');
      }
      if (messages.isNotEmpty) {
        _showMessage(messages.join(' '));
      }
    } on MissingPluginException {
      _showError(
        'The file picker is not installed in this build. Stop the app, '
        'run flutter pub get, and rebuild it.',
      );
    } on PlatformException catch (error) {
      _showError(
        error.code == 'permission_denied'
            ? 'File access was not allowed. You can try the system picker again.'
            : 'The file picker could not open. Close it and try again.',
      );
    } catch (_) {
      _showError(
        'We could not read that selection. Try choosing locally stored files.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _errorMessage = message;
    });
  }

  void _removeFile(ShareFile file) {
    setState(() {
      _files.removeWhere((item) => item.id == file.id);
    });
    _showMessage('Removed from selection. Your original file is unchanged.');
  }

  Future<void> _clearSelection() async {
    if (_files.isEmpty || _isPicking) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear selection?'),
        content: const Text(
          'This only clears the list in ShareBondhu. '
          'Your original files will not be deleted.',
        ),
        actions: <Widget>[
          TextButton(
            key: const ValueKey('keep-files-button'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep files'),
          ),
          FilledButton(
            key: const ValueKey('confirm-clear-button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear selection'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }
    setState(() {
      _files.clear();
    });
    _showMessage('Selection cleared. Your original files are unchanged.');
  }

  void _changePage(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      key: const ValueKey('main-scaffold'),
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.swap_calls_rounded,
                color: theme.colorScheme.onPrimary,
                size: 27,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'ShareBondhu',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                  Text(
                    'A LITTLE CLOSER',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.8,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            key: const ValueKey('theme-toggle'),
            tooltip: isDark ? 'Switch to light theme' : 'Switch to dark theme',
            onPressed: widget.onToggleTheme,
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: <Widget>[
            if (_errorMessage != null)
              _ErrorNotice(
                message: _errorMessage!,
                onDismiss: () => setState(() => _errorMessage = null),
              ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: switch (_selectedIndex) {
                    0 => _buildHome(context),
                    1 => _buildSelection(context),
                    _ => _buildGuide(context),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _changePage,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            key: ValueKey('nav-home'),
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            key: ValueKey('nav-files'),
            icon: Icon(Icons.folder_copy_outlined),
            selectedIcon: Icon(Icons.folder_copy_rounded),
            label: 'Files',
          ),
          NavigationDestination(
            key: ValueKey('nav-guide'),
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: 'Guide',
          ),
        ],
      ),
    );
  }

  Widget _buildHome(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const PageStorageKey('home-scroll'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: <Widget>[
        _HeroPanel(isPicking: _isPicking, onSelect: _selectFiles),
        const SizedBox(height: 18),
        _SurfacePanel(
          child: Row(
            children: <Widget>[
              Expanded(
                child: _Metric(
                  label: 'FILES SELECTED',
                  value: '${_files.length}',
                  valueKey: const ValueKey('selected-count'),
                  icon: Icons.layers_outlined,
                ),
              ),
              Container(
                width: 1,
                height: 48,
                color: theme.colorScheme.outlineVariant,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: _Metric(
                  label: 'TOTAL SIZE',
                  value: formatBytes(_totalSize),
                  valueKey: const ValueKey('selected-size'),
                  icon: Icons.data_usage_rounded,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Your selection',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('view-selection-button'),
              onPressed: () => _changePage(1),
              child: const Text('View all'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_files.isEmpty)
          const _EmptySelection()
        else
          Column(
            children: _files.take(3).map((file) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _FileTile(file: file, onRemove: () => _removeFile(file)),
              );
            }).toList(),
          ),
        const SizedBox(height: 20),
        _SurfacePanel(
          color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.construction_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'PART 01 · FILE SELECTION',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'No files are sent in this version. '
                'Nearby pairing and real transfers are the next build step.',
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                key: const ValueKey('how-it-works-button'),
                onPressed: () => _changePage(2),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('See the build guide'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSelection(BuildContext context) {
    final theme = Theme.of(context);
    return CustomScrollView(
      key: const PageStorageKey('selection-scroll'),
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Your selection',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  _selectionSummary,
                  key: const ValueKey('selection-summary'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Selected on this device. Nothing has been sent.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    FilledButton.icon(
                      key: const ValueKey('add-files-button'),
                      onPressed: _isPicking ? null : _selectFiles,
                      icon: _isPicking
                          ? const _SmallProgress()
                          : const Icon(Icons.add_rounded),
                      label: Text(_isPicking ? 'Opening picker' : 'Add files'),
                    ),
                    if (_files.isNotEmpty)
                      OutlinedButton.icon(
                        key: const ValueKey('clear-selection-button'),
                        onPressed: _isPicking ? null : _clearSelection,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Clear list'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_files.isEmpty)
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(child: _EmptySelection()),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final file = _files[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _FileTile(
                    file: file,
                    onRemove: () => _removeFile(file),
                  ),
                );
              }, childCount: _files.length),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 30)),
      ],
    );
  }

  Widget _buildGuide(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const PageStorageKey('guide-scroll'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: <Widget>[
        Text(
          'One step at a time.',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'We are building a real nearby-sharing app in small, testable parts.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 22),
        const _GuideStep(
          number: '01',
          title: 'Choose your files',
          description:
              'Use the system picker. Review the names and sizes, '
              'then remove anything you do not want in the list.',
          status: 'READY',
          isReady: true,
        ),
        const _GuideStep(
          number: '02',
          title: 'Connect nearby',
          description:
              'Next we will add sender and receiver pairing on the same '
              'Wi-Fi or a hotspot that allows device-to-device traffic.',
          status: 'NEXT',
        ),
        const _GuideStep(
          number: '03',
          title: 'Approve and transfer',
          description:
              'The receiver will review incoming files. We will add '
              'real byte progress, cancellation and error handling.',
          status: 'LATER',
        ),
        const _GuideStep(
          number: '04',
          title: 'Save and keep track',
          description:
              'We will add received-file storage and transfer history '
              'before preparing store releases or monetization.',
          status: 'LATER',
        ),
        const SizedBox(height: 12),
        _SurfacePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'About this version',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const _InfoLine(
                icon: Icons.lock_outline_rounded,
                text:
                    'Part 1 does not send your files or run a transfer server.',
              ),
              const _InfoLine(
                icon: Icons.restart_alt_rounded,
                text: 'The selection and theme choice reset when the app restarts.',
              ),
              const _InfoLine(
                icon: Icons.verified_user_outlined,
                text: 'Clearing this list never deletes your original files.',
              ),
              const _InfoLine(
                icon: Icons.cloud_outlined,
                text: 'Cloud-only files may need internet to become available.',
              ),
              const _InfoLine(
                icon: Icons.smartphone_rounded,
                text:
                    'We share selected files, not installed iPhone apps. '
                    'iOS does not offer Android-style Wi-Fi Direct.',
              ),
              const SizedBox(height: 4),
              Text(
                'ShareBondhu is a working brand name. Check its availability '
                'before publishing.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.isPicking, required this.onSelect});

  final bool isPicking;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF113F32), Color(0xFF1E7157)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.spa_outlined, size: 18, color: Color(0xFFD5F391)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'A SPACE FOR YOUR FILES',
                  style: TextStyle(
                    color: Color(0xFFD5F391),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'Good things are\nmeant to be shared.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              height: 1.16,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 13),
          const Text(
            'Start with a photo, a video, or a whole collection. '
            'Your selection stays with you.',
            style: TextStyle(
              color: Color(0xFFE0EDE5),
              fontSize: 14,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 23),
          FilledButton.icon(
            key: const ValueKey('select-files-button'),
            onPressed: isPicking ? null : onSelect,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD5F391),
              foregroundColor: const Color(0xFF143D2D),
              disabledBackgroundColor: const Color(0xFF94B989),
              disabledForegroundColor: const Color(0xFF143D2D),
            ),
            icon: isPicking
                ? const _SmallProgress()
                : const Icon(Icons.add_rounded),
            label: Text(isPicking ? 'Opening picker' : 'Select files'),
          ),
        ],
      ),
    );
  }
}

class _SurfacePanel extends StatelessWidget {
  const _SurfacePanel({required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color ?? colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.valueKey,
    required this.icon,
  });

  final String label;
  final String value;
  final Key valueKey;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value,
          key: valueKey,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
      ],
    );
  }
}

class _EmptySelection extends StatelessWidget {
  const _EmptySelection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SurfacePanel(
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: <Widget>[
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.folder_open_rounded,
                size: 29,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'A fresh start',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'No files selected yet.\nChoose something to add to your list.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.file, required this.onRemove});

  final ShareFile file;
  final VoidCallback onRemove;

  IconData get _icon => switch (file.category) {
    FileCategory.image => Icons.image_outlined,
    FileCategory.video => Icons.movie_outlined,
    FileCategory.audio => Icons.music_note_outlined,
    FileCategory.document => Icons.description_outlined,
    FileCategory.archive => Icons.folder_zip_outlined,
    FileCategory.other => Icons.insert_drive_file_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 5, 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 48,
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(_icon, color: colors.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${file.formattedSize} · ${file.categoryLabel}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('remove:${file.id}'),
            tooltip: 'Remove ${file.name} from selection',
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.number,
    required this.title,
    required this.description,
    required this.status,
    this.isReady = false,
  });

  final String number;
  final String title;
  final String description;
  final String status;
  final bool isReady;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _SurfacePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  number,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isReady
                        ? colors.primaryContainer
                        : colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 19, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('selection-error'),
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline_rounded, color: colors.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
          IconButton(
            key: const ValueKey('dismiss-error-button'),
            tooltip: 'Dismiss error',
            onPressed: onDismiss,
            color: colors.onErrorContainer,
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _SmallProgress extends StatelessWidget {
  const _SmallProgress();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: IconTheme.of(context).color,
        semanticsLabel: 'Opening file picker',
      ),
    );
  }
}
```

### File 5 — `test/widget_test.dart`

২৮টি সম্পূর্ণ automated test। সম্পূর্ণ ফাইল:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharebondhu/main.dart';
import 'package:sharebondhu/models/share_file.dart';

ShareFile sampleFile({
  String name = 'notes.pdf',
  String path = '/picked/notes.pdf',
  int size = 1536,
  Stream<List<int>> Function()? openRead,
}) {
  return ShareFile(
    name: name,
    size: size,
    sourceUri: Uri.file(path),
    readStream: openRead ?? () => Stream<List<int>>.value(<int>[1, 2, 3]),
  );
}

Future<void> mountApp(
  WidgetTester tester,
  PickShareFiles picker, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.binding.platformDispatcher.platformBrightnessTestValue =
      Brightness.light;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(
    tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
  );
  await tester.pumpWidget(ShareBondhuApp(pickFiles: picker));
  await tester.pumpAndSettle();
}

Future<void> tapSelect(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('select-files-button'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> tapNavigation(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  group('File model', () {
    test('formats bytes with binary units', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1023), '1023 B');
      expect(formatBytes(1024), '1 KiB');
      expect(formatBytes(1536), '1.5 KiB');
      expect(formatBytes(1048576), '1 MiB');
      expect(formatBytes(9663676416), '9 GiB');
    });

    test('rejects negative byte counts', () {
      expect(() => formatBytes(-1), throwsArgumentError);
      expect(() => sampleFile(size: -1), throwsArgumentError);
    });

    test('classifies file extensions without case sensitivity', () {
      expect(sampleFile(name: 'PHOTO.JPEG').category, FileCategory.image);
      expect(sampleFile(name: 'clip.mp4').category, FileCategory.video);
      expect(sampleFile(name: 'song.flac').category, FileCategory.audio);
      expect(sampleFile(name: 'slides.pptx').category, FileCategory.document);
      expect(sampleFile(name: 'backup.7z').category, FileCategory.archive);
      expect(sampleFile(name: 'package.apk').category, FileCategory.other);
    });

    test('handles dotfiles and names without extensions', () {
      expect(sampleFile(name: '.gitignore').extension, '');
      expect(sampleFile(name: 'README').extension, '');
      expect(sampleFile(name: 'trailing.').extension, '');
      expect(sampleFile(name: 'report.final.PDF').extension, 'pdf');
    });

    test('keeps source identity separate from the display name', () {
      final first = sampleFile(name: 'notes.pdf', path: '/one/notes.pdf');
      final second = sampleFile(name: 'notes.pdf', path: '/two/notes.pdf');
      expect(first.name, second.name);
      expect(first.id, isNot(second.id));
    });

    test('does not read file content until a stream is requested', () async {
      var readCount = 0;
      final file = sampleFile(
        size: 3,
        openRead: () {
          readCount += 1;
          return Stream<List<int>>.value(<int>[1, 2, 3]);
        },
      );
      expect(file.formattedSize, '3 B');
      expect(file.categoryLabel, 'Document');
      expect(readCount, 0);
      final content = await file.openRead().expand((chunk) => chunk).toList();
      expect(content, <int>[1, 2, 3]);
      expect(readCount, 1);
      await file.openRead().drain<void>();
      expect(readCount, 2);
    });

    test('validates filenames and URI schemes', () {
      expect(() => sampleFile(name: '  '), throwsArgumentError);
      expect(
        () => ShareFile(
          name: 'notes.pdf',
          size: 3,
          sourceUri: Uri.parse('relative-file'),
          readStream: () => const Stream<List<int>>.empty(),
        ),
        throwsArgumentError,
      );
    });

    test('freezes selection results and validates unavailable counts', () {
      final original = <ShareFile>[sampleFile()];
      final selection = FileSelection(files: original);
      original.clear();
      expect(selection.files, hasLength(1));
      expect(() => selection.files.clear(), throwsUnsupportedError);
      expect(
        () => FileSelection(files: <ShareFile>[], unavailableCount: -1),
        throwsArgumentError,
      );
    });
  });

  group('Part 1 user interface', () {
    testWidgets('starts with the brand and an empty selection', (tester) async {
      await mountApp(tester, () async => FileSelection(files: <ShareFile>[]));
      expect(find.text('ShareBondhu'), findsOneWidget);
      expect(find.text('Select files'), findsOneWidget);
      expect(find.byKey(const ValueKey('selected-count')), findsOneWidget);
      final count = tester.widget<Text>(
        find.byKey(const ValueKey('selected-count')),
      );
      expect(count.data, '0');
      expect(find.text('Transfer complete'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('selects several files and calculates the total', (
      tester,
    ) async {
      final files = <ShareFile>[
        sampleFile(),
        sampleFile(name: 'photo.jpg', path: '/picked/photo.jpg', size: 512),
      ];
      await mountApp(tester, () async => FileSelection(files: files));
      await tapSelect(tester);
      expect(find.text('notes.pdf'), findsOneWidget);
      expect(find.text('photo.jpg'), findsOneWidget);
      expect(find.text('2 files · 2 KiB'), findsOneWidget);
      expect(find.text('Added 2 files.'), findsOneWidget);
      expect(find.text('Transfer complete'), findsNothing);
    });

    testWidgets('skips duplicate source references in one selection', (
      tester,
    ) async {
      final file = sampleFile();
      await mountApp(
        tester,
        () async => FileSelection(files: <ShareFile>[file, file]),
      );
      await tapSelect(tester);
      expect(find.text('notes.pdf'), findsOneWidget);
      expect(find.text('1 file · 1.5 KiB'), findsOneWidget);
      expect(
        find.text('Added 1 file. 1 duplicate reference skipped.'),
        findsOneWidget,
      );
    });

    testWidgets('skips duplicate source references across picker calls', (
      tester,
    ) async {
      final file = sampleFile();
      await mountApp(
        tester,
        () async => FileSelection(files: <ShareFile>[file]),
      );
      await tapSelect(tester);
      await tester.tap(find.byKey(const ValueKey('add-files-button')));
      await tester.pumpAndSettle();
      expect(find.text('1 file · 1.5 KiB'), findsOneWidget);
      expect(find.text('1 duplicate reference skipped.'), findsOneWidget);
    });

    testWidgets('keeps files that share a name but have different sources', (
      tester,
    ) async {
      await mountApp(
        tester,
        () async => FileSelection(
          files: <ShareFile>[
            sampleFile(path: '/one/notes.pdf'),
            sampleFile(path: '/two/notes.pdf'),
          ],
        ),
      );
      await tapSelect(tester);
      expect(find.text('notes.pdf'), findsNWidgets(2));
      expect(find.text('2 files · 3 KiB'), findsOneWidget);
    });

    testWidgets('preserves the selection when the picker is canceled', (
      tester,
    ) async {
      var calls = 0;
      await mountApp(tester, () async {
        calls += 1;
        return FileSelection(
          files: calls == 1 ? <ShareFile>[sampleFile()] : <ShareFile>[],
        );
      });
      await tapSelect(tester);
      await tester.tap(find.byKey(const ValueKey('add-files-button')));
      await tester.pumpAndSettle();
      expect(find.text('notes.pdf'), findsOneWidget);
      expect(find.text('1 file · 1.5 KiB'), findsOneWidget);
      expect(calls, 2);
    });

    testWidgets('removes a reference without reading its original file', (
      tester,
    ) async {
      var reads = 0;
      final file = sampleFile(
        openRead: () {
          reads += 1;
          return const Stream<List<int>>.empty();
        },
      );
      await mountApp(
        tester,
        () async => FileSelection(files: <ShareFile>[file]),
      );
      await tapSelect(tester);
      await tester.tap(find.byKey(ValueKey('remove:${file.id}')));
      await tester.pumpAndSettle();
      expect(find.text('0 files · 0 B'), findsOneWidget);
      expect(find.text('notes.pdf'), findsNothing);
      expect(reads, 0);
      expect(
        find.text('Removed from selection. Your original file is unchanged.'),
        findsOneWidget,
      );
    });

    testWidgets('asks before clearing and respects both dialog choices', (
      tester,
    ) async {
      await mountApp(
        tester,
        () async => FileSelection(files: <ShareFile>[sampleFile()]),
      );
      await tapSelect(tester);
      await tester.tap(find.byKey(const ValueKey('clear-selection-button')));
      await tester.pumpAndSettle();
      expect(find.text('Clear selection?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('keep-files-button')));
      await tester.pumpAndSettle();
      expect(find.text('notes.pdf'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('clear-selection-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-clear-button')));
      await tester.pumpAndSettle();
      expect(find.text('0 files · 0 B'), findsOneWidget);
      expect(find.text('notes.pdf'), findsNothing);
    });

    testWidgets('shows unavailable-file feedback without losing valid files', (
      tester,
    ) async {
      await mountApp(
        tester,
        () async => FileSelection(
          files: <ShareFile>[sampleFile()],
          unavailableCount: 1,
        ),
      );
      await tapSelect(tester);
      expect(find.text('notes.pdf'), findsOneWidget);
      expect(
        find.text(
          'Added 1 file. 1 file was unavailable. Save locally and try again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('reports an entirely unavailable selection', (tester) async {
      await mountApp(
        tester,
        () async => FileSelection(files: <ShareFile>[], unavailableCount: 2),
      );
      await tapSelect(tester);
      expect(
        find.text('2 files were unavailable. Save locally and try again.'),
        findsOneWidget,
      );
      final count = tester.widget<Text>(
        find.byKey(const ValueKey('selected-count')),
      );
      expect(count.data, '0');
    });

    testWidgets('shows access errors and permits a successful retry', (
      tester,
    ) async {
      var calls = 0;
      await mountApp(tester, () async {
        calls += 1;
        if (calls == 1) {
          throw PlatformException(code: 'permission_denied');
        }
        return FileSelection(files: <ShareFile>[sampleFile()]);
      });
      await tapSelect(tester);
      expect(find.byKey(const ValueKey('selection-error')), findsOneWidget);
      expect(
        find.text(
          'File access was not allowed. You can try the system picker again.',
        ),
        findsOneWidget,
      );
      await tapSelect(tester);
      expect(find.byKey(const ValueKey('selection-error')), findsNothing);
      expect(find.text('notes.pdf'), findsOneWidget);
      expect(calls, 2);
    });

    testWidgets('reports missing native plugins with rebuild instructions', (
      tester,
    ) async {
      await mountApp(tester, () async => throw MissingPluginException());
      await tapSelect(tester);
      expect(find.textContaining('run flutter pub get'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dismiss-error-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('selection-error')), findsNothing);
    });

    testWidgets('handles an unexpected picker error without crashing', (
      tester,
    ) async {
      await mountApp(
        tester,
        () async => throw StateError('test picker failure'),
      );
      await tapSelect(tester);
      expect(
        find.text(
          'We could not read that selection. Try choosing locally stored files.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('prevents repeated picker calls while selection is pending', (
      tester,
    ) async {
      final pending = Completer<FileSelection>();
      var calls = 0;
      await mountApp(tester, () {
        calls += 1;
        return pending.future;
      });
      final button = find.byKey(const ValueKey('select-files-button'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.tap(button);
      await tester.pump();
      expect(calls, 1);
      pending.complete(FileSelection(files: <ShareFile>[sampleFile()]));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('notes.pdf'), findsOneWidget);
    });

    testWidgets('changes themes without losing the current selection', (
      tester,
    ) async {
      await mountApp(
        tester,
        () async => FileSelection(files: <ShareFile>[sampleFile()]),
      );
      await tapSelect(tester);
      final scaffold = find.byKey(const ValueKey('main-scaffold'));
      expect(Theme.of(tester.element(scaffold)).brightness, Brightness.light);
      await tester.tap(find.byKey(const ValueKey('theme-toggle')));
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(scaffold)).brightness, Brightness.dark);
      expect(find.text('notes.pdf'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('theme-toggle')));
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(scaffold)).brightness, Brightness.light);
      expect(find.text('1 file · 1.5 KiB'), findsOneWidget);
    });

    testWidgets('keeps the selection when switching navigation tabs', (
      tester,
    ) async {
      await mountApp(
        tester,
        () async => FileSelection(files: <ShareFile>[sampleFile()]),
      );
      await tapSelect(tester);
      await tapNavigation(tester, 'nav-guide');
      expect(find.text('One step at a time.'), findsOneWidget);
      expect(find.text('Connect nearby'), findsOneWidget);
      await tapNavigation(tester, 'nav-home');
      final count = tester.widget<Text>(
        find.byKey(const ValueKey('selected-count')),
      );
      expect(count.data, '1');
      await tapNavigation(tester, 'nav-files');
      expect(find.text('notes.pdf'), findsOneWidget);
    });

    testWidgets('handles large metadata without reading the file into memory', (
      tester,
    ) async {
      var reads = 0;
      await mountApp(
        tester,
        () async => FileSelection(
          files: <ShareFile>[
            sampleFile(
              name: 'large-video.mkv',
              size: 9663676416,
              openRead: () {
                reads += 1;
                return const Stream<List<int>>.empty();
              },
            ),
          ],
        ),
      );
      await tapSelect(tester);
      expect(find.text('1 file · 9 GiB'), findsOneWidget);
      expect(reads, 0);
    });

    testWidgets('renders narrow screens without layout errors', (tester) async {
      await mountApp(
        tester,
        () async => FileSelection(files: <ShareFile>[sampleFile()]),
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
      await tapSelect(tester);
      expect(find.text('1 file · 1.5 KiB'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tapNavigation(tester, 'nav-guide');
      expect(tester.takeException(), isNull);
    });

    testWidgets('supports large system text on a narrow screen', (
      tester,
    ) async {
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      await mountApp(
        tester,
        () async => FileSelection(files: <ShareFile>[sampleFile()]),
        size: const Size(320, 740),
      );
      expect(tester.takeException(), isNull);
      await tapNavigation(tester, 'nav-files');
      expect(tester.takeException(), isNull);
      await tapNavigation(tester, 'nav-guide');
      expect(tester.takeException(), isNull);
    });

    testWidgets('ignores late picker results after the screen is disposed', (
      tester,
    ) async {
      final pending = Completer<FileSelection>();
      await mountApp(tester, () => pending.future);
      final button = find.byKey(const ValueKey('select-files-button'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(FileSelection(files: <ShareFile>[sampleFile()]));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
```


## নিজে পরীক্ষা করুন

1. Android phone/emulator বা Mac-এর iOS Simulator-এ app চালান। প্রথম পর্দায় selection count হবে 0।
2. **Select files** দিয়ে দুইটি locally stored file নিন। Files tab-এ নাম ও মোট size দেখুন।
3. **Add files** খুলে cancel করুন। পুরোনো selection থাকবে।
4. কোনো ফাইলের পাশের close button চাপুন। শুধু তালিকার reference সরবে; আসল ফাইল মুছবে না।
5. **Clear list → Keep files** এবং **Clear list → Clear selection** দুই পথ পরীক্ষা করুন।
6. Theme button ও Home / Files / Guide tab বদলান। চলতি session-এর তালিকা থাকবে।
7. App পুরোপুরি বন্ধ করে আবার খুললে selection ও theme preference reset হবে। এগুলো এখনো persistent নয়।
8. এই সংস্করণে **Send**, **Receive** বা সফল transfer দেখার চেষ্টা করবেন না—সেগুলো এখনো implement করা হয়নি।

দেখানো size file-provider metadata থেকে নেওয়া হয়। আমাদের Dart selection logic পুরো file RAM-এ পড়ে না; native picker/OS প্রয়োজন হলে temporary copy বা cloud download করতে পারে। বাস্তব sender যোগ করার সময় metadata-এর পাশাপাশি streamed byte count-ও যাচাই করতে হবে।

### পরীক্ষার সীমা

এখানে `flutter analyze`-এ কোনো issue পাওয়া যায়নি এবং `flutter test`-এর ২৮টি model/widget test পাস করেছে। Unit/widget tests-এর picker results injected; native OS picker, physical phone, APK compilation ও iOS compilation এখনো verify করা হয়নি। Preview image Flutter test renderer-এর, বাস্তব ফোনের screenshot নয়।

## পরের ধাপ — Next Part 2

পরের Part-এ **File 6–10** দিয়ে local-network/pairing ও transfer foundation শুরু করব। আগের কোনো ফাইল বদলাতে হলে সেটির আগের file number রেখেই সম্পূর্ণ updated version দেব। UI integration ও Android/iOS network permission-এর প্রয়োজনীয় কাজও ধারাবাহিকভাবে যোগ হবে; networking চালু হওয়ার আগে সেগুলো বাদ রাখা হবে না।

**চালিয়ে যেতে চ্যাটে লিখুন: `Next Part 2`।**
