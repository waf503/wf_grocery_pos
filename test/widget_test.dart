import 'package:flutter_test/flutter_test.dart';

import 'package:wf_grocery_pos/app.dart';

void main() {
  testWidgets('App loads and shows the dashboard by default', (WidgetTester tester) async {
    await tester.pumpWidget(const GroceryPosApp());
    await tester.pumpAndSettle();

    expect(find.text('Inicio'), findsWidgets);
    expect(find.text('Punto de Venta'), findsWidgets);
  });
}
