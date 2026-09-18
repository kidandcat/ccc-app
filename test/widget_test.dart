import 'dart:typed_data';

import 'package:ccc_app/crew.dart';
import 'package:ccc_app/decisions.dart';
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

  test('parses ask_owner questions', () {
    final q = QuestionInfo.fromJson({
      'id': 4,
      'bot_id': 9,
      'bot': 'Deployer',
      'question': 'Ship to prod?',
      'options': ['ship', 'hold'],
      'at': '2026-09-18T10:00:00Z',
    });
    expect(q.bot, 'Deployer');
    expect(q.options, ['ship', 'hold']);
    final b = BotInfo.fromJson({
      'id': 9,
      'name': 'Deployer',
      'role': '',
      'status': 'waiting',
      'engine': 'grok',
      'question': {
        'id': 4,
        'bot_id': 9,
        'bot': 'Deployer',
        'question': 'Ship to prod?',
        'options': ['ship', 'hold'],
      },
    });
    expect(b.question?.id, 4);
    expect(statusLabel('waiting'), 'waiting');
    expect(statusLabel('disabled'), 'idle');
    expect(statusCaption('waiting'), 'Waiting');
    expect(statusCaption('running'), 'Running');
  });

  test('parses pending ask_owner on a bot and the questions list', () {
    final b = BotInfo.fromJson({
      'id': 3,
      'name': 'Deploy',
      'role': '',
      'status': 'waiting',
      'engine': 'grok',
      'question': {
        'id': 11,
        'bot_id': 3,
        'bot': 'Deploy',
        'question': 'Ship to prod?',
        'options': ['ship', 'hold'],
      },
    });
    expect(b.status, 'waiting');
    expect(b.question?.question, 'Ship to prod?');
    expect(b.question?.options, ['ship', 'hold']);
    expect(statusLabel('waiting'), 'waiting');
    expect(statusLabel('disabled'), 'idle');
    final qs = questionsFrom({
      'body': [
        {
          'id': 11,
          'bot_id': 3,
          'bot': 'Deploy',
          'question': 'Ship to prod?',
          'options': ['ship', 'hold'],
        },
      ],
    });
    expect(qs, hasLength(1));
    expect(qs.first.id, 11);
    expect(qs.first.options, ['ship', 'hold']);
  });

  test('notifies on post unless that chat is open in the foreground', () {
    expect(
      shouldNotify(
        kind: 'post',
        machineId: 'mac',
        botId: 1,
        watching: null,
        general: true,
      ),
      isTrue,
    );
    expect(
      shouldNotify(kind: 'post', machineId: 'mac', botId: 1, watching: null),
      isFalse,
    );
    expect(
      shouldNotify(
        kind: 'progress',
        machineId: 'mac',
        botId: 1,
        watching: null,
      ),
      isFalse,
    );
    expect(
      shouldNotify(
        kind: 'post',
        machineId: 'mac',
        botId: 1,
        watching: (machine: 'mac', bot: 1),
        general: true,
      ),
      isFalse,
    );
    expect(
      shouldNotify(
        kind: 'post',
        machineId: 'mac',
        botId: 1,
        watching: (machine: 'mac', bot: 2),
        general: true,
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
        general: true,
      ),
      isTrue,
    );
    expect(
      shouldNotify(kind: 'file', machineId: 'mac', botId: 1, watching: null),
      isTrue,
    );
    expect(
      shouldNotify(
        kind: 'question',
        machineId: 'mac',
        botId: 1,
        watching: null,
      ),
      isTrue,
    );
    expect(
      shouldNotify(
        kind: 'question',
        machineId: 'mac',
        botId: 1,
        watching: (machine: 'mac', bot: 1),
      ),
      isFalse,
    );
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
        {
          'id': 9,
          'name': 'ccc.apk',
          'mime': 'application/vnd.android.package-archive',
          'size': 19300000,
        },
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
      Crew.resolveProgress(
        status: 'running',
        turnProgress: 'reading main.dart · 8s',
      ),
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
      Crew.resolveProgress(
        status: 'running',
        turnProgress: '',
        current: 'thinking · 2s',
      ),
      'thinking · 2s',
    );
    expect(
      Crew.resolveProgress(status: 'running', turnProgress: ''),
      'working',
    );
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

  testWidgets('decision card shows Telegram-style option buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DecisionCard(
            machine: Machine(hub: 'wss://h', id: 'ab', pk: 'cd', name: 'mac'),
            question: QuestionInfo(
              id: 1,
              botId: 2,
              bot: 'Deploy',
              question: 'Ship to prod?',
              options: ['ship', 'hold'],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Ship to prod?'), findsOneWidget);
    expect(find.text('ship'), findsOneWidget);
    expect(find.text('hold'), findsOneWidget);
    expect(find.text('Deploy'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);
  });

  testWidgets('status mark labels running waiting idle', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              StatusMark('running'),
              StatusMark('waiting'),
              StatusMark('idle'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Waiting'), findsOneWidget);
    expect(find.text('Idle'), findsOneWidget);
  });

  test('pendingDecisions lists live ask_owner questions', () {
    final crew = Crew(HubIdentity(Uint8List(32), Uint8List(32)));
    addTearDown(crew.dispose);
    final mac = Machine(hub: 'wss://h', id: 'mac', pk: 'cd', name: 'Mac');
    crew.machines = [mac];
    crew.questions[mac.id] = [
      QuestionInfo(
        id: 7,
        botId: 3,
        bot: 'Deploy',
        question: 'Ship to prod?',
        options: ['ship', 'hold'],
      ),
    ];
    expect(crew.pendingDecisions, hasLength(1));
    expect(crew.pendingDecisions.first.question.id, 7);
    expect(crew.questionFor('mac', 3)?.question, 'Ship to prod?');
    expect(crew.questionFor('mac', 9), isNull);
    crew.questions[mac.id] = [];
    expect(crew.pendingDecisions, isEmpty);
  });

  test('marks the dispatcher from hub flag, topic_id, or name fallback', () {
    final flagged = BotInfo.fromJson({
      'id': 1,
      'name': 'Chief',
      'role': '',
      'status': 'idle',
      'engine': 'grok',
      'topic_id': 0,
      'general': true,
    });
    expect(flagged.isGeneral, isTrue);
    expect(flagged.topicId, 0);
    final worker = BotInfo.fromJson({
      'id': 2,
      'name': 'deploy-watch',
      'role': '',
      'status': 'running',
      'engine': 'grok',
      'topic_id': -2,
      'general': false,
    });
    expect(worker.isGeneral, isFalse);
    final oldListen = BotInfo.fromJson({
      'id': 3,
      'name': 'Chief',
      'role': '',
      'status': 'idle',
      'engine': 'grok',
    });
    expect(oldListen.isGeneral, isTrue);
    expect(oldListen.topicId, isNull);
    final legacyName = BotInfo.fromJson({
      'id': 5,
      'name': 'General',
      'role': '',
      'status': 'idle',
      'engine': 'grok',
    });
    expect(legacyName.isGeneral, isTrue);
    final namedWorker = BotInfo.fromJson({
      'id': 4,
      'name': 'landing',
      'role': '',
      'status': 'idle',
      'engine': 'grok',
    });
    expect(namedWorker.isGeneral, isFalse);
    final bots = [flagged, worker, namedWorker];
    expect(generalOf(bots)?.id, 1);
    expect(workersOf(bots).map((b) => b.id), [2, 4]);
  });

  test('turn display hides system injections on General and inbox reports', () {
    final report = TurnInfo.fromJson({
      'id': 1,
      'source': 'bot',
      'input': 'Message from deploy-watch:\nhealth 200',
      'output': 'replica is caught up',
      'status': 'done',
      'at': '2026-09-18T10:00:00Z',
    });
    final onGeneral = TurnDisplay.from(report, inGeneral: true);
    expect(onGeneral.owner, isFalse);
    expect(onGeneral.caption, 'deploy-watch');
    expect(onGeneral.quote, isNull);
    expect(onGeneral.output, 'replica is caught up');
    final onWorker = TurnDisplay.from(report, inGeneral: false);
    expect(onWorker.caption, 'deploy-watch');
    expect(onWorker.quote, 'health 200');
    final user = TurnInfo.fromJson({
      'id': 2,
      'source': 'user',
      'input': 'watch the deploy',
      'output': 'session deploy-watch started',
      'status': 'done',
      'at': '2026-09-18T10:00:00Z',
    });
    final you = TurnDisplay.from(user, inGeneral: true);
    expect(you.owner, isTrue);
    expect(you.quote, 'watch the deploy');
    final sys = TurnInfo.fromJson({
      'id': 3,
      'source': 'system',
      'input': 'this work is too long for General',
      'output': '',
      'status': 'done',
      'at': '2026-09-18T10:00:00Z',
    });
    expect(TurnDisplay.from(sys, inGeneral: true).hide, isTrue);
    expect(
      inboxPayload('Message from deploy-watch:\nhealth 200').sender,
      'deploy-watch',
    );
  });

  test('live bots RPC payload drops archived workers', () {
    final bots = botsFrom({
      'body': [
        {
          'id': 1,
          'name': 'Live',
          'role': '',
          'status': 'running',
          'engine': 'grok',
        },
        {
          'id': 2,
          'name': 'Gone',
          'role': '',
          'status': 'idle',
          'engine': 'grok',
          'archived': true,
        },
      ],
    });
    expect(bots.map((b) => b.id), [1, 2]);
    final live = bots.where((b) => !b.archived).toList();
    expect(live, hasLength(1));
    expect(live.first.name, 'Live');
    expect(statusCaption('idle'), 'Idle');
  });

  testWidgets('decisions page lists pending ask_owner buttons', (tester) async {
    final crew = Crew(HubIdentity(Uint8List(32), Uint8List(32)));
    final mac = Machine(hub: 'wss://h', id: 'mac', pk: 'cd', name: 'Mac');
    crew.machines = [mac];
    crew.questions[mac.id] = [
      QuestionInfo(
        id: 7,
        botId: 3,
        bot: 'Deploy',
        question: 'Ship to prod?',
        options: ['ship', 'hold'],
      ),
    ];
    addTearDown(crew.dispose);
    await tester.pumpWidget(
      CrewScope(
        crew: crew,
        child: const MaterialApp(home: DecisionsPage()),
      ),
    );
    expect(find.text('Ship to prod?'), findsOneWidget);
    expect(find.text('ship'), findsOneWidget);
    expect(find.text('hold'), findsOneWidget);
    expect(find.text('Deploy'), findsOneWidget);
  });
}
