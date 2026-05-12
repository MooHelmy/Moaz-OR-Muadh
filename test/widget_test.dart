import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medi_guard/main.dart';

void main() {
  testWidgets('MuadhApp builds successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const MuadhApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
