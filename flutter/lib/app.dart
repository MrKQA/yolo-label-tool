// =============================================================================
// app.dart - Root Application Widget / 根应用组件
// =============================================================================
// Defines YoloLabelApp with Material theme configuration, dark/light mode
// support, and the workspace shell as its home page.
//
// 定义 YoloLabelApp 根组件：Material 主题配置、暗色/亮色模式支持、
// 以 WorkspaceShell 为主页面。
// =============================================================================

import 'package:flutter/material.dart';

import 'models/app_status.dart';
import 'services/app_runtime.dart';
import 'services/i18n.dart';
import 'services/window_branding.dart';
import 'src/rust/api.dart';
import 'theme/app_theme.dart';
import 'theme/theme_transition.dart';
import 'widgets/common/workspace_shell.dart';

class YoloLabelApp extends StatelessWidget {
  const YoloLabelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguageStrings>(
      valueListenable: languageStringsNotifier,
      builder: (context, language, _) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeNotifier,
          builder: (context, themeMode, _) {
            return ValueListenableBuilder<WindowBranding>(
              valueListenable: windowBrandingNotifier,
              builder: (context, branding, _) {
                return MaterialApp(
                  debugShowCheckedModeBanner: false,
                  title: branding.displayName,
                  themeMode: themeMode,
                  theme: buildAppTheme(Brightness.light),
                  darkTheme: buildAppTheme(Brightness.dark),
                  themeAnimationDuration: Duration.zero,
                  themeAnimationCurve: appMotionCurve,
                  scrollBehavior: const AppScrollBehavior(),
                  builder: (context, child) {
                    final media = MediaQuery.of(context);
                    return AppThemeRippleTransition(
                      child: MediaQuery(
                        data: media.copyWith(
                          textScaler: media.textScaler.clamp(
                            minScaleFactor: 0.90,
                            maxScaleFactor: 1.30,
                          ),
                        ),
                        child: child ?? const SizedBox.shrink(),
                      ),
                    );
                  },
                  home: const HomePage(),
                );
              },
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
  late final Future<BridgeStatus> _status = _loadStatus();

  Future<BridgeStatus> _loadStatus() async {
    final greeting = await rustGreeting(name: 'Flutter');
    final modes = await supportedAnnotationModes();
    return BridgeStatus(greeting: greeting, modes: modes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<BridgeStatus>(
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

          return WorkspaceShell(status: snapshot.data!);
        },
      ),
    );
  }
}
