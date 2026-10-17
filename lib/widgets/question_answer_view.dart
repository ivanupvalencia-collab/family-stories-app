import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/question_answer_hints.dart';
import '../design/aritoria_design.dart';
import '../models/question.dart';
import 'question_text.dart';

enum QuestionAnswerStage { initial, recording, review, sent }

/// Presentation only: recording, playback, submission and routes stay in screens.
class QuestionAnswerView extends StatelessWidget {
  const QuestionAnswerView({
    required this.question,
    required this.stage,
    required this.onStart,
    this.startLabel = 'Grabar respuesta',
    this.duration = Duration.zero,
    this.playing = false,
    this.playbackProgress = 0,
    this.busy = false,
    this.submitting = false,
    this.onStop,
    this.onCancel,
    this.onPlay,
    this.onSend,
    this.onRecordAgain,
    this.onReturn,
    this.sentAt,
    this.photoControls,
    this.photoBytes,
    this.senderName,
    this.onSeek,
    super.key,
  });

  final Question question;
  final QuestionAnswerStage stage;
  final VoidCallback? onStart,
      onStop,
      onCancel,
      onPlay,
      onSend,
      onRecordAgain,
      onReturn;
  final String startLabel;
  final Duration duration;
  final double playbackProgress;
  final bool playing, busy, submitting;
  final DateTime? sentAt;
  final Widget? photoControls;
  final Uint8List? photoBytes;
  final String? senderName;
  final ValueChanged<double>? onSeek;

  bool get _sent => stage == QuestionAnswerStage.sent;
  String get _duration =>
      '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

  Widget _button(
    String label,
    IconData? icon,
    VoidCallback? callback, {
    bool secondary = false,
  }) {
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(56),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      backgroundColor: secondary
          ? AritoriaColors.sage.withValues(alpha: 0.18)
          : AritoriaColors.olive,
      foregroundColor: secondary
          ? AritoriaColors.olive
          : AritoriaColors.onPhoto,
      textStyle: AritoriaType.body.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    );
    if (icon == null) {
      return FilledButton(
        style: style,
        onPressed: busy ? null : callback,
        child: Text(label),
      );
    }
    return FilledButton.icon(
      style: style,
      onPressed: busy ? null : callback,
      icon: submitting && !secondary
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 20),
      label: Text(label),
    );
  }

  Widget _recording(BuildContext context) => Column(
    children: [
      Semantics(
        label: 'Grabando',
        child: SizedBox.square(
          dimension: 164,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.error
                  .withValues(alpha: 0.035),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.error
                      .withValues(alpha: 0.09),
                ),
                child: Center(
                  child: SizedBox.square(
                    dimension: 80,
                    child: IconButton.filled(
                      tooltip: 'Detener grabación',
                      onPressed: busy ? null : onStop,
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        foregroundColor: AritoriaColors.onPhoto,
                      ),
                      icon: const Icon(Icons.stop_rounded, size: 34),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        _duration,
        style: AritoriaType.body.copyWith(fontSize: 20),
        semanticsLabel: 'Tiempo de grabación: $_duration',
      ),
    ],
  );

  Widget _review() => Semantics(
    label: 'Grabación terminada',
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        border: Border.all(color: AritoriaColors.line),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          IconButton.filled(
            tooltip: playing ? 'Pausar' : 'Reproducir',
            onPressed: busy ? null : onPlay,
            style: IconButton.styleFrom(
              backgroundColor: AritoriaColors.olive,
              foregroundColor: AritoriaColors.onPhoto,
              fixedSize: const Size(48, 48),
            ),
            icon: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 30,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 44,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  void seekAt(Offset position) {
                    if (constraints.maxWidth > 0) {
                      onSeek?.call(
                        (position.dx / constraints.maxWidth).clamp(0.0, 1.0),
                      );
                    }
                  }

                  return Semantics(
                    label: 'Cambiar posición del audio',
                    value: '${(playbackProgress * 100).round()} %',
                    child: GestureDetector(
                      key: const ValueKey('answer-waveform'),
                      behavior: HitTestBehavior.opaque,
                      onTapUp: onSeek == null
                          ? null
                          : (event) => seekAt(event.localPosition),
                      onHorizontalDragStart: onSeek == null
                          ? null
                          : (event) => seekAt(event.localPosition),
                      onHorizontalDragUpdate: onSeek == null
                          ? null
                          : (event) => seekAt(event.localPosition),
                      child: SizedBox(
                        height: 44,
                        child: CustomPaint(
                          painter: _AudioMotifPainter(playbackProgress),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(_duration, style: AritoriaType.caption.copyWith(fontSize: 14)),
        ],
      ),
    ),
  );

  Widget _thanks() => Column(
    children: [
      Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AritoriaColors.sage.withValues(alpha: 0.2),
        ),
        child: const Icon(
          Icons.check_rounded,
          size: 44,
          color: AritoriaColors.olive,
        ),
      ),
      const SizedBox(height: 24),
      Text(
        '¡Gracias por compartir tu historia!',
        textAlign: TextAlign.center,
        style: AritoriaType.section.copyWith(
          fontSize: 28,
          color: AritoriaColors.olive,
        ),
      ),
      const SizedBox(height: 16),
      Text(
        'Tu respuesta ya ha sido enviada y la podrá escuchar tu familiar muy pronto.',
        textAlign: TextAlign.center,
        style: AritoriaType.body.copyWith(color: AritoriaColors.muted),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final date = sentAt?.toLocal();
    final sender = senderName?.trim();
    final status = _sent
        ? 'Respuesta enviada${date == null ? '' : ' · ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}'}'
        : 'Enviada por ${sender == null || sender.isEmpty ? 'otro familiar' : sender} · Pendiente';
    return Theme(
      data: AritoriaDesign.theme(),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(
              'Pregunta para ti',
              style: AritoriaType.section.copyWith(
                fontSize: 20,
                color: AritoriaColors.olive,
              ),
            ),
            leading: _sent ? BackButton(onPressed: onReturn) : null,
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AritoriaSpace.maxWidth,
                ),
                child: CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.all(AritoriaSpace.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            QuestionText(
                              question.text,
                              style: AritoriaType.section.copyWith(
                                fontSize: 28,
                                height: 1.18,
                                color: AritoriaColors.olive,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  _sent
                                      ? Icons.check_circle
                                      : Icons.send_outlined,
                                  size: 18,
                                  color: _sent
                                      ? AritoriaColors.olive
                                      : AritoriaColors.muted,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    status,
                                    style: AritoriaType.caption.copyWith(
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (!_sent) ...[
                              const SizedBox(height: 24),
                              Semantics(
                                label: 'Pista para responder',
                                child: Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: AritoriaColors.line.withValues(
                                      alpha: 0.4,
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Text(
                                    answerHintFor(question),
                                    style: AritoriaType.body.copyWith(
                                      fontSize: 14,
                                      height: 1.6,
                                      color: AritoriaColors.muted,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            const Spacer(),
                            if (stage == QuestionAnswerStage.recording)
                              _recording(context),
                            if (stage == QuestionAnswerStage.review) _review(),
                            if (stage == QuestionAnswerStage.review &&
                                photoBytes != null) ...[
                              const SizedBox(height: 16),
                              ClipRRect(
                                key: const ValueKey('answer-photo-preview'),
                                borderRadius: BorderRadius.circular(18),
                                child: Image.memory(
                                  photoBytes!,
                                  width: double.infinity,
                                  height: 160,
                                  fit: BoxFit.cover,
                                  cacheWidth: 1024,
                                  semanticLabel: 'Foto seleccionada',
                                  errorBuilder: (context, error, stack) =>
                                      const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Text(
                                          'No se pudo mostrar la foto seleccionada.',
                                        ),
                                      ),
                                ),
                              ),
                            ],
                            if (_sent) _thanks(),
                            if (stage != QuestionAnswerStage.initial) ...[
                              const SizedBox(height: 24),
                              const Spacer(),
                            ],
                            if (stage == QuestionAnswerStage.initial)
                              _button(startLabel, Icons.mic_outlined, onStart),
                            if (stage == QuestionAnswerStage.recording)
                              _button(
                                'Cancelar',
                                null,
                                onCancel,
                                secondary: true,
                              ),
                            if (stage == QuestionAnswerStage.review) ...[
                              _button(
                                submitting
                                    ? 'Enviando respuesta...'
                                    : 'Enviar respuesta',
                                Icons.send_outlined,
                                onSend,
                              ),
                              const SizedBox(height: 16),
                              _button(
                                'Grabar de nuevo',
                                Icons.refresh,
                                onRecordAgain,
                                secondary: true,
                              ),
                              ?photoControls,
                            ],
                            if (_sent) _button('Volver', null, onReturn),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Decorative amplitudes, colored using the real playback position.
class _AudioMotifPainter extends CustomPainter {
  const _AudioMotifPainter(this.progress);
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    const heights = [
      .2,
      .5,
      .8,
      1.0,
      .7,
      .9,
      .6,
      .3,
      .7,
      .9,
      .5,
      .8,
      .4,
      .3,
      .6,
      1.0,
      .8,
      .4,
      .2,
      .4,
      .6,
      .8,
      .6,
      .3,
    ];
    final paint = Paint()
      ..color = AritoriaColors.muted.withValues(alpha: 0.65)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < heights.length; i++) {
      paint.color = (i + .5) / heights.length <= progress
          ? AritoriaColors.olive
          : AritoriaColors.muted.withValues(alpha: 0.65);
      final x = (i + .5) * size.width / heights.length;
      final half = heights[i] * size.height / 2;
      canvas.drawLine(
        Offset(x, size.height / 2 - half),
        Offset(x, size.height / 2 + half),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AudioMotifPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
