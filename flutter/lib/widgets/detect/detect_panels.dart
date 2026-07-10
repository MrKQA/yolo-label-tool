part of '../../main.dart';

class _DetectPreviewList extends StatelessWidget {
  const _DetectPreviewList({
    required this.items,
    required this.selectedInput,
    required this.onSelected,
  });

  final List<String> items;
  final String? selectedInput;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final selected = pathKey(item) == pathKey(selectedInput ?? '');
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => onSelected(item),
            borderRadius: BorderRadius.circular(6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : _controlColor(context),
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : _borderColor(context),
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: isImagePath(item)
                          ? Image.file(File(item), fit: BoxFit.cover)
                          : const Center(
                              child: Icon(Icons.video_file_outlined, size: 32),
                            ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fileName(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DetectParameterPanel extends StatelessWidget {
  const _DetectParameterPanel({
    required this.session,
    required this.deviceValue,
    required this.deviceArgument,
    required this.autoDeviceLabel,
    required this.nvidiaDeviceLabel,
    required this.hasNvidiaDevice,
    required this.intelDeviceLabel,
    required this.hasOpenVinoDevice,
    required this.onChooseModel,
    required this.onResetEffect,
    required this.onPredict,
    required this.onSaveCurrent,
    required this.onSaveAll,
    required this.onToggleResult,
    required this.onConfChanged,
    required this.onImageSizeChanged,
    required this.onDeviceChanged,
  });

  final _DetectVideoSession session;
  final String deviceValue;
  final String deviceArgument;
  final String autoDeviceLabel;
  final String nvidiaDeviceLabel;
  final bool hasNvidiaDevice;
  final String intelDeviceLabel;
  final bool hasOpenVinoDevice;
  final VoidCallback onChooseModel;
  final VoidCallback onResetEffect;
  final VoidCallback onPredict;
  final VoidCallback onSaveCurrent;
  final VoidCallback onSaveAll;
  final VoidCallback onToggleResult;
  final ValueChanged<double> onConfChanged;
  final ValueChanged<int> onImageSizeChanged;
  final ValueChanged<String> onDeviceChanged;

  bool get _hasFolderImageTargets => session.folderItems.any(isImagePath);

  bool get _canRunCurrent =>
      !session.predicting && session.selectedInput != null;

  @override
  Widget build(BuildContext context) {
    final selectedModel = session.detectModelPath;
    final hasPrediction = session.predictionOutputPath != null;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('detect.parameters'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              children: [
                ParameterSectionTitle(title: t('detect.model')),
                Row(
                  children: [
                    Expanded(
                      child: Tooltip(
                        message: selectedModel ?? t('detect.chooseModel'),
                        waitDuration: const Duration(milliseconds: 500),
                        child: OutlinedButton.icon(
                          onPressed: session.predicting ? null : onChooseModel,
                          icon: const Icon(Icons.folder_open, size: 16),
                          label: Text(
                            selectedModel == null
                                ? t('detect.chooseModel')
                                : fileName(selectedModel),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    if (selectedModel != null) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: session.predicting ? null : onResetEffect,
                        icon: const Icon(Icons.restart_alt, size: 16),
                        label: Text(t('detect.resetEffect')),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                ParameterSectionTitle(title: t('detect.actions')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(t('detect.playVideo')),
                  value: session.playVideo,
                  onChanged: session.predicting
                      ? null
                      : (value) => unawaited(session.setPlayMode(value)),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: session.predicting ? null : onPredict,
                    icon: session.predicting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.visibility, size: 16),
                    label: Text(
                      session.predicting
                          ? t('detect.predicting')
                          : selectedModel == null
                          ? t('detect.chooseModel')
                          : t('detect.predict'),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _canRunCurrent ? onSaveCurrent : null,
                        icon: const Icon(Icons.save_alt, size: 16),
                        label: Text(t('detect.saveCurrent')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: !session.predicting && _hasFolderImageTargets
                            ? onSaveAll
                            : null,
                        icon: const Icon(Icons.library_add_check, size: 16),
                        label: Text(t('detect.saveAll')),
                      ),
                    ),
                  ],
                ),
                if (hasPrediction) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onToggleResult,
                      icon: const Icon(Icons.compare, size: 16),
                      label: Text(
                        session.showPredictionResult
                            ? t('detect.showOriginal')
                            : t('detect.showPredicted'),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                ParameterSectionTitle(title: t('detect.inferenceParams')),
                ImageSizeParameterEditor(
                  value: session.detectImageSize.toDouble(),
                  enabled: !session.predicting,
                  onChanged: (value) => onImageSizeChanged(value.round()),
                ),
                const SizedBox(height: 10),
                Tooltip(
                  message: t('detect.conf'),
                  waitDuration: const Duration(milliseconds: 500),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      children: [
                        ParameterHeader(
                          name: t('detect.conf'),
                          value:
                              'conf=${session.detectConf.toStringAsFixed(2)}',
                        ),
                        CompactSlider(
                          value: session.detectConf,
                          min: 0.01,
                          max: 1.0,
                          divisions: 99,
                          label: session.detectConf.toStringAsFixed(2),
                          enabled: !session.predicting,
                          onChanged: onConfChanged,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Tooltip(
                  message: t('detect.deviceHelp'),
                  waitDuration: const Duration(milliseconds: 500),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ParameterHeader(
                          name: t('detect.device'),
                          value: 'device=$deviceArgument',
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _DetectDeviceChip(
                              value: 'auto',
                              label: autoDeviceLabel,
                              selected: deviceValue == 'auto',
                              enabled: !session.predicting,
                              onSelected: onDeviceChanged,
                            ),
                            _DetectDeviceChip(
                              value: 'nv',
                              label: nvidiaDeviceLabel,
                              selected: deviceValue == 'nv',
                              enabled: !session.predicting && hasNvidiaDevice,
                              onSelected: onDeviceChanged,
                            ),
                            _DetectDeviceChip(
                              value: 'intel',
                              label: intelDeviceLabel,
                              selected: deviceValue == 'intel',
                              enabled:
                                  !session.predicting && hasOpenVinoDevice,
                              onSelected: onDeviceChanged,
                            ),
                            _DetectDeviceChip(
                              value: 'cpu',
                              label: t('detect.deviceCpu'),
                              selected: deviceValue == 'cpu',
                              enabled: !session.predicting,
                              onSelected: onDeviceChanged,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetectDeviceChip extends StatelessWidget {
  const _DetectDeviceChip({
    required this.value,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final String value;
  final String label;
  final bool selected;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 500),
      child: FilterChip(
        selected: selected,
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 210),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        avatar: Icon(
          selected ? Icons.check_circle : Icons.memory_outlined,
          size: 18,
        ),
        onSelected: enabled ? (_) => onSelected(value) : null,
      ),
    );
  }
}
