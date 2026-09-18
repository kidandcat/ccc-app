import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'hub.dart';
import 'notify.dart';

class CrewScope extends InheritedNotifier<Crew> {
  const CrewScope({super.key, required Crew crew, required super.child})
    : super(notifier: crew);

  static Crew of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CrewScope>();
    assert(scope != null, 'CrewScope not found');
    return scope!.notifier!;
  }

  static Crew read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<CrewScope>();
    assert(scope != null, 'CrewScope not found');
    return scope!.notifier!;
  }
}

class Crew extends ChangeNotifier with WidgetsBindingObserver {
  Crew(this.identity) {
    WidgetsBinding.instance.addObserver(this);
  }
  final HubIdentity identity;
  final navKey = GlobalKey<NavigatorState>();

  List<Machine> machines = [];
  final _sessions = <String, HubSession>{};
  final _progress = <String, String>{};
  final questions = <String, List<QuestionInfo>>{};
  ({String machine, int bot})? watching;
  AppLifecycleState life = AppLifecycleState.resumed;
  void Function(Machine machine, HubSession session, BotInfo bot)? openChat;
  void Function(Machine machine)? openDecisions;
  Timer? _poll;

  bool get foreground => life == AppLifecycleState.resumed;

  static String progressKey(String machineId, int botId) => '$machineId:$botId';

  String progressFor(String machineId, int botId) =>
      _progress[progressKey(machineId, botId)] ?? '';

  void setProgress(String machineId, int botId, String text) {
    final k = progressKey(machineId, botId);
    if (text.isEmpty) {
      _progress.remove(k);
    } else {
      _progress[k] = text;
    }
  }

  /// Pick the live thinking/tool line to show when reopening a chat.
  /// Cached hub events win; otherwise the history/bots payload; never drop a
  /// running turn just because we left the screen.
  static String resolveProgress({
    required String? status,
    String? turnProgress,
    String cached = '',
    String current = '',
  }) {
    final live = (turnProgress ?? '').trim();
    final run = status == 'running' || status == 'queued';
    if (!run && live.isEmpty) return '';
    final c = cached.trim();
    if (c.isNotEmpty) return c;
    if (live.isNotEmpty) return live;
    final cur = current.trim();
    if (cur.isNotEmpty) return cur;
    return status == 'queued' ? 'queued' : 'working';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    life = state;
    if (state == AppLifecycleState.resumed) {
      for (final s in _sessions.values) {
        s.wake();
      }
      refreshQuestions();
    }
  }

  List<QuestionInfo> questionsOn(String machineId) =>
      questions[machineId] ?? const [];

  List<({Machine machine, QuestionInfo question})> get pendingDecisions {
    final out = <({Machine machine, QuestionInfo question})>[];
    for (final m in machines) {
      for (final q in questionsOn(m.id)) {
        out.add((machine: m, question: q));
      }
    }
    return out;
  }

  QuestionInfo? questionFor(String machineId, int botId) {
    for (final q in questionsOn(machineId)) {
      if (q.botId == botId) return q;
    }
    return null;
  }

  Future<void> load() async {
    machines = await Store.load();
    for (final m in machines) {
      sessionFor(m);
    }
    await _syncListen();
    await refreshQuestions();
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!foreground) return;
      refreshQuestions();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  HubSession sessionFor(Machine m) {
    return _sessions.putIfAbsent(m.id, () {
      final s = HubSession(identity, m);
      s.addListener((kind, body) => _onEvent(m, kind, body));
      s.connect();
      return s;
    });
  }

  void watchChat(Machine m, int botId) {
    watching = (machine: m.id, bot: botId);
  }

  void unwatchChat(Machine m, int botId) {
    if (watching?.machine == m.id && watching?.bot == botId) {
      watching = null;
    }
  }

  Future<void> save(List<Machine> next) async {
    machines = next;
    await Store.save(machines);
    final keep = machines.map((e) => e.id).toSet();
    for (final id in _sessions.keys.toList()) {
      if (!keep.contains(id)) {
        await _sessions.remove(id)?.close();
      }
    }
    for (final m in machines) {
      sessionFor(m);
    }
    await _syncListen();
    await refreshQuestions();
    notifyListeners();
  }

  Future<void> pair(Machine m) async {
    final next = [...machines.where((e) => e.id != m.id), m];
    await save(next);
  }

  Future<void> removeAt(int i) async {
    if (i < 0 || i >= machines.length) return;
    final next = [...machines]..removeAt(i);
    await save(next);
  }

  Future<void> refreshQuestions([Machine? only]) async {
    final targets = only == null ? machines : [only];
    var changed = false;
    for (final m in targets) {
      try {
        final res = await sessionFor(m).rpc('questions');
        final next = questionsFrom(res);
        final prev = questions[m.id];
        if (prev == null ||
            prev.length != next.length ||
            !_sameQuestions(prev, next)) {
          questions[m.id] = next;
          changed = true;
        }
      } catch (_) {
        // Old listen binaries have no questions RPC; fall back to bots.question.
        try {
          final bots = botsFrom(await sessionFor(m).rpc('bots'));
          final next = [
            for (final b in bots)
              if (b.question != null) b.question!,
          ];
          final prev = questions[m.id];
          if (prev == null || !_sameQuestions(prev, next)) {
            questions[m.id] = next;
            changed = true;
          }
        } catch (_) {}
      }
    }
    if (changed) notifyListeners();
  }

  static bool _sameQuestions(List<QuestionInfo> a, List<QuestionInfo> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].question != b[i].question) return false;
    }
    return true;
  }

  Future<void> answerQuestion(
    Machine m,
    QuestionInfo q, {
    int? option,
    String? text,
  }) async {
    final params = <String, dynamic>{'question_id': q.id};
    if (option != null) params['option'] = option;
    final typed = text?.trim() ?? '';
    if (typed.isNotEmpty) params['text'] = typed;
    try {
      await sessionFor(m).rpc('answer', params);
    } catch (e) {
      final msg = '$e';
      if (!msg.contains('unknown method')) rethrow;
      final answer = typed.isNotEmpty
          ? typed
          : (option != null && option >= 0 && option < q.options.length
                ? q.options[option]
                : '');
      if (answer.isEmpty) rethrow;
      await sessionFor(m).rpc('send', {
        'bot_id': q.botId,
        'text': answer,
      }, const Duration(seconds: 40));
    }
    final cur = [...questionsOn(m.id)]..removeWhere((e) => e.id == q.id);
    questions[m.id] = cur;
    notifyListeners();
    await refreshQuestions(m);
  }

  void _onEvent(Machine m, String kind, Map<String, dynamic> body) {
    if (kind == 'up' ||
        kind == 'session' ||
        kind == 'question' ||
        kind == 'answered' ||
        kind == 'archive') {
      if (kind == 'archive') {
        final botId = (body['bot_id'] as num?)?.toInt();
        if (botId != null) {
          questions[m.id] = [...questionsOn(m.id)]
            ..removeWhere((q) => q.botId == botId);
          notifyListeners();
        }
      }
      if (kind == 'answered') {
        final qid = (body['id'] as num?)?.toInt();
        if (qid != null) {
          questions[m.id] = [...questionsOn(m.id)]
            ..removeWhere((q) => q.id == qid);
          notifyListeners();
        }
      }
      unawaited(refreshQuestions(m));
    }
    final botId = (body['bot_id'] as num?)?.toInt();
    if (botId == null) return;
    final text = (body['text'] as String?)?.trim() ?? '';
    if (kind == 'progress') {
      setProgress(m.id, botId, text);
      notifyListeners();
      return;
    }
    if (kind == 'post' || kind == 'file') {
      setProgress(m.id, botId, '');
    }
    final name = (body['bot'] as String?)?.trim();
    final general =
        body['general'] == true ||
        (body['general'] == null && (name ?? '').toLowerCase() == 'general');
    if (!shouldNotify(
      kind: kind,
      machineId: m.id,
      botId: botId,
      watching: watching,
      foreground: foreground,
      general: general,
    )) {
      return;
    }
    final title = kind == 'question'
        ? ((name == null || name.isEmpty) ? 'Decision' : name)
        : ((name == null || name.isEmpty) ? m.name : name);
    Notify.message(
      id: notificationId(m.id, botId),
      title: title,
      body: text.isEmpty
          ? (kind == 'question' ? 'Needs a decision' : 'New message')
          : text,
      payload: jsonEncode({'machine': m.id, 'bot_id': botId}),
    );
  }

  Future<void> onNotificationTap(String payload) async {
    final p = parseNotifyPayload(payload);
    if (p == null) return;
    Machine? m;
    for (final e in machines) {
      if (e.id == p.machine) m = e;
    }
    if (m == null) return;
    final s = sessionFor(m);
    try {
      final res = await s.rpc('bots');
      BotInfo? bot;
      for (final b in botsFrom(res)) {
        if (b.id == p.bot) bot = b;
      }
      if (bot == null) return;
      openChat?.call(m, s, bot);
    } catch (_) {}
  }

  Future<void> _syncListen() async {
    try {
      if (machines.isEmpty) {
        await Notify.stopListening();
        return;
      }
      await Notify.startListening(machines: machines.length);
    } catch (_) {}
  }
}
