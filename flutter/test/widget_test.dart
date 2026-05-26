import 'package:flutter_test/flutter_test.dart';
import 'package:yolo_label_tool/main.dart';

void main() {
  testWidgets('app shell renders', (tester) async {
    await tester.pumpWidget(const YoloLabelApp());
    expect(find.text('YOLO Label Tool'), findsOneWidget);
  });
}
