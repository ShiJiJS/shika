import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'library/demo_repository.dart';
import 'library/models.dart';
import 'library/repository.dart';
import 'library/state_store.dart';
import 'ui/home.dart';
import 'ui/paper.dart';
import 'ui/preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Paper.background,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Paper.background,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  final repository = DemoLibraryRepository(
    await FileStateStore.create(),
    scenario: DemoScenario.values.byName(
      const String.fromEnvironment('DEMO_SCENARIO', defaultValue: 'normal'),
    ),
  );
  String? error;
  try {
    await repository.initialize();
  } catch (e) {
    error = e.toString();
  }
  runApp(
    VideoViewerApp(
      repository: repository,
      initialError: error,
      preferences: await UiPreferences.load(),
    ),
  );
}

class VideoViewerApp extends StatefulWidget {
  const VideoViewerApp({
    super.key,
    required this.repository,
    this.initialError,
    this.backupFiles,
    this.preferences,
  });
  final LibraryRepository repository;
  final String? initialError;
  final BackupFiles? backupFiles;
  final UiPreferences? preferences;
  @override
  State<VideoViewerApp> createState() => _VideoViewerAppState();
}

class _VideoViewerAppState extends State<VideoViewerApp> {
  late final preferences = widget.preferences ?? UiPreferences();
  @override
  void dispose() {
    if (widget.preferences == null) preferences.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) => MaterialApp(
      title: 'Video Viewer',
      debugShowCheckedModeBanner: false,
      theme: Paper.theme,
      darkTheme: Paper.darkTheme,
      themeMode: preferences.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: preferences.dark
              ? Brightness.light
              : Brightness.dark,
          systemNavigationBarColor: Theme.of(context).scaffoldBackgroundColor,
          systemNavigationBarIconBrightness: preferences.dark
              ? Brightness.light
              : Brightness.dark,
        ),
        child: child!,
      ),
      home: LibraryHome(
        key: ObjectKey(widget.repository),
        repository: widget.repository,
        initialError: widget.initialError,
        backupFiles: widget.backupFiles,
        preferences: preferences,
      ),
    ),
  );
}
