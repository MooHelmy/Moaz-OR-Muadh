import 'package:Muadh/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MuadhApp builds successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const MuadhApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
