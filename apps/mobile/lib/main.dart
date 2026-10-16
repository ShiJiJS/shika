import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'library/demo_repository.dart';
import 'library/models.dart';
import 'library/repository.dart';
import 'library/state_store.dart';
import 'ui/home.dart';
import 'ui/paper.dart';

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
  runApp(VideoViewerApp(repository: repository, initialError: error));
}

class VideoViewerApp extends StatelessWidget {
  const VideoViewerApp({
    super.key,
    required this.repository,
    this.initialError,
    this.backupFiles,
  });
  final LibraryRepository repository;
  final String? initialError;
  final BackupFiles? backupFiles;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Video Viewer',
    debugShowCheckedModeBanner: false,
    theme: Paper.theme,
    home: LibraryHome(
      key: ObjectKey(repository),
      repository: repository,
      initialError: initialError,
      backupFiles: backupFiles,
    ),
  );
}
