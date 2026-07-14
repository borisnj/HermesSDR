// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_sdr/main.dart';

void main() {
  testWidgets('Hermes Discovery Test UI smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MaterialApp(home: HermesDiscoveryTest()));

    // Verify that we display the title
    expect(find.text('YAESU FTDX-101D SDR CONSOLE'), findsOneWidget);
    expect(find.text('BOARD OFFLINE — TOGGLE POWER BUTTON TO PROBE'), findsOneWidget);
  });
}
