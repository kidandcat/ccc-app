import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'hub.dart';
import 'notify.dart';

class CrewScope extends InheritedNotifier<Crew> {
  const CrewScope({super.key, required Crew crew, required super.child}) : super(notifier: crew);

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
  ({String machine, int bot})? watching;
  void Function(Machine machine, HubSession session, BotInfo bot)? openChat;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      for (final s in _sessions.values) {
        s.wake();
      }
    }
  }

  Future<void> load() async {
    machines = await Store.load();
    for (final m in machines) {
      sessionFor(m);
    }
    await _syncListen();
    notifyListeners();
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

  void _onEvent(Machine m, String kind, Map<String, dynamic> body) {
    final botId = (body['bot_id'] as num?)?.toInt();
    if (botId == null) return;
    if (!shouldNotify(kind: kind, machineId: m.id, botId: botId, watching: watching)) {
      return;
    }
    final name = (body['bot'] as String?)?.trim();
    final text = (body['text'] as String?)?.trim();
    Notify.message(
      id: notificationId(m.id, botId),
      title: (name == null || name.isEmpty) ? m.name : name,
      body: (text == null || text.isEmpty) ? 'New message' : text,
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
    if (machines.isEmpty) {
      await Notify.stopListening();
      return;
    }
    await Notify.startListening(machines: machines.length);
  }
}
