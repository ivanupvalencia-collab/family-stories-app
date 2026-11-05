import 'package:family_stories_app/screens/add_family_member_screen.dart';
import 'package:family_stories_app/services/family_member_photo_service.dart';
import 'package:family_stories_app/widgets/family_member_photo_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' as fixtures;

Future<void> _open(
  WidgetTester tester,
  fixtures.FakeProfileImagePicker picker, {
  Size size = const Size(390, 844),
  double textScale = 1,
  double keyboardHeight = 0,
  ValueChanged<FamilyMemberDraft?>? onSaved,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: keyboardHeight),
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final draft = await Navigator.of(context).push<FamilyMemberDraft>(
                MaterialPageRoute(
                  builder: (_) => AddFamilyMemberScreen(
                    imagePicker: picker,
                    photoService: LocalFamilyMemberPhotoService(
                      storage: fixtures.MemoryFamilyMemberStorage(),
                    ),
                  ),
                ),
              );
              onSaved?.call(draft);
            },
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'círculo y + seleccionan foto y la muestran en el círculo sin botón adicional',
    (tester) async {
      final picker = fixtures.FakeProfileImagePicker(
        result: fixtures.testPickedImage,
      );
      await _open(tester, picker);
      expect(find.text('Añadir ser querido'), findsOneWidget);
      expect(
        find.text('Crea su perfil para guardar sus historias'),
        findsOneWidget,
      );
      expect(find.text('Elegir foto (opcional)'), findsNothing);
      expect(find.text('Añadir foto'), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(find.byKey(const ValueKey('pick_family_member_photo')));
      await tester.pumpAndSettle();
      expect(picker.pickCalls, 1);
      final photo = tester.widget<FamilyMemberPhotoView>(
        find.byType(FamilyMemberPhotoView),
      );
      expect(photo.previewBytes, fixtures.testPickedImage.bytes);
      expect(
        find.descendant(
          of: find.byType(FamilyMemberPhotoView),
          matching: find.byType(ClipOval),
        ),
        findsOneWidget,
      );
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
      await tester.tap(
        find.byKey(const ValueKey('pick_family_member_photo_add')),
      );
      await tester.pumpAndSettle();
      expect(picker.pickCalls, 2);
      await tester.tap(find.text('Quitar foto seleccionada'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
    },
  );

  testWidgets('un error al seleccionar foto no impide usar el formulario', (
    tester,
  ) async {
    final picker = fixtures.FakeProfileImagePicker(
      error: StateError('gallery'),
    );
    await _open(tester, picker);
    await tester.tap(
      find.byKey(const ValueKey('pick_family_member_photo_add')),
    );
    await tester.pumpAndSettle();
    expect(find.text('No se pudo elegir la foto.'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardar'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'pantalla pequeña, teclado y texto ampliado permiten validar y guardar sin foto con Nieto/a',
    (tester) async {
      FamilyMemberDraft? saved;
      await _open(
        tester,
        fixtures.FakeProfileImagePicker(),
        size: const Size(320, 640),
        textScale: 1.6,
        keyboardHeight: 200,
        onSaved: (draft) => saved = draft,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Guardar'));
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Introduce un nombre'), findsOneWidget);
      final field = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>),
      );
      expect(field.validator!(null), 'Selecciona una relación');
      await tester.ensureVisible(find.byType(TextFormField));
      await tester.enterText(find.byType(TextFormField), '  Nico  ');
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Nieto/a').last);
      await tester.tap(find.text('Nieto/a').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Guardar'));
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(saved?.member.name, 'Nico');
      expect(saved?.member.relationship, 'Nieto/a');
      expect(saved?.photo, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
