import 'package:ccc_app/crew.dart';
import 'package:ccc_app/hub.dart';
import 'package:ccc_app/md.dart';
import 'package:ccc_app/notify.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses ccc pair URI', () {
    const raw = 'ccc://pair/v1?h=wss://hub.getccc.dev&i=ab&k=cd&n=c0ffee';
    final p = Pairing.parse(raw)!;
    expect(p.hub, 'wss://hub.getccc.dev');
    expect(p.instanceId, 'ab');
    expect(p.code, 'c0ffee');
  });

  test('parses bot last_text and archived', () {
    final b = BotInfo.fromJson({
      'id': 9,
      'name': 'Build APK',
      'role': '',
      'status': 'idle',
      'engine': 'grok',
      'last_text': 'sent the apk',
      'archived': true,
    });
    expect(b.lastText, 'sent the apk');
    expect(b.archived, isTrue);
    b.name = 'CCC app';
    expect(b.name, 'CCC app');
  });

  test('notifies on post unless that chat is open in the foreground', () {
    expect(
      shouldNotify(kind: 'post', machineId: 'mac', botId: 1, watching: null),
      isTrue,
    );
    expect(
      shouldNotify(kind: 'progress', machineId: 'mac', botId: 1, watching: null),
      isFalse,
    );
    expect(
      shouldNotify(
        kind: 'post',
        machineId: 'mac',
        botId: 1,
        watching: (machine: 'mac', bot: 1),
      ),
      isFalse,
    );
    expect(
      shouldNotify(
        kind: 'post',
        machineId: 'mac',
        botId: 1,
        watching: (machine: 'mac', bot: 2),
      ),
      isTrue,
    );
    expect(
      shouldNotify(
        kind: 'post',
        machineId: 'mac',
        botId: 1,
        watching: (machine: 'mac', bot: 1),
        foreground: false,
      ),
      isTrue,
    );
    expect(shouldNotify(kind: 'file', machineId: 'mac', botId: 1, watching: null), isTrue);
  });

  test('parses file attachments on turns', () {
    final t = TurnInfo.fromJson({
      'id': 1,
      'source': 'user',
      'input': 'install this',
      'output': '',
      'status': 'done',
      'at': '2026-09-16T12:00:00Z',
      'files': [
        {'id': 9, 'name': 'ccc.apk', 'mime': 'application/vnd.android.package-archive', 'size': 19300000},
      ],
    });
    expect(t.files, hasLength(1));
    expect(t.files.first.name, 'ccc.apk');
    expect(t.files.first.size, 19300000);
    expect(fmtSize(19300000), contains('MB'));
    expect(mimeForName('ccc.apk'), 'application/vnd.android.package-archive');
  });

  test('keeps thinking text when reopening a running turn', () {
    expect(
      Crew.resolveProgress(status: 'running', turnProgress: 'reading main.dart · 8s'),
      'reading main.dart · 8s',
    );
    expect(
      Crew.resolveProgress(
        status: 'running',
        turnProgress: 'working',
        cached: 'call grep · 3s',
      ),
      'call grep · 3s',
    );
    expect(
      Crew.resolveProgress(status: 'running', turnProgress: '', current: 'thinking · 2s'),
      'thinking · 2s',
    );
    expect(Crew.resolveProgress(status: 'running', turnProgress: ''), 'working');
    expect(Crew.resolveProgress(status: 'queued', turnProgress: ''), 'queued');
    expect(Crew.resolveProgress(status: 'done', turnProgress: ''), '');
  });

  test('parses live progress on bots and turns', () {
    final b = BotInfo.fromJson({
      'id': 3,
      'name': 'Build',
      'role': '',
      'status': 'running',
      'engine': 'grok',
      'progress': 'reading main.dart · 8s',
    });
    expect(b.progress, 'reading main.dart · 8s');
    final t = TurnInfo.fromJson({
      'id': 1,
      'source': 'user',
      'input': 'hi',
      'output': '',
      'status': 'running',
      'at': '2026-09-16T12:00:00Z',
      'progress': 'thinking · 3s',
    });
    expect(t.progress, 'thinking · 3s');
    expect(t.status, 'running');
  });

  testWidgets('renders markdown tables and emphasis', (tester) async {
    const md = '''
**hello**

| col | n |
| --- | - |
| a   | 1 |
''';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: MdBody(md))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('col'), findsOneWidget);
    expect(find.text('a'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
  });

  test('parses notification payload', () {
    final p = parseNotifyPayload('{"machine":"abc","bot_id":9}');
    expect(p?.machine, 'abc');
    expect(p?.bot, 9);
    expect(parseNotifyPayload('nope'), isNull);
  });
}
