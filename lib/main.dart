import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hub.dart';

const _ink = Color(0xFF0E1116);
const _panel = Color(0xFF171C24);
const _line = Color(0xFF2A3340);
const _text = Color(0xFFE8EDF4);
const _muted = Color(0xFF8B97A8);
const _gold = Color(0xFFD4A84B);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CccApp());
}

class CccApp extends StatelessWidget {
  const CccApp({super.key});
  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _ink,
      colorScheme: const ColorScheme.dark(
        primary: _gold,
        surface: _panel,
        onSurface: _text,
      ),
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'CCC',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        textTheme: GoogleFonts.sourceSans3TextTheme(base.textTheme).apply(
          bodyColor: _text,
          displayColor: _text,
        ),
        appBarTheme: const AppBarTheme(backgroundColor: _ink, foregroundColor: _text, elevation: 0),
      ),
      home: const MachinesPage(),
    );
  }
}

class Store {
  static const _k = 'ccc.machines';
  static Future<List<Machine>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_k) ?? [];
    return raw.map((e) => Machine.fromJson(jsonDecode(e) as Map<String, dynamic>)).toList();
  }

  static Future<void> save(List<Machine> ms) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_k, ms.map((e) => jsonEncode(e.toJson())).toList());
  }
}

class MachinesPage extends StatefulWidget {
  const MachinesPage({super.key});
  @override
  State<MachinesPage> createState() => _MachinesPageState();
}

class _MachinesPageState extends State<MachinesPage> {
  List<Machine> _ms = [];

  @override
  void initState() {
    super.initState();
    Store.load().then((v) => setState(() => _ms = v));
  }

  Future<void> _add() async {
    final uri = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          backgroundColor: _panel,
          title: const Text('Pair a machine'),
          content: TextField(
            controller: c,
            maxLines: 4,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Paste the ccc://pair/v1?… URI from `ccc pair`',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Pair')),
          ],
        );
      },
    );
    if (uri == null || uri.trim().isEmpty || !mounted) return;
    final p = Pairing.parse(uri);
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That is not a ccc pairing URI')));
      return;
    }
    try {
      final id = await HubSession.loadIdentity();
      final m = Machine(hub: p.hub, id: p.instanceId, pk: p.instancePk, name: 'pairing…');
      final s = HubSession(id, m);
      await s.connect();
      final res = await s.pair(p);
      await s.close();
      var name = 'ccc';
      final body = res['body'];
      if (body is Map && body['name'] is String) name = body['name'] as String;
      if (body is String && body.isNotEmpty) {
        try {
          final j = jsonDecode(body) as Map<String, dynamic>;
          name = j['name'] as String? ?? name;
        } catch (_) {}
      }
      m.name = name;
      _ms = [..._ms.where((e) => e.id != m.id), m];
      await Store.save(_ms);
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pair failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('CCC', style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w700, letterSpacing: 0.08)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _gold,
        foregroundColor: _ink,
        onPressed: _add,
        label: const Text('Pair machine'),
        icon: const Icon(Icons.qr_code_2),
      ),
      body: _ms.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No machines yet.\nOn the Mac (or any PC running ccc) type:\n\n    ccc pair\n\nand paste the URI here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, height: 1.5),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: _ms.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final m = _ms[i];
                return ListTile(
                  tileColor: _panel,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _line)),
                  title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(m.id.substring(0, 12), style: const TextStyle(color: _muted, fontFamily: 'monospace')),
                  trailing: const Icon(Icons.chevron_right, color: _muted),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BotsPage(machine: m))),
                  onLongPress: () async {
                    _ms.removeAt(i);
                    await Store.save(_ms);
                    setState(() {});
                  },
                );
              },
            ),
    );
  }
}

class BotsPage extends StatefulWidget {
  const BotsPage({super.key, required this.machine});
  final Machine machine;
  @override
  State<BotsPage> createState() => _BotsPageState();
}

class _BotsPageState extends State<BotsPage> {
  HubSession? _s;
  List<BotInfo> _bots = [];
  String? _err;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final id = await HubSession.loadIdentity();
      final s = HubSession(id, widget.machine);
      await s.connect();
      final res = await s.rpc('bots');
      final body = res['body'];
      final list = <BotInfo>[];
      final raw = body is String ? jsonDecode(body) : body;
      if (raw is List) {
        for (final e in raw) {
          list.add(BotInfo.fromJson(e as Map<String, dynamic>));
        }
      }
      if (!mounted) return;
      setState(() {
        _s = s;
        _bots = list;
      });
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  @override
  void dispose() {
    _s?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.machine.name)),
      body: _err != null
          ? Center(child: Text(_err!, style: const TextStyle(color: _muted)))
          : _s == null
              ? const Center(child: CircularProgressIndicator(color: _gold))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _bots.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final b = _bots[i];
                    return ListTile(
                      tileColor: _panel,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _line)),
                      title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        [b.engine, b.status, b.role].where((e) => e.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ChatPage(session: _s!, bot: b, machine: widget.machine)),
                      ),
                    );
                  },
                ),
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.session, required this.bot, required this.machine});
  final HubSession session;
  final BotInfo bot;
  final Machine machine;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _c = TextEditingController();
  final _scroll = ScrollController();
  List<TurnInfo> _turns = [];
  String _progress = '';

  @override
  void initState() {
    super.initState();
    widget.session.onEvent = (kind, body) {
      if ((body['bot_id'] as num?)?.toInt() != widget.bot.id) return;
      if (kind == 'progress') {
        setState(() => _progress = body['text'] as String? ?? '');
      } else {
        _load();
      }
    };
    _load();
  }

  Future<void> _load() async {
    final res = await widget.session.rpc('history', {'bot_id': widget.bot.id, 'limit': 50});
    final body = res['body'];
    final raw = body is String ? jsonDecode(body) : body;
    final list = <TurnInfo>[];
    if (raw is List) {
      for (final e in raw) {
        list.add(TurnInfo.fromJson(e as Map<String, dynamic>));
      }
    }
    if (!mounted) return;
    setState(() {
      _turns = list;
      _progress = '';
    });
  }

  Future<void> _send() async {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    _c.clear();
    await widget.session.rpc('send', {'bot_id': widget.bot.id, 'text': t});
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.bot.name)),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _turns.length + (_progress.isEmpty ? 0 : 1),
              itemBuilder: (ctx, i) {
                if (i == _turns.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_progress, style: const TextStyle(color: _gold, fontSize: 13)),
                  );
                }
                final t = _turns[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (t.input.isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(color: _gold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
                            child: Text(t.input),
                          ),
                        ),
                      if (t.output.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(t.output, style: const TextStyle(height: 1.45)),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _c,
                      minLines: 1,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: 'Message ${widget.bot.name}',
                        filled: true,
                        fillColor: _panel,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: _line)),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: _gold, foregroundColor: _ink),
                    onPressed: _send,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
