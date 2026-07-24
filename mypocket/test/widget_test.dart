// test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mypocket/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const MyApp(
        seenOnboarding: false,
        isDarkMode: false, // Required parameter
      ),
    );

    // Verify that the app starts up without crashing
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
