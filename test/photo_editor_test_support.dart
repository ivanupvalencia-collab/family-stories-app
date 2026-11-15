import 'package:family_stories_app/screens/photo_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> waitForPhotoEditor(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.byType(PhotoEditorScreen), findsOneWidget);
  for (var attempt = 0; attempt < 200; attempt++) {
    final save = tester.widget<FilledButton>(
      find.byKey(const ValueKey('photo-crop-save')),
    );
    if (save.onPressed != null) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('Photo editor did not decode the selected image.');
}

Future<void> confirmPhotoCrop(WidgetTester tester) async {
  await waitForPhotoEditor(tester);
  await tester.ensureVisible(find.byKey(const ValueKey('photo-crop-save')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('photo-crop-save')));
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(PhotoEditorScreen).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Photo crop did not finish.');
}
