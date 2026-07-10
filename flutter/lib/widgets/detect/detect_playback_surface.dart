part of '../../main.dart';

class _DetectPlaybackSurface extends StatelessWidget {
  const _DetectPlaybackSurface({
    required this.session,
    required this.onCancelPrediction,
    required this.onSeekPredictionFrame,
  });

  final _DetectVideoSession session;
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
                  ? _PredictedFrameSequencePanel(
                      manifestPath: input,
                      predicting: session.predicting,
                      onCancelPrediction: onCancelPrediction,
                      onSeekFrame: onSeekPredictionFrame,
                    )
                  : _VideoPlayerPanel(session: session),
            ),
          ),
          if (input != null && showPredictionStatus)
            Positioned(
              right: 14,
              top: 14,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _controlColor(context).withAlpha(232),
                  border: Border.all(color: _borderColor(context)),
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
