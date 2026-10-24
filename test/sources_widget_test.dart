import 'package:flutter/material.dart';

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/presentation/sources_dialog.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/sources/provider_connections.dart';
import 'package:music_time/sources/additional_sources.dart';

import 'provider_auth_test.dart' show MemoryVault;

void main() {
  testWidgets(
    'disconnected additional source card expands with removal still available',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      final providers = ProviderConnections(
        await SharedPreferences.getInstance(),
        store,
        vault: MemoryVault(),
      );
      providers.additional.connections.add(
        SourceConnection(
          id: 'google-fixture',
          type: 'google',
          label: 'Google demo',
          connected: false,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProviderSettingsPage(
              providers: providers,
              onImported: () {},
              onlyMicrosoft: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Remover fonte'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('source.card.google-fixture')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Remover fonte'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      providers.dispose();
      await tester.runAsync(store.close);
    },
  );
  testWidgets(
    'duas fontes aparecem separadas e adicionar OneDrive continua disponível',
    (tester) async {
      const clientId = '00000000-0000-0000-0000-000000000001';
      SharedPreferences.setMockInitialValues({'microsoft.client_id': clientId});
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      final vault = MemoryVault();
      final saved = jsonEncode({
        'client_id': clientId,
        'access_token': 'fixture',
        'drive_id': 'A',
        'expires_at': '2099-01-01T00:00:00Z',
      });
      await vault.write('microsoft.session', saved);
      final root = ProviderConnections(
        await SharedPreferences.getInstance(),
        store,
        vault: vault,
      );
      await root.renameMicrosoftSource('Conta principal');
      final second = await root.createMicrosoftSource();
      await second.renameMicrosoftSource('Conta adicional');
      await root.refreshStatus();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProviderSettingsPage(
              providers: root,
              onImported: () {},
              onlyMicrosoft: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Conta principal'), findsOneWidget);
      expect(find.text('Conta adicional'), findsOneWidget);
      await tester.tap(find.text('Conta adicional'));
      await tester.pumpAndSettle();
      expect(find.text('Conectar pelo navegador'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byTooltip('Adicionar fonte'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Adicionar fonte'));
      await tester.pumpAndSettle();
      expect(find.text('OneDrive pessoal'), findsOneWidget);
      expect(await vault.read('microsoft.session'), saved);
      await tester.pumpWidget(const SizedBox());
      root.dispose();
      await tester.runAsync(store.close);
    },
  );
  testWidgets(
    'verificação OneDrive exibe etapas e mantém estado sem pasta indexada',
    (tester) async {
      const clientId = '00000000-0000-0000-0000-000000000001';
      SharedPreferences.setMockInitialValues({'microsoft.client_id': clientId});
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      final vault = MemoryVault();
      await vault.write(
        'microsoft.session',
        jsonEncode({
          'client_id': clientId,
          'access_token': 'fixture',
          'expires_at': '2099-01-01T00:00:00Z',
        }),
      );
      final p = ProviderConnections(
        await SharedPreferences.getInstance(),
        store,
        vault: vault,
        client: MockClient(
          (r) async => http.Response('{"id":"drive","name":"OneDrive"}', 200),
        ),
      );
      await p.refreshStatus();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProviderSettingsPage(
              providers: p,
              onImported: () {},
              onlyMicrosoft: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text('Verificar conexão, pasta e leitura'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verificar conexão, pasta e leitura'));
      await tester.pumpAndSettle();
      expect(
        find.text('Sessão Microsoft e OneDrive: acesso confirmado.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Escolha a pasta musical para verificar a leitura de músicas.',
        ),
        findsOneWidget,
      );
      expect(p.microsoftCheckedAt, isNull);
      expect(p.microsoftConnected, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      p.dispose();
      await tester.runAsync(store.close);
    },
  );
  testWidgets(
    'seletor destaca seleção; navegar/cancelar preserva e confirmar troca pasta',
    (tester) async {
      const clientId = '00000000-0000-0000-0000-000000000001';
      SharedPreferences.setMockInitialValues({
        'microsoft.client_id': clientId,
        'microsoft.folder_selected': true,
        'microsoft.folder_id': 'music',
        'microsoft.folder_path': '/drive/root:/Música',
        'microsoft.folder_name': 'Música',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      final vault = MemoryVault();
      await vault.write(
        'microsoft.session',
        jsonEncode({
          'client_id': clientId,
          'access_token': 'fixture',
          'expires_at': '2099-01-01T00:00:00Z',
        }),
      );
      final providers = ProviderConnections(
        prefs,
        store,
        vault: vault,
        client: MockClient(
          (r) async => http.Response(
            jsonEncode(
              r.url.path == '/v1.0/me/drive'
                  ? {'id': 'drive', 'name': 'OneDrive'}
                  : {
                      'value': r.url.path.endsWith('/root/children')
                          ? [
                              {'id': 'music', 'name': 'Música', 'folder': {}},
                              {'id': 'docs', 'name': 'Docs', 'folder': {}},
                            ]
                          : [],
                    },
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProviderSettingsPage(
              providers: providers,
              onImported: () {},
              onlyMicrosoft: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Escolher pasta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Escolher pasta'));
      await tester.pumpAndSettle();
      expect(find.text('Selecionada: /Música'), findsOneWidget);
      expect(find.text('Pasta selecionada'), findsOneWidget);
      await tester.tap(find.text('Docs'));
      await tester.pumpAndSettle();
      expect(find.text('Navegando: /Docs'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(prefs.getString('microsoft.folder_id'), 'music');
      await tester.tap(find.text('Escolher pasta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Docs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Selecionar esta pasta'));
      await tester.pumpAndSettle();
      expect(prefs.getString('microsoft.folder_id'), 'docs');
      expect(providers.selectedFolderLabel, '/Docs');
      await tester.pumpWidget(const SizedBox.shrink());
      providers.dispose();
      await tester.runAsync(store.close);
    },
  );
  testWidgets(
    'OneDrive pode ser adicionado e conexão não fica desativada sem configuração',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'microsoft.sync_summary': '{"folder":"Música","total":2,"processed":2,"completedAt":"2026-10-13T12:00:00"}',
      });
      final preferences = await SharedPreferences.getInstance();
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      final providers = ProviderConnections(
        preferences,
        store,
        vault: MemoryVault(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProviderSettingsPage(
              providers: providers,
              onImported: () {},
              onlyMicrosoft: true,
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Conectar pelo navegador'), findsNothing);
      await tester.tap(find.byTooltip('Adicionar fonte'));
      await tester.pumpAndSettle();
      final gate = Completer<void>();
      final pending = providers.run(() => gate.future);
      await tester.pump();
      await tester.tap(find.text('OneDrive pessoal'));
      gate.complete();
      await pending;
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Conectar pelo navegador'),
      );
      expect(button.onPressed, isNotNull);
      await tester.ensureVisible(find.text('Avançado'));
      await tester.tap(find.text('Avançado'));
      await tester.pumpAndSettle();
      expect(find.text('Client ID público do Music Time'), findsOneWidget);
      expect(
        find.text('Última sincronização concluída — Música'),
        findsOneWidget,
      );
      expect(find.text('13/10/2026 às 12:00'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      providers.dispose();
      await tester.runAsync(store.close);
    },
  );
}
