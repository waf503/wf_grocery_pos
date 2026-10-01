import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wf_grocery_pos/app.dart';
import 'package:wf_grocery_pos/core/database/app_database.dart';

void main() {
  testWidgets('App loads and shows the dashboard by default', (WidgetTester tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(GroceryPosApp(database: database));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Inicio'), findsWidgets);
    expect(find.text('Punto de Venta'), findsWidgets);
  });
}
