import 'dart:io';
import 'dart:ui' as ui;

import 'package:family_stories_app/design/aritoria_design.dart';
import 'package:family_stories_app/models/question_request.dart';
import 'package:family_stories_app/models/user_profile.dart';
import 'package:family_stories_app/services/received_request_details_service.dart';
import 'package:family_stories_app/services/visible_account_avatar_service.dart';
import 'package:family_stories_app/widgets/account_avatar_view.dart';
import 'package:family_stories_app/widgets/aritoria_home_view.dart';
import 'package:family_stories_app/widgets/aritoria_requests_view.dart';
import 'package:family_stories_app/widgets/question_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' as fixtures;

class _Avatars extends VisibleAccountAvatarService {
  @override
  UserProfile? cached(String id) => const UserProfile(
    id: 'sender-user-id',
    name: 'Usuario A',
    avatarKey: 'avatar_01',
  );
  @override
  Future<UserProfile?> load(String id) async => cached(id);
}

List<QuestionRequest> _requests({bool answered = false}) => [
  for (final (index, question) in [
    '¿Cómo era tu casa cuando eras pequeño/a?',
    '¿Qué época de tu vida recuerdas con más cariño?',
  ].indexed)
    fixtures.testQuestionRequest(
      id: 'q$index',
      recipientId: 'recipient',
      questionText: question,
      createdAt: DateTime(2026, 10, 4),
      status: answered
          ? QuestionRequestStatus.answered
          : QuestionRequestStatus.pending,
      answeredAt: answered ? DateTime(2026, 10, 5) : null,
    ),
];

Widget _app({
  bool answered = false,
  int pendingCount = 2,
  ValueChanged<int>? onTab,
  ValueChanged<QuestionRequest>? onRequest,
  Future<void> Function()? onRefresh,
  VisibleAccountAvatarService? avatars,
  double scale = 1,
  Widget? status,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AritoriaDesign.theme(),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(
      body: SafeArea(
        child: AritoriaRequestsView(
          requests: _requests(answered: answered),
          pendingCount: pendingCount,
          showAnswers: answered,
          status: status,
          avatarService: avatars,
          details: const {
            'q0': ReceivedRequestDetails(
              senderName: 'Usuario A',
              durationSeconds: 75,
            ),
            'q1': ReceivedRequestDetails(
              senderName: 'Usuario E',
              durationSeconds: 90,
            ),
          },
          onRefresh: onRefresh ?? () async {},
          onTabChanged: onTab ?? (_) {},
          onRequestTap: onRequest ?? (_) {},
        ),
      ),
      bottomNavigationBar: AritoriaNavigation(selected: 3, onSelect: (_) {}),
    ),
  ),
);

void main() {
  testWidgets(
    'editorial list reuses sender avatars, joined questions and original row action',
    (tester) async {
      final avatars = _Avatars();
      QuestionRequest? opened;
      int? tab;
      await tester.pumpWidget(
        _app(
          avatars: avatars,
          onTab: (value) => tab = value,
          onRequest: (request) => opened = request,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Preguntas para ti (2)'), findsOneWidget);
      expect(
        find.text(
          'Preguntas que tus familiares te han hecho para conocer mejor tu historia.',
        ),
        findsOneWidget,
      );
      expect(find.byType(AccountAvatarView), findsNWidgets(2));
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));
      final question = tester.widget<QuestionText>(
        find.byType(QuestionText).first,
      );
      expect(question.style!.fontFamily, 'Lora');
      expect(question.data, contains('pequeño\u2060/\u2060a'));
      expect(question.semanticsLabel, _requests().first.questionText);
      expect(find.text('De Usuario A · 04/10/2026'), findsOneWidget);
      await tester.tap(find.textContaining('casa'));
      expect(opened!.id, 'q0');
      expect(opened!.questionText, _requests().first.questionText);
      await tester.tap(find.text('Historias que has contado'));
      expect(tab, 1);
      await tester.pumpWidget(const SizedBox());
      avatars.dispose();
    },
  );

  testWidgets(
    'answered tab retains count, dates, duration and playback entry',
    (tester) async {
      QuestionRequest? opened;
      await tester.pumpWidget(
        _app(answered: true, onRequest: (request) => opened = request),
      );
      await tester.pumpAndSettle();
      expect(find.text('Preguntas para ti (2)'), findsOneWidget);
      expect(find.byType(AccountAvatarView), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNWidgets(2));
      expect(
        find.text('Para Usuario A · 05/10/2026\u00a0·\u00a01:15'),
        findsOneWidget,
      );
      await tester.tap(find.textContaining('casa'));
      expect(opened!.status, QuestionRequestStatus.answered);
    },
  );

  for (final size in [const Size(320, 640), const Size(640, 320)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'horizontal selector remains usable at $size and scale $scale',
        (tester) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          int? tab;
          await tester.pumpWidget(
            _app(scale: scale, onTab: (value) => tab = value),
          );
          await tester.pumpAndSettle();
          final list = find
              .descendant(
                of: find.byKey(const ValueKey('questions-scroll')),
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.scrollUntilVisible(
            find.text('Historias que has contado'),
            80,
            scrollable: list,
          );
          await tester.ensureVisible(find.text('Historias que has contado'));
          await tester.pumpAndSettle();
          final viewport = tester.getRect(
            find.byKey(const ValueKey('questions-scroll')),
          );
          // At 200% a label can be wider than the phone; tap its visible part.
          await tester.tapAt(
            tester
                .getRect(find.text('Historias que has contado'))
                .intersect(viewport)
                .center,
          );
          expect(tab, 1);
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(
            find.text('Preguntas para ti (2)'),
            -80,
            scrollable: list,
          );
          await tester.ensureVisible(find.text('Preguntas para ti (2)'));
          await tester.pumpAndSettle();
          await tester.tapAt(
            tester
                .getRect(find.text('Preguntas para ti (2)'))
                .intersect(viewport)
                .center,
          );
          expect(tab, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final width in [320.0, 390.0]) {
    testWidgets('answered date and duration stay on one line at $width px', (
      tester,
    ) async {
      await (FontLoader(
        'Nunito Sans',
      )..addFont(rootBundle.load('assets/fonts/NunitoSans.ttf'))).load();
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_app(answered: true));
      await tester.pumpAndSettle();
      final metadataFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.semanticsLabel ==
                'Para Usuario A · 05/10/2026 · 1:15',
      );
      final metadata = tester.widget<Text>(metadataFinder).data!;
      if (width == 320) {
        expect(
          metadata,
          'Para Usuario A\n05/10/2026\u00a0·\u00a01:15',
        );
      }
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.text(metadata),
          matching: find.byType(RichText),
        ),
      );
      final dateIndex = metadata.indexOf('05/10/2026');
      final durationIndex = metadata.indexOf('1:15');
      final date = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: dateIndex, extentOffset: dateIndex + 10),
      );
      final duration = paragraph.getBoxesForSelection(
        TextSelection(
          baseOffset: durationIndex,
          extentOffset: durationIndex + 4,
        ),
      );
      expect(date, hasLength(1));
      expect(duration, hasLength(1));
      expect(date.single.top, duration.single.top);
      expect(
        tester.widget<Text>(find.text(metadata)).semanticsLabel,
        'Para Usuario A · 05/10/2026 · 1:15',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'status keeps header and selector; pull to refresh is available',
    (tester) async {
      var refreshes = 0;
      await tester.pumpWidget(
        _app(
          status: const Text('No tienes preguntas pendientes.'),
          onRefresh: () async {
            refreshes++;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReceivedRequestRow), findsNothing);
      expect(find.text('No tienes preguntas pendientes.'), findsOneWidget);
      expect(find.text('Preguntas para ti (2)'), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('questions-scroll')),
        const Offset(0, 350),
      );
      await tester.pumpAndSettle();
      expect(refreshes, 1);
    },
  );

  testWidgets('questions visual preview with bundled fonts', (tester) async {
    if (!const bool.fromEnvironment('ARITORIA_PREVIEW')) return;
    for (final (family, path) in [
      ('Lora', 'assets/fonts/Lora.ttf'),
      ('Nunito Sans', 'assets/fonts/NunitoSans.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(path))).load();
    }
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey();
    final avatars = _Avatars();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: _app(avatars: avatars),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/avatars/avatar_01.png'),
        tester.element(find.byType(AritoriaRequestsView)),
      );
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await File('.dart_tool/questions-preview.png')
          .writeAsBytes(data.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    avatars.dispose();
  });

  testWidgets('long request lists build only the visible rows (C-14)', (
    tester,
  ) async {
    final many = [
      for (var i = 0; i < 300; i++)
        fixtures.testQuestionRequest(
          id: 'q$i',
          recipientId: 'recipient',
          questionText: 'Pregunta número $i',
          createdAt: DateTime(2026, 10, 4),
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AritoriaDesign.theme(),
        home: Scaffold(
          body: AritoriaRequestsView(
            requests: many,
            pendingCount: many.length,
            showAnswers: false,
            status: null,
            details: const {},
            onRefresh: () async {},
            onTabChanged: (_) {},
            onRequestTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final built = find.byType(ReceivedRequestRow).evaluate().length;
    expect(built, greaterThan(0));
    expect(
      built,
      lessThan(300),
      reason: 'C-14: the whole request list was built eagerly.',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tab labels are measured once and not on every rebuild (C-15)', (
    tester,
  ) async {
    debugTabLabelLayouts = 0;
    addTearDown(() => debugTabLabelLayouts = 0);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(debugTabLabelLayouts, 2);
    // Plain rebuilds (a different selected tab) must reuse the measures.
    await tester.pumpWidget(_app(answered: true));
    await tester.pumpAndSettle();
    expect(
      debugTabLabelLayouts,
      2,
      reason: 'C-15: the tab labels were re-measured on a plain rebuild.',
    );
    // A changed label set (new pending count) re-measures once.
    await tester.pumpWidget(_app(answered: true, pendingCount: 5));
    await tester.pumpAndSettle();
    expect(debugTabLabelLayouts, 4);
    expect(find.text('Preguntas para ti (5)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
