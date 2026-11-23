import 'package:flutter_test/flutter_test.dart';

import 'package:aquaflow/aquaflow_app.dart';

void main() {
  testWidgets('Firebase startup errors are shown to the user', (tester) async {
    await tester.pumpWidget(
      AquaFlowApp(startupError: StateError('Firebase is not configured')),
    );

    expect(find.text('AquaFlow could not start'), findsOneWidget);
    expect(find.textContaining('Firebase is not configured'), findsOneWidget);
  });
}
