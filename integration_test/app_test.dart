import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:medi_guard/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('end-to-end test', () {
    testWidgets('app starts and shows permission screen',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MuadhApp());
      await tester.pumpAndSettle();

      expect(find.textContaining('معاذ يحتاج صلاحية'), findsOneWidget);
      expect(find.text('منح الصلاحيات والبدء'), findsOneWidget);
    });
  });
}
