import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'library/demo_repository.dart';
import 'library/models.dart';
import 'library/repository.dart';
import 'library/state_store.dart';
import 'library/credentials.dart';
import 'library/server_repository.dart';
import 'library/file_command_store.dart';
import 'library/backup_work_store.dart';
import 'library/backup_file_picker.dart';
import 'ui/home.dart';
import 'ui/paper.dart';
import 'ui/preferences.dart';
import 'library/server_api.dart';
import 'features/connection/connection_flow.dart';

/// Shared by the real entry point and isolated native startup checks.
Future<void> configureApplicationWindow() async {
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Paper.background,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Paper.background,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureApplicationWindow();
  const demo =
      String.fromEnvironment('LIBRARY_MODE', defaultValue: 'server') == 'demo';
  final LibraryRepository repository = demo
      ? DemoLibraryRepository(
          await FileStateStore.create(),
          scenario: DemoScenario.values.byName(
            const String.fromEnvironment(
              'DEMO_SCENARIO',
              defaultValue: 'normal',
            ),
          ),
        )
      : ServerLibraryRepository(
          SecureCredentialStore(),
          fileCommands: SecureFileCommandStore(),
          packCommands: SecureFileCommandStore(
            key: 'video_viewer.pack_commands.v1',
          ),
          backupWork: SecureBackupWorkStore(),
          address: const String.fromEnvironment('SERVER_ADDRESS'),
          port: const int.fromEnvironment('SERVER_PORT', defaultValue: 8760),
        );
  String? error;
  if (demo) {
    try {
      await repository.initialize();
    } catch (e) {
      error = e.toString();
    }
  }
  runApp(
    ShikaApp(
      repository: repository,
      initializeRepository: !demo,
      initialError: error,
      preferences: await UiPreferences.load(),
    ),
  );
}

class ShikaApp extends StatefulWidget {
  const ShikaApp({
    super.key,
    required this.repository,
    this.initialError,
    this.backupFiles,
    this.backupArchiveFiles = const NativeBackupArchiveFiles(),
    this.preferences,
    this.initializeRepository = false,
    this.navigatorObservers = const [],
  });
  final LibraryRepository repository;
  final String? initialError;
  final BackupFiles? backupFiles;
  final BackupArchiveFiles backupArchiveFiles;
  final UiPreferences? preferences;
  final bool initializeRepository;
  final List<NavigatorObserver> navigatorObservers;
  @override
  State<ShikaApp> createState() => _ShikaAppState();
}

class _ShikaAppState extends State<ShikaApp> {
  late final preferences = widget.preferences ?? UiPreferences();
  GlobalKey<NavigatorState> navigation = GlobalKey<NavigatorState>();
  late bool connected;
  late Object identity;
  late bool starting = widget.initializeRepository;
  String? offlineError, loginError;
  bool relogin = false;
  int startup = 0;

  @override
  void initState() {
    super.initState();
    connected = widget.repository.snapshot.connected;
    identity = widget.repository.connectionIdentity;
    widget.repository.addListener(connectionChanged);
    if (starting) unawaited(restore());
  }

  void connectionChanged() {
    if (!mounted) return;
    final repo = widget.repository;
    setState(() {
      if (connected != repo.snapshot.connected ||
          repo.snapshot.connected &&
              !identical(identity, repo.connectionIdentity)) {
        // All pages, sheets and players belong to one authenticated connection.
        // Replacing this navigator disposes them, including root popup routes.
        navigation = GlobalKey<NavigatorState>();
      }
      connected = repo.snapshot.connected;
      identity = repo.connectionIdentity;
    });
  }

  Future<void> restore() async {
    final serial = ++startup;
    setState(() {
      starting = true;
      offlineError = loginError = null;
      relogin = false;
    });
    try {
      await widget.repository.initialize();
    } catch (failure) {
      if (!mounted || serial != startup) return;
      if (failure is ApiFailure && failure.status == 401) {
        loginError = '登录已失效，请重新输入个人口令';
        relogin = true;
      } else if (failure is ApiFailure &&
          widget.repository.snapshot.address.isNotEmpty) {
        offlineError = connectionFailure(failure);
      } else {
        loginError = connectionFailure(failure);
      }
    } finally {
      if (mounted && serial == startup) setState(() => starting = false);
    }
  }

  void changeServer() {
    startup++;
    widget.repository.cancelConnection();
    setState(() {
      starting = false;
      offlineError = loginError = null;
      relogin = false;
    });
  }

  Widget destination() {
    final repo = widget.repository;
    if (starting || offlineError != null) {
      return ConnectionRestoration(
        endpoint: repo.snapshot.address.isEmpty
            ? ''
            : '${repo.snapshot.address}:${repo.snapshot.port}',
        error: offlineError,
        onRetry: restore,
        onChange: changeServer,
      );
    }
    if (!repo.snapshot.connected) {
      return ConnectionFlow(
        key: ObjectKey(repo),
        repository: repo,
        preferences: preferences,
        initialError: loginError ?? repo.connectionError ?? widget.initialError,
        autoCheck: relogin || repo.connectionError != null,
      );
    }
    return LibraryHome(
      key: ObjectKey(repo),
      repository: repo,
      initialError: widget.initialError,
      backupFiles: widget.backupFiles,
      backupArchiveFiles: widget.backupArchiveFiles,
      preferences: preferences,
    );
  }

  @override
  void dispose() {
    startup++;
    widget.repository.removeListener(connectionChanged);
    widget.repository.cancelConnection();
    if (widget.preferences == null) preferences.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) => MaterialApp(
      title: '拾刻',
      navigatorKey: navigation,
      debugShowCheckedModeBanner: false,
      navigatorObservers: widget.navigatorObservers,
      theme: Paper.theme,
      darkTheme: Paper.darkTheme,
      themeMode: preferences.dark ? ThemeMode.dark : ThemeMode.light,
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => PaperAppearanceTheme(
        data: Theme.of(context),
        reduced: MediaQuery.disableAnimationsOf(context),
        child: Builder(
          builder: (context) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: preferences.dark
                  ? Brightness.light
                  : Brightness.dark,
              systemNavigationBarColor: Theme.of(context)
                  .scaffoldBackgroundColor,
              systemNavigationBarIconBrightness: preferences.dark
                  ? Brightness.light
                  : Brightness.dark,
            ),
            child: PaperControlTheme(child: child!),
          ),
        ),
      ),
      home: destination(),
    ),
  );
}
