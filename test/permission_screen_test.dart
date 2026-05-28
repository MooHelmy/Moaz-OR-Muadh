import 'package:Muadh/feature/media_bloc/presentation/views/permission_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockSharedPreferences extends Mock implements SharedPreferences {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PermissionScreen', () {
    // ignore: unused_local_variable
    late MockSharedPreferences mockPrefs;

    setUp(() {
      mockPrefs = MockSharedPreferences();
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('shows loading initially', (WidgetTester tester) async {
      bool onGrantedCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: PermissionScreen(
            onGranted: (bool _) => onGrantedCalled = true,
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(onGrantedCalled, false);
    });

    testWidgets('shows permission request UI after loading',
        (WidgetTester tester) async {
      // ignore: unused_local_variable
      bool onGrantedCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: PermissionScreen(
            onGranted: (bool _) => onGrantedCalled = true,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('معاذ يحتاج صلاحية الوصول للملفات\nعشان يحميك تلقائياً'),
          findsOneWidget);
      expect(find.text('منح الصلاحيات والبدء'), findsOneWidget);
      expect(find.byIcon(Icons.security), findsOneWidget);
    });
  });
}
