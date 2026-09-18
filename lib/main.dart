import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'crew.dart';
import 'decisions.dart';
import 'hub.dart';
import 'md.dart';
import 'notify.dart';

const _ink = Color(0xFF0E1116);
const _panel = Color(0xFF171C24);
const _line = Color(0xFF2A3340);
const _text = Color(0xFFE8EDF4);
const _muted = Color(0xFF8B97A8);
const _gold = Color(0xFFD4A84B);

const _maxImageBytes = 350 * 1024;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final identity = await HubSession.loadIdentity();
  final crew = Crew(identity);
  crew.openChat = (machine, session, bot) {
    crew.navKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(session: session, bot: bot, machine: machine),
      ),
    );
  };
  crew.openDecisions = (machine) {
    crew.navKey.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => DecisionsPage(machine: machine)),
    );
  };
  await Notify.init(
    onTap: (payload) {
      void go() => crew.onNotificationTap(payload);
      if (crew.navKey.currentState == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => go());
      } else {
        go();
      }
    },
  );
  await crew.load();
  runApp(CrewScope(crew: crew, child: const CccApp()));
}

class CccApp extends StatelessWidget {
  const CccApp({super.key});
  @override
  Widget build(BuildContext context) {
    final crew = CrewScope.of(context);
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
      navigatorKey: crew.navKey,
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        textTheme: GoogleFonts.sourceSans3TextTheme(base.textTheme)
            .apply(bodyColor: _text, displayColor: _text),
        appBarTheme: const AppBarTheme(
          backgroundColor: _ink,
          foregroundColor: _text,
          elevation: 0,
        ),
      ),
      home: const MachinesPage(),
    );
  }
}

Future<String?> _askName(
  BuildContext context, {
  required String title,
  String initial = '',
}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _panel,
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLength: 64,
        decoration: const InputDecoration(
          hintText: 'Session name',
          counterText: '',
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, c.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

class MachinesPage extends StatefulWidget {
  const MachinesPage({super.key});
  @override
  State<MachinesPage> createState() => _MachinesPageState();
}

class _MachinesPageState extends State<MachinesPage> {
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
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('Pair'),
            ),
          ],
        );
      },
    );
    if (uri == null || uri.trim().isEmpty || !mounted) return;
    final p = Pairing.parse(uri);
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That is not a ccc pairing URI')),
      );
      return;
    }
    try {
      final id = await HubSession.loadIdentity();
      final m = Machine(
        hub: p.hub,
        id: p.instanceId,
        pk: p.instancePk,
        name: 'pairing…',
      );
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
      if (!mounted) return;
      await CrewScope.of(context).pair(m);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Pair failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final crew = CrewScope.of(context);
    final ms = crew.machines;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'CCC',
          style: GoogleFonts.sourceSerif4(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.08,
          ),
        ),
        actions: [
          if (crew.pendingDecisions.isNotEmpty)
            IconButton(
              tooltip: 'Decisions',
              icon: Badge(
                label: Text('${crew.pendingDecisions.length}'),
                child: const Icon(Icons.front_hand_outlined),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const DecisionsPage()),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _gold,
        foregroundColor: _ink,
        onPressed: _add,
        label: const Text('Pair machine'),
        icon: const Icon(Icons.qr_code_2),
      ),
      body: ms.isEmpty
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
          : Column(
              children: [
                if (crew.pendingDecisions.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: DecisionBanner(machine: null),
                  ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: ms.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) {
                      final m = ms[i];
                      final waiting = crew.questionsOn(m.id).length;
                      return ListTile(
                        tileColor: _panel,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: _line),
                        ),
                        title: Text(
                          m.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          waiting == 0
                              ? m.id.substring(0, 12)
                              : (waiting == 1
                                    ? '1 decision waiting'
                                    : '$waiting decisions waiting'),
                          style: TextStyle(
                            color: waiting == 0 ? _muted : _gold,
                            fontFamily: waiting == 0 ? 'monospace' : null,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: _muted,
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BotsPage(machine: m),
                          ),
                        ),
                        onLongPress: () => crew.removeAt(i),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class BotsPage extends StatefulWidget {
  const BotsPage({
    super.key,
    required this.machine,
    this.session,
    this.archived = false,
  });
  final Machine machine;
  final HubSession? session;
  final bool archived;
  @override
  State<BotsPage> createState() => _BotsPageState();
}

class _BotsPageState extends State<BotsPage> {
  HubSession? _s;
  List<BotInfo> _bots = [];
  String? _err;
  bool _booted = false;
  final _archiving = <int>{};
  Timer? _poll;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_booted) return;
    _booted = true;
    _boot();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _s?.removeListener(_onHub);
    super.dispose();
  }

  void _onHub(String kind, Map<String, dynamic> body) {
    if (kind == 'archive' ||
        (kind == 'session' && body['action'] == 'archive')) {
      final id = (body['bot_id'] as num?)?.toInt();
      if (id != null) {
        setState(() => _bots.removeWhere((b) => b.id == id));
      }
    }
    if (kind == 'progress' ||
        kind == 'post' ||
        kind == 'file' ||
        kind == 'session' ||
        kind == 'question' ||
        kind == 'answered' ||
        kind == 'archive' ||
        kind == 'up') {
      _load();
    }
  }

  Future<void> _boot() async {
    try {
      _s = widget.session ?? CrewScope.read(context).sessionFor(widget.machine);
      _s!.addListener(_onHub);
      await _s!.connect();
      if (!mounted) return;
      setState(() {});
      await _load();
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted) return;
        _load();
        CrewScope.read(context).refreshQuestions(widget.machine);
      });
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  Future<void> _load() async {
    if (_s == null) return;
    try {
      final res = await _s!.rpc(widget.archived ? 'archived' : 'bots');
      if (!mounted) return;
      setState(() {
        _bots = botsFrom(res)
            .where((b) => !_archiving.contains(b.id))
            .where((b) => widget.archived || !b.archived)
            .toList();
        _err = null;
      });
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  Future<void> _archiveNow(BotInfo b, int index) async {
    if (_s == null) return;
    _archiving.add(b.id);
    setState(() => _bots.removeWhere((x) => x.id == b.id));
    try {
      await _s!.rpc('archive', {'bot_id': b.id});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (index < 0 || index > _bots.length) {
          _bots.add(b);
        } else {
          _bots.insert(index, b);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      _archiving.remove(b.id);
    }
  }

  Future<void> _unarchive(BotInfo b) async {
    if (_s == null) return;
    try {
      await _s!.rpc('unarchive', {'bot_id': b.id});
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _rename(BotInfo b) async {
    final name = await _askName(
      context,
      title: 'Rename session',
      initial: b.name,
    );
    if (name == null || name.isEmpty || name == b.name || _s == null) return;
    try {
      await _s!.rpc('rename', {'bot_id': b.id, 'name': name});
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.archived ? 'Archived' : widget.machine.name,
          style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (!widget.archived)
            IconButton(
              tooltip: 'Decisions',
              icon: Badge(
                isLabelVisible: CrewScope.of(context)
                    .questionsOn(widget.machine.id)
                    .isNotEmpty,
                label: Text(
                  '${CrewScope.of(context).questionsOn(widget.machine.id).length}',
                ),
                child: const Icon(Icons.front_hand_outlined),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => DecisionsPage(machine: widget.machine),
                ),
              ),
            ),
          if (!widget.archived && _s != null)
            IconButton(
              tooltip: 'Archived sessions',
              icon: const Icon(Icons.inventory_2_outlined),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BotsPage(
                      machine: widget.machine,
                      session: _s,
                      archived: true,
                    ),
                  ),
                );
                _load();
              },
            ),
        ],
      ),
      body: _err != null
          ? Center(
              child: Text(_err!, style: const TextStyle(color: _muted)),
            )
          : _s == null
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : Column(
              children: [
                if (!widget.archived)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: DecisionBanner(
                      machine: widget.machine,
                      questions: CrewScope.of(context)
                          .questionsOn(widget.machine.id),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    color: _gold,
                    onRefresh: () async {
                      final crew = CrewScope.read(context);
                      await _load();
                      await crew.refreshQuestions(widget.machine);
                    },
                    child: _bots.isEmpty
                        ? ListView(
                            children: [
                              const SizedBox(height: 120),
                              Text(
                                widget.archived ? 'Nothing archived.' : 'When General opens a worker, it shows up here.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: _muted),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            itemCount: _bots.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (ctx, i) {
                              final b = _bots[i];
                              final q =
                                  CrewScope.of(context)
                                      .questionFor(widget.machine.id, b.id) ??
                                  b.question;
                              final asking =
                                  q != null && q.question.trim().isNotEmpty;
                              final live =
                                  b.progress != null && b.progress!.isNotEmpty;
                              final tile = ListTile(
                                tileColor: _panel,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: asking
                                        ? _gold.withValues(alpha: 0.45)
                                        : _line,
                                  ),
                                ),
                                title: Text(
                                  b.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  asking
                                      ? q.question
                                      : live
                                      ? b.progress!
                                      : (b.lastText != null &&
                                            b.lastText!.isNotEmpty)
                                      ? b.lastText!
                                      : b.engine,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color:
                                        (asking ||
                                            live ||
                                            b.status == 'waiting' ||
                                            b.status == 'running')
                                        ? _gold
                                        : _muted,
                                  ),
                                ),
                                trailing: widget.archived
                                    ? TextButton(
                                        onPressed: () => _unarchive(b),
                                        child: const Text('Restore'),
                                      )
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          StatusMark(
                                            asking ? 'waiting' : b.status,
                                          ),
                                          const SizedBox(width: 8),
                                          const Icon(
                                            Icons.chevron_right,
                                            color: _muted,
                                          ),
                                        ],
                                      ),
                                onTap: widget.archived
                                    ? () => _unarchive(b)
                                    : () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ChatPage(
                                            session: _s!,
                                            bot: b,
                                            machine: widget.machine,
                                          ),
                                        ),
                                      ).then((_) => _load()),
                                onLongPress: widget.archived
                                    ? null
                                    : () => _rename(b),
                              );
                              if (widget.archived) return tile;
                              return Dismissible(
                                key: ValueKey(b.id),
                                direction: DismissDirection.endToStart,
                                onDismissed: (_) => _archiveNow(b, i),
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  decoration: BoxDecoration(
                                    color: _gold.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.inventory_2_outlined,
                                    color: _gold,
                                  ),
                                ),
                                child: tile,
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.session,
    required this.bot,
    required this.machine,
  });
  final HubSession session;
  final BotInfo bot;
  final Machine machine;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _c = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  List<TurnInfo> _turns = [];
  String _progress = '';
  PendingAttach? _pending;
  bool _sending = false;
  final _fetching = <int>{};
  Crew? _crew;
  bool _listening = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_listening) return;
    _listening = true;
    _crew = CrewScope.of(context);
    _crew!.watchChat(widget.machine, widget.bot.id);
    widget.session.addListener(_onHub);
    _progress = Crew.resolveProgress(
      status: widget.bot.status,
      turnProgress: widget.bot.progress,
      cached: _crew!.progressFor(widget.machine.id, widget.bot.id),
    );
    _load();
  }

  void _onHub(String kind, Map<String, dynamic> body) {
    if (!mounted) return;
    final id = (body['bot_id'] as num?)?.toInt();
    if (kind == 'question' ||
        kind == 'answered' ||
        kind == 'session' ||
        kind == 'archive') {
      setState(() {});
    }
    if (kind == 'archive' && id == widget.bot.id) {
      Navigator.of(context).maybePop();
      return;
    }
    if (kind == 'session') {
      unawaited(_ensureStillLive());
    }
    if (id != null && id != widget.bot.id) return;
    if (id == null && kind != 'progress' && kind != 'post' && kind != 'file')
      return;
    if (kind == 'progress') {
      final text = body['text'] as String? ?? '';
      _crew?.setProgress(widget.machine.id, widget.bot.id, text);
      setState(() => _progress = text);
      _toBottom();
    } else {
      if (kind == 'post' || kind == 'file') {
        _crew?.setProgress(widget.machine.id, widget.bot.id, '');
      }
      _load();
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_onHub);
    _crew?.unwatchChat(widget.machine, widget.bot.id);
    _c.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ensureStillLive() async {
    try {
      final bots = botsFrom(await widget.session.rpc('bots'));
      if (!mounted) return;
      if (!bots.any((b) => b.id == widget.bot.id)) {
        Navigator.of(context).maybePop();
      }
    } catch (_) {}
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(0); // reverse:true — 0 is the latest message
    });
  }

  Future<void> _load() async {
    try {
      final res = await widget.session.rpc('history', {
        'bot_id': widget.bot.id,
        'limit': 50,
      });
      final body = res['body'];
      final raw = body is String ? jsonDecode(body) : body;
      final list = <TurnInfo>[];
      if (raw is List) {
        for (final e in raw) {
          list.add(TurnInfo.fromJson(e as Map<String, dynamic>));
        }
      }
      if (!mounted) return;
      final last = list.isEmpty ? null : list.last;
      final progress = Crew.resolveProgress(
        status: last?.status,
        turnProgress: last?.progress,
        cached: _crew?.progressFor(widget.machine.id, widget.bot.id) ?? '',
        current: _progress,
      );
      if (progress.isEmpty) {
        _crew?.setProgress(widget.machine.id, widget.bot.id, '');
      }
      setState(() {
        _turns = list;
        _progress = progress;
      });
      _toBottom();
    } catch (e) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _rename() async {
    final name = await _askName(
      context,
      title: 'Rename session',
      initial: widget.bot.name,
    );
    if (name == null || name.isEmpty || name == widget.bot.name) return;
    try {
      await widget.session.rpc('rename', {
        'bot_id': widget.bot.id,
        'name': name,
      });
      setState(() => widget.bot.name = name);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _pick(ImageSource source) async {
    final picker = ImagePicker();
    var file = await picker.pickImage(
      source: source,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 70,
    );
    if (file == null) return;
    var bytes = await file.readAsBytes();
    if (bytes.length > _maxImageBytes) {
      file = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 45,
      );
      if (file == null) return;
      bytes = await file.readAsBytes();
    }
    if (bytes.length > _maxImageBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image is too large (max ~350 KB)')),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(
      () => _pending = PendingAttach(
        name: 'photo.jpg',
        mime: 'image/jpeg',
        bytes: bytes,
      ),
    );
  }

  Future<void> _pickFile() async {
    final f = await FilePicker.pickFile();
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (bytes.length > hubFileMaxBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File is too large (max 50 MB)')),
        );
      }
      return;
    }
    if (!mounted) return;
    final name = (f.name.trim().isEmpty) ? 'file' : f.name;
    setState(
      () => _pending = PendingAttach(
        name: name,
        mime: mimeForName(name),
        bytes: bytes,
      ),
    );
  }

  Future<void> _attach() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panel,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.attach_file, color: _gold),
              title: const Text('File'),
              subtitle: const Text('APK, zip, pdf, …'),
              onTap: () {
                Navigator.pop(ctx);
                _pickFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: _gold),
              title: const Text('Photo library'),
              onTap: () {
                Navigator.pop(ctx);
                _pick(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: _gold),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(ctx);
                _pick(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFile(FileInfo f) async {
    if (_fetching.contains(f.id)) return;
    setState(() => _fetching.add(f.id));
    try {
      final bytes = await widget.session.fetchFile(f.id);
      if (!mounted) return;
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Save ${f.name}',
        fileName: f.name,
        bytes: bytes,
      );
      if (uri != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Saved ${f.name}')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _fetching.remove(f.id));
    }
  }

  Future<void> _send() async {
    final t = _c.text.trim();
    final att = _pending;
    if (t.isEmpty && att == null) return;
    if (_sending) return;
    _focus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _sending = true;
      _pending = null;
    });
    _c.clear();
    try {
      if (att != null) {
        await widget.session.sendBytes(
          botId: widget.bot.id,
          name: att.name,
          mime: att.mime,
          bytes: att.bytes,
          text: t,
        );
      } else {
        await widget.session.rpc('send', {
          'bot_id': widget.bot.id,
          'text': t,
        }, const Duration(seconds: 40));
      }
      await _load();
      await _crew?.refreshQuestions(widget.machine);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final crew = CrewScope.of(context);
    final pending = crew.questionFor(widget.machine.id, widget.bot.id);
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _rename,
          child: Text(
            widget.bot.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w700),
          ),
        ),
        actions: [
          StatusMark(pending != null ? 'waiting' : widget.bot.status),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Rename session',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: _rename,
          ),
        ],
      ),
      body: Column(
        children: [
          if (pending != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: DecisionCard(
                machine: widget.machine,
                question: pending,
                showSession: false,
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              reverse: true,
              padding: const EdgeInsets.all(16),
              itemCount: _turns.length + (_progress.isEmpty ? 0 : 1),
              itemBuilder: (ctx, i) {
                final extra = _progress.isEmpty ? 0 : 1;
                if (extra == 1 && i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _progress,
                      style: const TextStyle(color: _gold, fontSize: 13),
                    ),
                  );
                }
                final t = _turns[_turns.length - 1 - (i - extra)];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (t.input.isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width * 0.82,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: _gold.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: MdBody(t.input),
                            ),
                          ),
                        ),
                      if (t.output.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        MdBody(t.output),
                      ],
                      for (final f in t.files) ...[
                        const SizedBox(height: 8),
                        _FileChip(
                          file: f,
                          busy: _fetching.contains(f.id),
                          onTap: () => _openFile(f),
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
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
              child: Column(
                children: [
                  if (_pending != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 8),
                        child: Stack(
                          children: [
                            if (_pending!.isImage)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  _pending!.bytes,
                                  height: 72,
                                  fit: BoxFit.cover,
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  10,
                                  36,
                                  10,
                                ),
                                decoration: BoxDecoration(
                                  color: _panel,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _line),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.insert_drive_file_outlined,
                                      color: _gold,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 220,
                                      ),
                                      child: Text(
                                        '${_pending!.name} · ${fmtSize(_pending!.bytes.length)}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: IconButton.filled(
                                style: IconButton.styleFrom(
                                  backgroundColor: _ink,
                                  foregroundColor: _text,
                                  padding: const EdgeInsets.all(4),
                                  minimumSize: const Size(28, 28),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () =>
                                    setState(() => _pending = null),
                                icon: const Icon(Icons.close, size: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: _sending ? null : _attach,
                        icon: const Icon(Icons.attach_file, color: _gold),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _c,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.send,
                          decoration: InputDecoration(
                            hintText: 'Message',
                            hintStyle: const TextStyle(color: _muted),
                            filled: true,
                            fillColor: _panel,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(color: _line),
                            ),
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: _gold,
                          foregroundColor: _ink,
                        ),
                        onPressed: _sending ? null : _send,
                        icon: const Icon(Icons.arrow_upward),
                      ),
                    ],
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

class _FileChip extends StatelessWidget {
  const _FileChip({
    required this.file,
    required this.busy,
    required this.onTap,
  });
  final FileInfo file;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _line),
      ),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Icon(
                file.mime.startsWith('image/')
                    ? Icons.image_outlined
                    : Icons.insert_drive_file_outlined,
                color: _gold,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      fmtSize(file.size),
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _gold,
                  ),
                )
              else
                const Icon(Icons.save_alt, color: _muted, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
