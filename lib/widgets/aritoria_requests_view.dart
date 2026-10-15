import 'package:flutter/material.dart';

import '../design/aritoria_design.dart';
import '../models/question_request.dart';
import '../services/received_request_details_service.dart';
import '../services/visible_account_avatar_service.dart';
import 'aritoria_home_view.dart';

/// Presentation of the existing received-questions and answered-stories lists.
class AritoriaRequestsView extends StatelessWidget {
  const AritoriaRequestsView({
    required this.requests,
    required this.details,
    required this.pendingCount,
    required this.showAnswers,
    required this.status,
    required this.onRefresh,
    required this.onTabChanged,
    required this.onRequestTap,
    this.avatarService,
    super.key,
  });

  final List<QuestionRequest> requests;
  final Map<String, ReceivedRequestDetails> details;
  final int pendingCount;
  final bool showAnswers;
  final Widget? status;
  final Future<void> Function() onRefresh;
  final ValueChanged<int> onTabChanged;
  final ValueChanged<QuestionRequest> onRequestTap;
  final VisibleAccountAvatarService? avatarService;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: ListView(
      key: const ValueKey('questions-scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AritoriaSpace.lg),
      children: [
        Text('Preguntas', style: AritoriaType.brand.copyWith(fontSize: 36)),
        const SizedBox(height: AritoriaSpace.sm + AritoriaSpace.xs),
        Text(
          'Preguntas que tus familiares te han hecho para conocer mejor tu historia.',
          style: AritoriaType.body.copyWith(color: AritoriaColors.muted),
        ),
        const SizedBox(height: AritoriaSpace.lg),
        _RequestTabs(
          pendingCount: pendingCount,
          showAnswers: showAnswers,
          onChanged: onTabChanged,
        ),
        const SizedBox(height: AritoriaSpace.lg),
        if (status != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AritoriaSpace.md),
            child: status!,
          )
        else
          for (final request in requests)
            ReceivedRequestRow(
              request: request,
              details: details[request.id],
              editorial: true,
              avatarService: avatarService,
              onTap: () => onRequestTap(request),
            ),
      ],
    ),
  );
}

class _RequestTabs extends StatelessWidget {
  const _RequestTabs({
    required this.pendingCount,
    required this.showAnswers,
    required this.onChanged,
  });
  final int pendingCount;
  final bool showAnswers;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = [
      'Preguntas para ti ($pendingCount)',
      'Historias que has contado',
    ];
    final style = AritoriaType.action.copyWith(fontSize: 13);
    final widths = labels.map((label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width.ceilToDouble() + AritoriaSpace.lg;
      painter.dispose();
      return width;
    }).toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AritoriaColors.line),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: LayoutBuilder(
          builder: (context, layout) {
            final scroll = widths.reduce((a, b) => a + b) > layout.maxWidth;
            final extra = scroll
                ? 0.0
                : (layout.maxWidth - widths.reduce((a, b) => a + b)) / 2;
            final row = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < labels.length; index++)
                  SizedBox(
                    width: widths[index] + extra,
                    child: Semantics(
                      button: true,
                      selected: showAnswers == (index == 1),
                      child: Material(
                        color: showAnswers == (index == 1)
                            ? AritoriaColors.sage.withValues(alpha: 0.3)
                            : AritoriaColors.transparent,
                        borderRadius: BorderRadius.circular(24),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => onChanged(index),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 44),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Center(
                                child: Text(
                                  labels[index],
                                  maxLines: 1,
                                  softWrap: false,
                                  style: style.copyWith(
                                    color: showAnswers == (index == 1)
                                        ? AritoriaColors.olive
                                        : AritoriaColors.muted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
            // Keep the full labels and accessible text sizes on narrow screens.
            return scroll
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: row,
                  )
                : row;
          },
        ),
      ),
    );
  }
}
