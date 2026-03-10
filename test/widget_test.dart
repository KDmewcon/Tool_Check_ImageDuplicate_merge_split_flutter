import 'package:flutter_test/flutter_test.dart';
import 'package:duplicate_image_cleaner/main.dart';

void main() {
  testWidgets('App starts correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const DuplicateCleanerApp());
    expect(find.text('Duplicate Cleaner'), findsOneWidget);
    expect(find.text('Tìm và xóa ảnh trùng lặp'), findsOneWidget);
  });
}
