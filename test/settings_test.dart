import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/features/settings/business_screen.dart';
import 'package:wf_grocery_pos/features/settings/data/settings_repository.dart';
import 'package:wf_grocery_pos/state/settings_provider.dart';

void main() {
  group('SettingsProvider', () {
    late AppDatabase db;
    late SettingsProvider settings;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      settings = SettingsProvider(DriftSettingsRepository(db));
      await settings.load();
    });
    tearDown(() async {
      settings.dispose();
      await db.close();
    });

    test('sin configurar usa el nombre por defecto', () {
      expect(settings.hasBusinessName, isFalse);
      expect(settings.businessName, 'Mi Tienda');
    });

    test('guarda el nombre (sin espacios sobrantes) y persiste', () async {
      await settings.setBusinessName('  Abarrotes   Doña  Rosa ');
      expect(settings.businessName, 'Abarrotes Doña Rosa');

      final reloaded = SettingsProvider(DriftSettingsRepository(db));
      addTearDown(reloaded.dispose);
      await reloaded.load();
      expect(reloaded.businessName, 'Abarrotes Doña Rosa');
      expect(reloaded.hasBusinessName, isTrue);
    });

    test('cambiar el nombre reemplaza al anterior', () async {
      await settings.setBusinessName('Uno');
      await settings.setBusinessName('Dos');
      expect(settings.businessName, 'Dos');
      expect(await db.select(db.settingsTable).get(), hasLength(1));
    });

    test('el tope para cobrar sin revisar vale \$5 por defecto, se guarda y con 0 se desactiva', () async {
      expect(settings.skipReviewLimitCents, 500);

      await settings.setSkipReviewLimitCents(1000);
      expect(settings.skipReviewLimitCents, 1000);
      final reloaded = SettingsProvider(DriftSettingsRepository(db));
      addTearDown(reloaded.dispose);
      await reloaded.load();
      expect(reloaded.skipReviewLimitCents, 1000);

      await settings.setSkipReviewLimitCents(0);
      expect(settings.skipReviewLimitCents, isNull); // desactivado
      expect(settings.skipReviewSetting, 0);
      expect(() => settings.setSkipReviewLimitCents(-5), throwsArgumentError);
    });

    test('rechaza un nombre vacío o demasiado largo', () async {
      await settings.setBusinessName('Tienda');
      expect(() => settings.setBusinessName('   '), throwsArgumentError);
      expect(() => settings.setBusinessName('x' * 41), throwsArgumentError);
      expect(settings.businessName, 'Tienda');
    });
  });

  testWidgets('el admin cambia el nombre del negocio desde la pantalla Negocio', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final settings = SettingsProvider(DriftSettingsRepository(db));
    addTearDown(settings.dispose);
    await tester.runAsync(() async {
      await settings.load();
      await settings.setBusinessName('Tienda Vieja');
    });

    await tester.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(
      value: settings,
      child: const MaterialApp(home: Scaffold(body: BusinessScreen())),
    ));
    expect(find.widgetWithText(TextField, 'Tienda Vieja'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Tienda Nueva');
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(settings.businessName, 'Tienda Nueva');

    // Vacío: no guarda y avisa.
    await tester.enterText(find.byType(TextField).first, '  ');
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    expect(find.text('Escribe el nombre del negocio'), findsOneWidget);
    expect(settings.businessName, 'Tienda Nueva');
    await tester.pump(const Duration(seconds: 4)); // la alerta se retira sola
  });

  test('migración v18 → v19: crea la tabla de datos del negocio', () async {
    final dir = await Directory.systemTemp.createTemp('wf_settings_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'test.sqlite'));

    final seeded = AppDatabase.forTesting(NativeDatabase(file));
    await seeded.customStatement('DROP TABLE settings');
    await seeded.customStatement('ALTER TABLE cash_sessions DROP COLUMN opened_by');
    await seeded.customStatement('ALTER TABLE cash_sessions DROP COLUMN closed_by');
    await seeded.customStatement('ALTER TABLE cash_movements DROP COLUMN created_by');
    await seeded.customStatement('ALTER TABLE customer_account_movements DROP COLUMN received_by');
    await seeded.customStatement('PRAGMA user_version = 18');
    await seeded.close();

    final migrated = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(migrated.close);
    final settings = SettingsProvider(DriftSettingsRepository(migrated));
    addTearDown(settings.dispose);
    await settings.load();
    expect(settings.businessName, 'Mi Tienda');
    await settings.setBusinessName('Tienda');
    expect(settings.businessName, 'Tienda');
  });
}
