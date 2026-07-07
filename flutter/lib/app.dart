part of 'main.dart';

class YoloLabelApp extends StatelessWidget {
  const YoloLabelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguageStrings>(
      valueListenable: _languageStringsNotifier,
      builder: (context, language, _) {
        _appText = language;
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: _themeModeNotifier,
          builder: (context, themeMode, _) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: t('app.title'),
              themeMode: themeMode,
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: _brandColor),
                fontFamily: _fontFamily,
                scaffoldBackgroundColor: _workspaceBackground,
                useMaterial3: true,
              ),
              darkTheme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: _darkBrandColor,
                  brightness: Brightness.dark,
                ),
                brightness: Brightness.dark,
                fontFamily: _fontFamily,
                scaffoldBackgroundColor: _darkAppBackground,
                dialogTheme: const DialogThemeData(
                  backgroundColor: _darkPanelBackground,
                  titleTextStyle: TextStyle(
                    color: _darkTextColor,
                    fontFamily: _fontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                dividerTheme: const DividerThemeData(color: _darkBorderColor),
                menuTheme: const MenuThemeData(
                  style: MenuStyle(
                    backgroundColor: WidgetStatePropertyAll(
                      _darkPanelBackground,
                    ),
                    surfaceTintColor: WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                  ),
                ),
                outlinedButtonTheme: OutlinedButtonThemeData(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _darkControlBackground,
                    foregroundColor: _darkTextColor,
                    side: const BorderSide(color: _darkBorderColor),
                  ),
                ),
                textButtonTheme: TextButtonThemeData(
                  style: TextButton.styleFrom(foregroundColor: _darkBrandColor),
                ),
                useMaterial3: true,
              ),
              home: const HomePage(),
            );
          },
        );
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Future<_BridgeStatus> _status = _loadStatus();

  Future<_BridgeStatus> _loadStatus() async {
    final greeting = await rustGreeting(name: 'Flutter');
    final modes = await supportedAnnotationModes();
    return _BridgeStatus(greeting: greeting, modes: modes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<_BridgeStatus>(
        future: _status,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SelectableText(
                  '${t('app.bridgeError')}:\n${snapshot.error}',
                ),
              ),
            );
          }

          return _WorkspaceShell(status: snapshot.data!);
        },
      ),
    );
  }
}

class _BridgeStatus {
  const _BridgeStatus({required this.greeting, required this.modes});

  final String greeting;
  final List<String> modes;
}
