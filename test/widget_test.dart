import 'package:family_stories_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home muestra el contenido inicial', (tester) async {
    await tester.pumpWidget(const FamilyStoriesApp());

    expect(find.text('Family Stories'), findsOneWidget);
    expect(
      find.text('Conserva las historias de las personas que quieres.'),
      findsOneWidget,
    );
    expect(find.text('Añadir familiar'), findsOneWidget);
    expect(find.text('Tus familiares'), findsOneWidget);
    expect(
      find.text('Todavía no has añadido ningún familiar.'),
      findsOneWidget,
    );
  });

  testWidgets('permite añadir un familiar', (tester) async {
    await tester.pumpWidget(const FamilyStoriesApp());

    await tester.tap(find.text('Añadir familiar'));
    await tester.pumpAndSettle();

    expect(find.text('Nombre'), findsOneWidget);
    expect(find.text('Relación contigo'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), 'Ana');
    await tester.tap(find.text('Relación contigo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abuelo/a').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Abuelo/a'), findsOneWidget);
    expect(find.text('Todavía no has añadido ningún familiar.'), findsNothing);
  });

  testWidgets('valida los campos obligatorios', (tester) async {
    await tester.pumpWidget(const FamilyStoriesApp());

    await tester.tap(find.text('Añadir familiar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pump();

    expect(find.text('Introduce un nombre'), findsOneWidget);
    expect(find.text('Selecciona una relación'), findsOneWidget);
  });

  testWidgets('navega desde un familiar hasta el aviso de grabación', (
    tester,
  ) async {
    await tester.pumpWidget(const FamilyStoriesApp());

    await tester.tap(find.text('Añadir familiar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Ana');
    await tester.tap(find.text('Relación contigo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abuelo/a').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();

    expect(find.text('Conoce su historia'), findsOneWidget);
    expect(find.text('Responder una pregunta'), findsOneWidget);
    expect(find.text('Sus historias'), findsOneWidget);
    expect(
      find.text('Aquí aparecerán sus historias cuando guarde sus respuestas.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Responder una pregunta'));
    await tester.pumpAndSettle();

    expect(find.text('Escribir mi propia pregunta'), findsOneWidget);
    expect(find.text('O elige una categoría'), findsOneWidget);
    expect(find.text('Infancia'), findsOneWidget);
    expect(find.text('¿Cómo era tu casa cuando eras pequeño/a?'), findsNothing);

    await tester.tap(find.text('Infancia'));
    await tester.pumpAndSettle();

    expect(
      find.text('¿Cómo era tu casa cuando eras pequeño/a?'),
      findsOneWidget,
    );

    await tester.tap(find.text('¿Cómo era tu casa cuando eras pequeño/a?'));
    await tester.pumpAndSettle();

    expect(find.text('Para Ana'), findsOneWidget);
    expect(find.text('Grabar respuesta'), findsOneWidget);

    await tester.tap(find.text('Grabar respuesta'));
    await tester.pump();

    expect(find.text('Grabación de audio próximamente'), findsOneWidget);
  });

  testWidgets('permite escribir y continuar con una pregunta personalizada', (
    tester,
  ) async {
    await tester.pumpWidget(const FamilyStoriesApp());

    await tester.tap(find.text('Añadir familiar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Ana');
    await tester.tap(find.text('Relación contigo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abuelo/a').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Responder una pregunta'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Escribir mi propia pregunta'));
    await tester.pumpAndSettle();

    expect(find.text('¿Qué quieres preguntarle a Ana?'), findsOneWidget);

    await tester.tap(find.text('Continuar'));
    await tester.pump();
    expect(find.text('Escribe una pregunta'), findsOneWidget);

    await tester.enterText(
      find.byType(EditableText),
      '¿Cuál es tu receta favorita?',
    );
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.text('¿Cuál es tu receta favorita?'), findsOneWidget);
    expect(find.text('Para Ana'), findsOneWidget);
    expect(find.text('Grabar respuesta'), findsOneWidget);
  });
}
