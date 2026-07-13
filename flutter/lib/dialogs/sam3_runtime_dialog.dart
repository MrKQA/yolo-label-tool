// =============================================================================
// sam3_runtime_dialog.dart - SAM3 Runtime Configuration / SAM3 运行时配置
// =============================================================================
// Dialog for configuring SAM3 inference parameters: precision, encoder,
// batch sizes, image dimensions, resize method, and torch.compile toggle.
//
// 配置 SAM3 推理参数：精度、编码器、batch 大小、图片尺寸、缩放方式与编译开关。
// =============================================================================

import 'package:flutter/material.dart';

import '../models/ai_assist.dart';
import '../services/i18n.dart';

class Sam3RuntimeDialog extends StatefulWidget {
  const Sam3RuntimeDialog({required this.initial});

  final AiSam3RuntimeConfig initial;

  @override
  State<Sam3RuntimeDialog> createState() => _Sam3RuntimeDialogState();
}

class _Sam3RuntimeDialogState extends State<Sam3RuntimeDialog> {
  late String _precision;
  late String _encoder;
  late String _resizeMethod;
  late bool _compile;
  late final TextEditingController _imageBatchController;
  late final TextEditingController _videoBatchController;
  late final TextEditingController _interactiveBatchController;
  late final TextEditingController _maxWidthController;
  late final TextEditingController _maxHeightController;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _precision = initial.precision;
    _encoder = initial.encoder;
    _resizeMethod = initial.resizeMethod == 'shorter_side'
        ? initial.resizeMethod
        : 'shorter_side';
    _compile = initial.compile;
    _imageBatchController = TextEditingController(
      text: initial.imageBatchSize.toString(),
    );
    _videoBatchController = TextEditingController(
      text: initial.videoBatchSize.toString(),
    );
    _interactiveBatchController = TextEditingController(
      text: initial.interactiveBatchSize.toString(),
    );
    _maxWidthController = TextEditingController(
      text: initial.maxImageWidth.toString(),
    );
    _maxHeightController = TextEditingController(
      text: initial.maxImageHeight.toString(),
    );
  }

  @override
  void dispose() {
    _imageBatchController.dispose();
    _videoBatchController.dispose();
    _interactiveBatchController.dispose();
    _maxWidthController.dispose();
    _maxHeightController.dispose();
    super.dispose();
  }

  int _intValue(TextEditingController controller, int fallback) {
    final value = int.tryParse(controller.text.trim()) ?? fallback;
    return value.clamp(1, 4096).toInt();
  }

  void _save() {
    Navigator.of(context).pop(
      AiSam3RuntimeConfig(
        precision: _precision,
        encoder: _encoder,
        imageBatchSize: _intValue(_imageBatchController, 1),
        videoBatchSize: _intValue(_videoBatchController, 1),
        interactiveBatchSize: _intValue(_interactiveBatchController, 1),
        maxImageWidth: _intValue(_maxWidthController, 1024),
        maxImageHeight: _intValue(_maxHeightController, 768),
        resizeMethod: _resizeMethod,
        compile: _compile,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('ai.sam3RuntimeConfig')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _precision,
                decoration: InputDecoration(labelText: t('ai.sam3Precision')),
                items: const [
                  DropdownMenuItem(value: 'fp16', child: Text('fp16')),
                  DropdownMenuItem(value: 'bf16', child: Text('bf16')),
                  DropdownMenuItem(value: 'fp32', child: Text('fp32')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _precision = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _encoder,
                decoration: InputDecoration(labelText: t('ai.sam3Encoder')),
                items: const [
                  DropdownMenuItem(value: 'vit_b', child: Text('vit_b')),
                  DropdownMenuItem(value: 'vit_l', child: Text('vit_l')),
                  DropdownMenuItem(value: 'vit_h', child: Text('vit_h')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _encoder = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _resizeMethod,
                decoration: InputDecoration(
                  labelText: t('ai.sam3ResizeMethod'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'shorter_side',
                    child: Text(t('ai.sam3ResizeShorterSide')),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _resizeMethod = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('ai.sam3Compile')),
                value: _compile,
                onChanged: (value) {
                  setState(() => _compile = value);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _imageBatchController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: t('ai.sam3BatchImage'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _videoBatchController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: t('ai.sam3BatchVideo'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _interactiveBatchController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: t('ai.sam3BatchInteractive'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _maxWidthController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: t('ai.sam3MaxWidth'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _maxHeightController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: t('ai.sam3MaxHeight'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t('action.cancel')),
        ),
        FilledButton(onPressed: _save, child: Text(t('action.save'))),
      ],
    );
  }
}
