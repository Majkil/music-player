import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:app_links/app_links.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path/path.dart' as p;
import 'services/audio_handler.dart';
import 'services/objectbox_service.dart';
import 'screens/files_screen.dart';

late MusicAudioHandler audioHandler;

@pragma('vm:entry-point')
Future<void> widgetBackgroundHandler(Uri? uri) async {
  // Ensure AudioService is initialized in this isolate
  final handler = await AudioService.init(
    builder: () => MusicAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.music_player.audio',
      androidNotificationChannelName: 'Music Player',
    ),
  );

  if (uri?.host == 'skipnext') {
    await handler.skipToNext();
  } else if (uri?.host == 'skipprevious') {
    await handler.skipToPrevious();
  } else if (uri?.host == 'playpause') {
    final playing = handler.playbackState.value.playing;
    if (playing) {
      await handler.pause();
    } else {
      await handler.play();
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('--- APP STARTING ---');

  try {
    // Initialize ObjectBox
    debugPrint('Initializing ObjectBox...');
    final objectBoxService = await ObjectBoxService.getInstance();
    debugPrint('ObjectBox initialized successfully.');

    // Initialize AudioService
    debugPrint('Initializing AudioService...');
    audioHandler = await AudioService.init(
      builder: () => MusicAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.music_player.audio',
        androidNotificationChannelName: 'Music Player',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        androidNotificationIcon: 'mipmap/ic_launcher',
      ),
    );
    debugPrint('AudioService initialized successfully.');

    // Setup HomeWidget background callback
    HomeWidget.registerInteractivityCallback(widgetBackgroundHandler);

    // Handle initial intent (cold start)
    final appLinks = AppLinks();
    final initialUri = await appLinks.getInitialLink();
    if (initialUri != null) {
      _handleExternalUri(initialUri);
    }

    // Handle streaming intents (warm start)
    appLinks.uriLinkStream.listen(_handleExternalUri);

    debugPrint('Running app...');
    runApp(MusicPlayerApp(
      audioHandler: audioHandler,
      objectBoxService: objectBoxService,
    ));
  } catch (e, stack) {
    debugPrint('CRITICAL ERROR DURING STARTUP: $e');
    debugPrint(stack.toString());
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error starting app: $e'),
          ),
        ),
      ),
    ));
  }
}

void _handleExternalUri(Uri uri) {
  debugPrint('Handling external URI: $uri');
  final String filePath = uri.toFilePath();
  final String fileName = p.basenameWithoutExtension(filePath);

  final mediaItem = MediaItem(
    id: filePath,
    title: fileName,
    artist: 'External File',
  );

  audioHandler.loadQueue([mediaItem]);
  audioHandler.play();
}

class MusicPlayerApp extends StatelessWidget {
  final MusicAudioHandler audioHandler;
  final ObjectBoxService objectBoxService;

  const MusicPlayerApp({
    super.key,
    required this.audioHandler,
    required this.objectBoxService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        primaryColor: const Color(0xFF6C63FF),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF6C63FF),
          secondary: const Color(0xFFE91E63),
          surface: const Color(0xFF1A1A2E),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A1A2E),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        fontFamily: 'Roboto',
      ),
      home: FilesScreen(
        audioHandler: audioHandler,
        objectBoxService: objectBoxService,
      ),
    );
  }
}
