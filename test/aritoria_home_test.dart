import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:family_stories_app/design/aritoria_design.dart';
import 'package:family_stories_app/models/family_member.dart';
import 'package:family_stories_app/models/question_request.dart';
import 'package:family_stories_app/screens/add_family_member_screen.dart';
import 'package:family_stories_app/screens/family_member_screen.dart';
import 'package:family_stories_app/screens/home_screen.dart';
import 'package:family_stories_app/screens/profile_screen.dart';
import 'package:family_stories_app/screens/questions_screen.dart';
import 'package:family_stories_app/services/family_member_photo_service.dart';
import 'package:family_stories_app/services/profile_image_picker.dart';
import 'package:family_stories_app/services/received_request_details_service.dart';
import 'package:family_stories_app/widgets/aritoria_home_view.dart';
import 'package:family_stories_app/widgets/family_member_photo_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' as fixtures;

const _pepe = FamilyMember(
  id: 'pepe',
  name: 'Pepe',
  relationship: 'Padre/Madre',
);
const _ana = FamilyMember(id: 'ana', name: 'Ana', relationship: 'Abuelo/a');

Finder _heroTitle(String name) => find.byWidgetPredicate(
  (widget) =>
      widget is Text &&
      widget.semanticsLabel == 'Hay historias que solo\n$name puede contarte',
);

class _Photos extends FamilyMemberPhotoService {
  _Photos({Uint8List? bytes}) : bytes = bytes ?? fixtures.testPickedImage.bytes;
  final Uint8List bytes;
  final paths = <String?>[];
  @override
  Uint8List? cachedPhoto(FamilyMember member) =>
      member.photoPath == null ? null : bytes;
  @override
  Future<Uint8List> load(FamilyMember member) async {
    paths.add(member.photoPath);
    return bytes;
  }

  @override
  Future<FamilyMember> save(
    FamilyMember member,
    PickedProfileImage? image,
  ) async => member;
}

class _Details implements ReceivedRequestDetailsService {
  _Details({this.fail = false, this.pending});
  final bool fail;
  final Completer<Map<String, ReceivedRequestDetails>>? pending;
  @override
  Future<Map<String, ReceivedRequestDetails>> load(List<String> ids) async {
    if (fail) throw StateError('RPC not installed');
    if (pending != null) return pending!.future;
    return {
      for (final id in ids)
        id: const ReceivedRequestDetails(
          senderName: 'Iván',
          durationSeconds: 75,
        ),
    };
  }
}

fixtures.FakeQuestionRequestService _requests() =>
    fixtures.FakeQuestionRequestService(
      pendingByRecipient: {
        fixtures.testAuthUser.id: [
          for (var i = 1; i <= 5; i++)
            fixtures.testQuestionRequest(
              id: 'q$i',
              recipientId: fixtures.testAuthUser.id,
              questionText: 'Pregunta $i',
              createdAt: DateTime.utc(2026, 10, i),
            ),
        ],
      },
      answeredByRecipient: {
        fixtures.testAuthUser.id: [
          for (var i = 1; i <= 5; i++)
            fixtures.testQuestionRequest(
              id: 'a$i',
              recipientId: fixtures.testAuthUser.id,
              questionText: 'Historia $i',
              status: QuestionRequestStatus.answered,
              answeredAt: DateTime.utc(2026, 10, i),
            ),
        ],
      },
    );

void main() {
  for (final count in [0, 1, 2]) {
    testWidgets(
      'notification bell opens received questions; header action with $count pending',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final requests = fixtures.FakeQuestionRequestService(
          pendingByRecipient: {
            fixtures.testAuthUser.id: [
              for (var i = 0; i < count; i++)
                fixtures.testQuestionRequest(
                  id: 'pending-$i',
                  questionText: 'Pendiente $i',
                  recipientId: fixtures.testAuthUser.id,
                ),
            ],
          },
        );
        await tester.pumpWidget(
          fixtures.testApp(
            fixtures.MemoryFamilyMemberStorage(),
            authService: fixtures.FakeAuthService(fixtures.testAuthUser),
            questionRequestService: requests,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('Notificaciones'), findsOneWidget);
        expect(find.text('Familia'), findsOneWidget);
        expect(
          find.text('Ver todas'),
          count == 0 ? findsNothing : findsOneWidget,
        );
        expect(
          tester.widget<Text>(find.text('Preguntas para ti')).style,
          AritoriaType.homeSection,
        );
        if (count > 0) {
          await tester.ensureVisible(find.text('Ver todas'));
          await tester.tap(find.text('Ver todas'));
          await tester.pumpAndSettle();
          expect(find.byType(ChoiceChip), findsNWidgets(2));
          expect(find.byType(ReceivedRequestRow), findsNWidgets(count));
          await tester.tap(find.text('Inicio'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byTooltip('Notificaciones'));
        await tester.pumpAndSettle();
        expect(find.byType(ChoiceChip), findsNWidgets(2));
        if (count == 0) {
          expect(find.text('No tienes preguntas pendientes.'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  test(
    'hero keeps first-member fallback and prefers an own photo without avatar metadata',
    () {
      expect(selectHomeHero([]), isNull);
      expect(selectHomeHero([_pepe, _ana]), same(_pepe));
      final photographed = _ana.withPhotoPath('own/ana/photo.png');
      expect(selectHomeHero([_pepe, photographed]), same(photographed));
      expect(selectHomeHero([_pepe, photographed]), same(photographed));
    },
  );

  testWidgets('hero opens the existing questions flow and keeps its theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      fixtures.testApp(fixtures.MemoryFamilyMemberStorage(members: [_pepe])),
    );
    await tester.pumpAndSettle();
    expect(_heroTitle('Pepe'), findsOneWidget);
    await tester.tap(find.text('Conoce su historia'));
    await tester.pumpAndSettle();
    expect(find.byType(QuestionsScreen), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(QuestionsScreen)))
          .colorScheme
          .primary,
      isNot(AritoriaColors.olive),
    );
  });

  testWidgets(
    'onboarding and all three quick create actions reuse existing routes',
    (tester) async {
      await tester.pumpWidget(
        fixtures.testApp(fixtures.MemoryFamilyMemberStorage()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Añadir ser querido'));
      await tester.pumpAndSettle();
      expect(find.byType(AddFamilyMemberScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      for (final action in [
        'Grabar una historia',
        'Enviar una pregunta',
        'Añadir ser querido',
      ]) {
        await tester.tap(find.byTooltip('Crear'));
        await tester.pumpAndSettle();
        final sheet = find.byType(BottomSheet);
        expect(
          find.descendant(of: sheet, matching: find.byType(ListTile)),
          findsNWidgets(3),
        );
        await tester.tap(
          find.descendant(of: sheet, matching: find.text(action)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AddFamilyMemberScreen), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'quick recording and sending select a member then open existing questions',
    (tester) async {
      await tester.pumpWidget(
        fixtures.testApp(
          fixtures.MemoryFamilyMemberStorage(members: [_pepe, _ana]),
        ),
      );
      await tester.pumpAndSettle();
      for (final action in ['Grabar una historia', 'Enviar una pregunta']) {
        await tester.tap(find.byTooltip('Crear'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text('Pepe'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(QuestionsScreen), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'navigation switches roots without duplicate stacks and Android back returns Home',
    (tester) async {
      await tester.pumpWidget(
        fixtures.testApp(fixtures.MemoryFamilyMemberStorage(members: [_pepe])),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Familia'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pepe'));
      await tester.pumpAndSettle();
      expect(find.byType(FamilyMemberScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Atrás'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preguntas'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Aritoria'), findsOneWidget);
      expect(find.byType(HomeScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Perfil'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Aritoria'), findsOneWidget);
    },
  );

  testWidgets(
    'Home shows two most recent rows and full lists remain accessible',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        fixtures.testApp(
          fixtures.MemoryFamilyMemberStorage(),
          authService: fixtures.FakeAuthService(fixtures.testAuthUser),
          questionRequestService: _requests(),
          receivedRequestDetailsService: _Details(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Historia 4'),
        250,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('home-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Historia 5'), findsOneWidget);
      expect(find.text('Historia 4'), findsOneWidget);
      expect(find.text('Historia 3'), findsNothing);
      expect(find.text('Para Iván · 05/10/2026 · 1:15'), findsOneWidget);
      await tester.ensureVisible(find.text('Ver todas').last);
      await tester.tap(find.text('Ver todas').last);
      await tester.pumpAndSettle();
      expect(find.text('Historia 3'), findsOneWidget);
      await tester.tap(find.text('Preguntas para ti'));
      await tester.pumpAndSettle();
      expect(find.text('Pregunta 5'), findsOneWidget);
      expect(find.text('Pregunta 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing optional RPC keeps rows and playback entry accessible', (
    tester,
  ) async {
    await tester.pumpWidget(
      fixtures.testApp(
        fixtures.MemoryFamilyMemberStorage(),
        authService: fixtures.FakeAuthService(fixtures.testAuthUser),
        questionRequestService: _requests(),
        receivedRequestDetailsService: _Details(fail: true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preguntas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Historias que has contado'));
    await tester.pumpAndSettle();
    expect(find.text('Para quien te preguntó · 05/10/2026'), findsOneWidget);
    await tester.tap(find.text('Historia 5'));
    await tester.pumpAndSettle();
    expect(find.text('No se pudo abrir esta respuesta.'), findsOneWidget);
  });

  testWidgets('late enrichment cannot leak names into another session', (
    tester,
  ) async {
    final pending = Completer<Map<String, ReceivedRequestDetails>>();
    final auth = fixtures.FakeAuthService(fixtures.testAuthUser);
    await tester.pumpWidget(
      fixtures.testApp(
        fixtures.MemoryFamilyMemberStorage(),
        authService: auth,
        questionRequestService: _requests(),
        receivedRequestDetailsService: _Details(pending: pending),
      ),
    );
    await tester.pumpAndSettle();
    auth.setUser(null);
    await tester.pumpAndSettle();
    pending.complete({
      'a5': const ReceivedRequestDetails(senderName: 'Private name'),
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Private name'), findsNothing);
  });

  for (final count in [0, 1, 20]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('320px Home handles $count members at text scale $scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final members = [
          for (var i = 0; i < count; i++)
            FamilyMember(
              id: 'member$i',
              name: 'Un nombre especialmente largo $i',
              relationship: 'Abuelo/a',
            ),
        ];
        await tester.pumpWidget(
          fixtures.testApp(
            fixtures.MemoryFamilyMemberStorage(members: members),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const ValueKey('home-scroll')),
          const Offset(0, -600),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'hero and circular portrait reuse the same service and cached photo',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final photos = _Photos();
      await tester.pumpWidget(
        fixtures.testApp(
          fixtures.MemoryFamilyMemberStorage(
            members: [_pepe, _ana.withPhotoPath('own/ana/photo.png')],
          ),
          familyMemberPhotoService: photos,
        ),
      );
      await tester.pumpAndSettle();
      expect(_heroTitle('Ana'), findsOneWidget);
      expect(photos.paths, isEmpty);
      expect(find.byType(FamilyMemberPhotoView), findsNWidgets(3));
    },
  );

  for (final dimensions in [const Size(320, 640), const Size(640, 320), null]) {
    testWidgets(
      'compact hero renders ${dimensions ?? 'no photo'} with a natural crop',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final family in ['Fraunces', 'Nunito Sans']) {
          await (FontLoader(family)..addFont(
                rootBundle.load(
                  'assets/fonts/${family == 'Fraunces' ? 'Fraunces' : 'NunitoSans'}.ttf',
                ),
              ))
              .load();
        }
        final bytes = dimensions == null
            ? fixtures.testPickedImage.bytes
            : (await tester.runAsync(() async {
                final recorder = ui.PictureRecorder();
                final canvas = Canvas(recorder);
                canvas.drawRect(
                  Offset.zero & dimensions,
                  Paint()..color = const Color(0xFFBDAA87),
                );
                canvas.drawCircle(
                  Offset(dimensions.width / 2, dimensions.height / 3),
                  40,
                  Paint()..color = const Color(0xFF6C6D65),
                );
                final picture = recorder.endRecording();
                final image = await picture.toImage(
                  dimensions.width.toInt(),
                  dimensions.height.toInt(),
                );
                final data = (await image.toByteData(
                  format: ui.ImageByteFormat.png,
                ))!;
                image.dispose();
                picture.dispose();
                return data.buffer.asUint8List();
              }))!;
        final original = Uint8List.fromList(bytes);
        final photos = _Photos(bytes: bytes);
        await tester.pumpWidget(
          fixtures.testApp(
            fixtures.MemoryFamilyMemberStorage(
              members: [
                dimensions == null
                    ? _pepe
                    : _pepe.withPhotoPath('own/pepe/photo.png'),
              ],
            ),
            familyMemberPhotoService: photos,
          ),
        );
        await tester.pumpAndSettle();
        final hero = find.byKey(const ValueKey('home-hero'));
        final size = tester.getSize(hero);
        final titleHeight = tester.getSize(_heroTitle('Pepe')).height;
        final oldHeight =
            (titleHeight + 145 + AritoriaSpace.lg * 2 + AritoriaSpace.md + 48)
                .clamp(350.0, double.infinity);
        expect(size.height / oldHeight, inInclusiveRange(0.74, 0.80));
        final images = find.descendant(of: hero, matching: find.byType(Image));
        if (dimensions == null) {
          expect(images, findsNothing);
        } else {
          final image = tester.widget<Image>(images);
          expect(image.fit, BoxFit.cover);
          expect(image.alignment, const Alignment(0, -0.15));
          expect(tester.getSize(images), size);
        }
        expect(bytes, original);
        expect(photos.paths, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [320.0, 390.0]) {
    for (final name in ['Mavi', 'Pepe', 'María José']) {
      testWidgets('hero avoids isolated solo at $width px for $name', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await (FontLoader(
          'Fraunces',
        )..addFont(rootBundle.load('assets/fonts/Fraunces.ttf'))).load();
        final member = FamilyMember(
          id: 'person',
          name: name,
          relationship: 'Otro',
        );
        await tester.pumpWidget(
          fixtures.testApp(
            fixtures.MemoryFamilyMemberStorage(members: [member]),
          ),
        );
        await tester.pumpAndSettle();
        final title = tester.widget<Text>(_heroTitle(name));
        expect(title.style!.fontSize, inInclusiveRange(24, 30));
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: _heroTitle(name),
            matching: find.byType(RichText),
          ),
        );
        const opening = 'Hay historias que solo';
        final ending = paragraph.getBoxesForSelection(
          TextSelection(
            baseOffset: opening.indexOf('que'),
            extentOffset: opening.length,
          ),
        );
        expect(ending.map((box) => box.top).toSet(), hasLength(1));
        if (width >= 390) {
          final firstLine = paragraph.getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: opening.length),
          );
          expect(firstLine.map((box) => box.top).toSet(), hasLength(1));
        }
        expect(title.semanticsLabel, '$opening\n$name puede contarte');
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final remote in [false, true]) {
    testWidgets('creates and round trips Nieto/a with remote=$remote', (
      tester,
    ) async {
      final storage = fixtures.MemoryFamilyMemberStorage();
      final members = fixtures.FakeFamilyMemberService();
      await tester.pumpWidget(
        fixtures.testApp(
          storage,
          authService: fixtures.FakeAuthService(
            remote ? fixtures.testAuthUser : null,
          ),
          familyMemberService: members,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Crear'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Añadir ser querido').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Nico');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Nieto/a').last);
      await tester.tap(find.text('Nieto/a').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Guardar'));
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      final member = (remote ? members.members : storage.members).single;
      expect(member.relationship, 'Nieto/a');
      expect(FamilyMember.fromJson(member.toJson()).relationship, 'Nieto/a');
      expect(
        FamilyMember.fromSupabaseJson({
          ...member.toJson(),
          'relationship': member.relationship,
        }).relationship,
        'Nieto/a',
      );
      if (remote) expect(members.createdRelationships, ['Nieto/a']);
    });
  }

  testWidgets('visual preview with bundled fonts', (tester) async {
    for (final license in ['fraunces-OFL.txt', 'nunitosans-OFL.txt']) {
      expect(
        await rootBundle.loadString('assets/fonts/$license'),
        contains('SIL OPEN FONT LICENSE'),
      );
    }
    for (final family in ['Fraunces', 'Nunito Sans']) {
      final loader = FontLoader(family)
        ..addFont(
          rootBundle.load(
            'assets/fonts/${family == 'Fraunces' ? 'Fraunces' : 'NunitoSans'}.ttf',
          ),
        );
      await loader.load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: fixtures.testApp(
          fixtures.MemoryFamilyMemberStorage(members: [_pepe, _ana]),
          authService: fixtures.FakeAuthService(fixtures.testAuthUser),
          familyMemberService: fixtures.FakeFamilyMemberService(
            members: [_pepe, _ana],
          ),
          questionRequestService: _requests(),
          receivedRequestDetailsService: _Details(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Aritoria'), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (!const bool.fromEnvironment('ARITORIA_PREVIEW')) return;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File('.dart_tool/aritoria-preview.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
  });
}
