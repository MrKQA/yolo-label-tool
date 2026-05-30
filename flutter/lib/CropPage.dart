// ignore_for_file: file_names

part of 'main.dart';

class _CropPage extends StatefulWidget {
  const _CropPage({required this.exportPath});

  final String exportPath;

  @override
  State<_CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<_CropPage> {
  String? _videoPath;
  String? _videoName;
  int _frameInterval = 30;
  final _folderNameController = TextEditingController(text: 'frames');
  bool _processing = false;
  String? _statusMessage;

  @override
  void dispose() {
    _folderNameController.dispose();
    super.dispose();
  }

  Future<void> _importVideo() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Video', extensions: ['mp4', 'avi', 'mov', 'mkv']),
      ],
    );
    if (file != null && mounted) {
      setState(() {
        _videoPath = file.path;
        _videoName = file.name;
        _statusMessage = '${t('crop.videoLoaded')}: ${file.name}';
      });
    }
  }

  Future<void> _startExtraction() async {
    if (_videoPath == null) return;
    setState(() {
      _processing = true;
      _statusMessage = t('crop.processingHint');
    });
    // Frame extraction requires Rust backend support.
    // The Rust bridge API extract_video_frames will be called here.
    await Future<void>.delayed(const Duration(seconds: 1));
    if (mounted) {
      setState(() {
        _processing = false;
        _statusMessage = t('crop.processingHint');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _workspaceColor(context),
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('crop.title'), style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _processing ? null : _importVideo,
                icon: const Icon(Icons.video_file_outlined),
                label: Text(t('crop.importVideo')),
              ),
              const SizedBox(width: 16),
              if (_videoName != null)
                Expanded(
                  child: Text(
                    _videoName!,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
            ],
          ),
          if (_videoPath != null) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  '${t('crop.frameInterval')}: ',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                SizedBox(
                  width: 200,
                  child: Slider(
                    value: _frameInterval.toDouble(),
                    min: 1,
                    max: 120,
                    divisions: 119,
                    label: '$_frameInterval',
                    onChanged: (v) =>
                        setState(() => _frameInterval = v.round()),
                  ),
                ),
                Text('${t('crop.every')} $_frameInterval ${t('crop.frames')}'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${t('export.folderName')}: ',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _folderNameController,
                    decoration: const InputDecoration(isDense: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${t('settings.outputPath')}: ${widget.exportPath}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _processing ? null : _startExtraction,
                  icon: const Icon(Icons.start),
                  label: Text(t('crop.startExtract')),
                ),
                if (_processing) ...[
                  const SizedBox(width: 16),
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ],
          if (_statusMessage != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusMessage!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          if (_videoPath == null) ...[
            const SizedBox(height: 24),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.content_cut,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      t('crop.placeholder'),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
