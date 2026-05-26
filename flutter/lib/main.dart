import 'package:flutter/material.dart';

import 'src/rust/api.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const YoloLabelApp());
}

class YoloLabelApp extends StatelessWidget {
  const YoloLabelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'YOLO Label Tool',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
      ),
      home: const HomePage(),
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
      appBar: AppBar(title: const Text('YOLO Label Tool')),
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
                child: SelectableText('Rust bridge failed:\n${snapshot.error}'),
              ),
            );
          }

          final status = snapshot.data!;
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status.greeting, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                Text('Annotation modes', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final mode in status.modes) Chip(label: Text(mode.toUpperCase())),
                  ],
                ),
                const SizedBox(height: 24),
                const Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.fromBorderSide(BorderSide(color: Color(0xFFE5E7EB))),
                    ),
                    child: Center(child: Text('Annotation canvas placeholder')),
                  ),
                ),
              ],
            ),
          );
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
