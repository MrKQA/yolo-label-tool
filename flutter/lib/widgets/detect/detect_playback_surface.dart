import 'dart:io';

import 'package:flutter/material.dart';

import '../../pages/detect_video_page.dart';
import '../../services/i18n.dart';
import '../../services/path_utils.dart';
import '../../theme/theme_helpers.dart';
import 'detect_support.dart';
import 'prediction_sequence.dart';
import 'video_player_widgets.dart';

class DetectPlaybackSurface extends StatelessWidget {
  const DetectPlaybackSurface({
    required this.session,
    required this.onCancelPrediction,
    required this.onSeekPredictionFrame,
  });

  final DetectVideoSession session;
  final VoidCallback onCancelPrediction;
  final ValueChanged<int> onSeekPredictionFrame;

  @override
  Widget build(BuildContext context) {
    final input = session.displayInput;
    final showPredictionStatus =
        session.predictVideo ||
        session.predictAll ||
        session.predictionOutputPath != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: null,
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: input == null
                  ? Text(t('detect.placeholder'))
                  : isImagePath(input)
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Image.file(
                        File(input),
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    )
                  : isPredictionManifestPath(input)
                  ? PredictedFrameSequencePanel(
                      manifestPath: input,
                      predicting: session.predicting,
                      onCancelPrediction: onCancelPrediction,
                      onSeekFrame: onSeekPredictionFrame,
                    )
                  : VideoPlayerPanel(session: session),
            ),
          ),
          if (input != null && showPredictionStatus)
            Positioned(
              right: 14,
              top: 14,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: controlColor(context).withAlpha(232),
                  border: Border.all(color: borderColor(context)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Text(
                    session.showPredictionResult
                        ? t('detect.resultVisible')
                        : t('detect.resultHidden'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
