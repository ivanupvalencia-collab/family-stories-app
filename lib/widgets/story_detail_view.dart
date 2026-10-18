import 'package:flutter/material.dart';

import '../design/aritoria_design.dart';
import 'question_text.dart';
import 'story_waveform_view.dart';

/// Story presentation. The player uses real position/duration; no fake waveform.
class StoryDetailView extends StatelessWidget {
  const StoryDetailView({
    required this.question,
    required this.date,
    required this.position,
    required this.duration,
    required this.playing,
    required this.loading,
    required this.onPlay,
    required this.onSeekChanged,
    required this.onSeekEnd,
    required this.photoMenu,
    this.authorName,
    this.recipientName,
    this.photo,
    this.waveform,
    this.onSeekCancel,
    this.waveformLoading = false,
    super.key,
  });
  final String question, date;
  final String? authorName, recipientName;
  final Duration position, duration;
  final bool playing, loading;
  final VoidCallback? onPlay;
  final ValueChanged<double>? onSeekChanged, onSeekEnd;
  final Widget photoMenu;
  final Widget? photo;
  final List<double>? waveform;
  final VoidCallback? onSeekCancel;
  final bool waveformLoading;

  String _time(Duration value) =>
      '${value.inMinutes.toString().padLeft(2, '0')}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(actions: [photoMenu]),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AritoriaSpace.maxWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            children: [
              Text(
                authorName?.trim().isNotEmpty == true
                    ? 'Historia de ${authorName!.trim()}'
                    : 'Historia',
                style: AritoriaType.action.copyWith(
                  fontSize: 13,
                  letterSpacing: 1.3,
                  color: AritoriaColors.sage,
                ),
              ),
              const SizedBox(height: 10),
              QuestionText(
                question,
                style: AritoriaType.section.copyWith(
                  fontSize: 32,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 17,
                    color: AritoriaColors.muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$date${recipientName?.trim().isNotEmpty == true ? ' · Para ${recipientName!.trim()}' : ''}',
                      style: AritoriaType.caption.copyWith(fontSize: 14),
                    ),
                  ),
                ],
              ),
              if (photo != null) ...[
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: photo!,
                ),
              ],
              const SizedBox(height: 24),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AritoriaColors.sage.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      IconButton.filled(
                        tooltip: loading
                            ? 'Cargando audio...'
                            : playing
                            ? 'Pausar'
                            : 'Reproducir historia',
                        onPressed: onPlay,
                        style: IconButton.styleFrom(
                          fixedSize: const Size(58, 58),
                          backgroundColor: AritoriaColors.olive,
                          foregroundColor: AritoriaColors.onPhoto,
                        ),
                        icon: loading
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 32,
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          children: [
                            if (waveform != null && waveform!.isNotEmpty)
                              StoryWaveformView(
                                samples: waveform!,
                                progress: duration > Duration.zero
                                    ? (position.inMicroseconds /
                                              duration.inMicroseconds)
                                          .clamp(0.0, 1.0)
                                    : 0,
                                onChanged: onSeekChanged,
                                onChangeEnd: onSeekEnd,
                                onCancel: onSeekCancel,
                              )
                            else if (waveformLoading)
                              const SizedBox(
                                height: 48,
                                child: Center(
                                  child: SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      key: ValueKey('story-waveform-loading'),
                                      strokeWidth: 2,
                                      color: AritoriaColors.sage,
                                      semanticsLabel:
                                          'Preparando la onda de audio',
                                    ),
                                  ),
                                ),
                              )
                            else
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 5,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 12,
                                  ),
                                ),
                                child: Slider(
                                  key: const ValueKey('story-seek'),
                                  semanticFormatterCallback: (_) =>
                                      '${_time(position)} de ${_time(duration)}',
                                  value: duration > Duration.zero
                                      ? (position.inMicroseconds /
                                                duration.inMicroseconds)
                                            .clamp(0.0, 1.0)
                                      : 0,
                                  onChanged: onSeekChanged,
                                  onChangeEnd: onSeekEnd,
                                  activeColor: AritoriaColors.olive,
                                  inactiveColor: AritoriaColors.sage.withValues(
                                    alpha: .35,
                                  ),
                                ),
                              ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        _time(position),
                                        style: AritoriaType.caption,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        _time(duration),
                                        style: AritoriaType.caption,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(
                    'Transcripción',
                    style: AritoriaType.body.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AritoriaColors.sage.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      child: Text(
                        'PRÓXIMAMENTE',
                        style: AritoriaType.caption.copyWith(
                          fontSize: 10,
                          color: AritoriaColors.sage,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Aquí podrás leer la transcripción de esta historia.',
                style: AritoriaType.caption.copyWith(fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
