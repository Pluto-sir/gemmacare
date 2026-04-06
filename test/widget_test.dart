import 'package:flutter_test/flutter_test.dart';

import 'package:gemmacare/main.dart';

void main() {
  testWidgets('Gemma Care shell loads', (WidgetTester tester) async {
    await tester.pumpWidget(const GemmaCareApp());
    await tester.pump();

    expect(find.text('Gemma Care'), findsOneWidget);
  });
}
