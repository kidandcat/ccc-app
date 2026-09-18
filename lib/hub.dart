import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pinenacl/x25519.dart' as nacl;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class HubIdentity {
  HubIdentity(this.private, this.public);
  final Uint8List private;
  final Uint8List public;
  String get id => _hex(public);
}

String _hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

Uint8List _unhex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

class Pairing {
  Pairing({
    required this.hub,
    required this.instanceId,
    required this.instancePk,
    required this.code,
  });
  final String hub;
  final String instanceId;
  final String instancePk;
  final String code;

  static Pairing? parse(String raw) {
    final s = raw.trim();
    if (!s.startsWith('ccc://pair/v1')) return null;
    final u = Uri.parse(s);
    final q = u.queryParameters;
    final hub = q['h'] ?? '';
    final id = q['i'] ?? '';
    final k = q['k'] ?? '';
    final n = q['n'] ?? '';
    if ([hub, id, k, n].any((e) => e.isEmpty)) return null;
    return Pairing(hub: hub, instanceId: id, instancePk: k, code: n);
  }
}

class Machine {
  Machine({
    required this.hub,
    required this.id,
    required this.pk,
    required this.name,
  });
  final String hub;
  final String id;
  final String pk;
  String name;
  Map<String, dynamic> toJson() => {
    'hub': hub,
    'id': id,
    'pk': pk,
    'name': name,
  };
  static Machine fromJson(Map<String, dynamic> j) => Machine(
    hub: j['hub'] as String,
    id: j['id'] as String,
    pk: j['pk'] as String,
    name: j['name'] as String? ?? 'ccc',
  );
}

class QuestionInfo {
  QuestionInfo({
    required this.id,
    required this.botId,
    required this.bot,
    required this.question,
    this.options = const [],
    this.at,
  });
  final int id;
  final int botId;
  final String bot;
  final String question;
  final List<String> options;
  final String? at;

  factory QuestionInfo.fromJson(Map<String, dynamic> j) {
    final opts = <String>[];
    final raw = j['options'];
    if (raw is List) {
      for (final e in raw) {
        if (e is String && e.trim().isNotEmpty) opts.add(e);
      }
    }
    return QuestionInfo(
      id: (j['id'] as num).toInt(),
      botId: (j['bot_id'] as num?)?.toInt() ?? 0,
      bot: j['bot'] as String? ?? '',
      question: j['question'] as String? ?? j['text'] as String? ?? '',
      options: opts,
      at: j['at'] as String?,
    );
  }
}

class BotInfo {
  BotInfo({
    required this.id,
    required this.name,
    required this.role,
    required this.status,
    required this.engine,
    this.last,
    this.lastText,
    this.progress,
    this.archived = false,
    this.question,
    this.topicId,
    this.generalFlag,
  });
  final int id;
  String name;
  final String role;
  final String status;
  final String engine;
  final String? last;
  final String? lastText;
  final String? progress;
  final bool archived;
  final QuestionInfo? question;

  /// 0 is Chief. Null means the listen binary did not send topic_id.
  final int? topicId;

  /// True when listen marked this row as the dispatcher. Null = field absent.
  /// Wire field is still `general` (historical).
  final bool? generalFlag;

  /// Dispatcher session. Prefer the hub flag; fall back to topic_id 0, then name.
  bool get isGeneral {
    if (generalFlag == true) return true;
    if (topicId == 0) return true;
    if (generalFlag == null && topicId == null) {
      final n = name.toLowerCase();
      return n == 'chief' || n == 'general';
    }
    return false;
  }

  factory BotInfo.fromJson(Map<String, dynamic> j) {
    QuestionInfo? q;
    final raw = j['question'];
    if (raw is Map) q = QuestionInfo.fromJson(Map<String, dynamic>.from(raw));
    return BotInfo(
      id: (j['id'] as num).toInt(),
      name: j['name'] as String? ?? '',
      role: j['role'] as String? ?? '',
      status: j['status'] as String? ?? '',
      engine: j['engine'] as String? ?? '',
      last: j['last'] as String?,
      lastText: j['last_text'] as String?,
      progress: j['progress'] as String?,
      archived: j['archived'] as bool? ?? false,
      question: q,
      topicId: j.containsKey('topic_id')
          ? (j['topic_id'] as num?)?.toInt()
          : null,
      generalFlag: j.containsKey('general') ? j['general'] as bool? : null,
    );
  }
}

BotInfo? generalOf(List<BotInfo> bots) {
  for (final b in bots) {
    if (b.isGeneral) return b;
  }
  return null;
}

List<BotInfo> workersOf(List<BotInfo> bots) =>
    bots.where((b) => !b.isGeneral).toList();

/// `Message from deploy-watch:\n…` as listen writes inbox turns.
({String? sender, String body}) inboxPayload(String input) {
  const prefix = 'Message from ';
  if (!input.startsWith(prefix)) return (sender: null, body: input);
  final i = input.indexOf(':\n');
  if (i < 0) return (sender: null, body: input);
  final sender = input.substring(prefix.length, i).trim();
  if (sender.isEmpty) return (sender: null, body: input);
  return (sender: sender, body: input.substring(i + 2));
}

/// How a turn should look in chat. Owner bubbles stay right; everything else
/// is a log line so worker reports are not painted as messages the owner sent.
class TurnDisplay {
  TurnDisplay({
    required this.owner,
    this.caption,
    this.quote,
    required this.output,
    this.hide = false,
  });
  final bool owner;
  final String? caption;
  final String? quote;
  final String output;
  final bool hide;

  factory TurnDisplay.from(TurnInfo t, {required bool inGeneral}) {
    final src = t.source;
    if (inGeneral && src == 'system') {
      return TurnDisplay(owner: false, output: '', hide: true);
    }
    if (src == 'user') {
      return TurnDisplay(owner: true, quote: t.input, output: t.output);
    }
    final parsed = inboxPayload(t.input);
    if (src == 'bot' || parsed.sender != null) {
      if (inGeneral) {
        final out = t.output.trim();
        return TurnDisplay(
          owner: false,
          caption: parsed.sender ?? 'session',
          quote: out.isEmpty ? parsed.body : null,
          output: t.output,
        );
      }
      return TurnDisplay(
        owner: false,
        caption: parsed.sender ?? 'Chief',
        quote: parsed.sender != null ? parsed.body : t.input,
        output: t.output,
      );
    }
    return TurnDisplay(
      owner: false,
      caption: src.isEmpty ? null : src,
      quote: t.input,
      output: t.output,
    );
  }
}

String statusLabel(String status) {
  switch (status) {
    case 'running':
    case 'waiting':
    case 'idle':
      return status;
    case 'disabled':
      return 'idle';
    default:
      return status.trim().isEmpty ? 'idle' : status;
  }
}

String statusCaption(String status) {
  final s = statusLabel(status);
  if (s.isEmpty) return s;
  return '${s[0].toUpperCase()}${s.substring(1)}';
}

class FileInfo {
  FileInfo({
    required this.id,
    required this.name,
    required this.mime,
    required this.size,
  });
  final int id;
  final String name;
  final String mime;
  final int size;
  factory FileInfo.fromJson(Map<String, dynamic> j) => FileInfo(
    id: (j['id'] as num).toInt(),
    name: j['name'] as String? ?? 'file',
    mime: j['mime'] as String? ?? 'application/octet-stream',
    size: (j['size'] as num?)?.toInt() ?? 0,
  );
}

class PendingAttach {
  PendingAttach({required this.name, required this.mime, required this.bytes});
  final String name;
  final String mime;
  final Uint8List bytes;
  bool get isImage => mime.startsWith('image/');
}

String fmtSize(int n) {
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024)
    return '${(n / 1024).toStringAsFixed(n < 10 * 1024 ? 1 : 0)} KB';
  return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String mimeForName(String name) {
  final i = name.lastIndexOf('.');
  final ext = i < 0 ? '' : name.substring(i).toLowerCase();
  switch (ext) {
    case '.apk':
      return 'application/vnd.android.package-archive';
    case '.png':
      return 'image/png';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.gif':
      return 'image/gif';
    case '.webp':
      return 'image/webp';
    case '.pdf':
      return 'application/pdf';
    case '.zip':
      return 'application/zip';
    case '.txt':
      return 'text/plain';
    default:
      return 'application/octet-stream';
  }
}

const hubFileInlineMax = 400 * 1024;
const hubChunkBytes = 96 * 1024;
const hubFileMaxBytes = 50 * 1024 * 1024;

class TurnInfo {
  TurnInfo({
    required this.id,
    required this.source,
    required this.input,
    required this.output,
    required this.status,
    required this.at,
    this.progress,
    this.files = const [],
  });
  final int id;
  final String source;
  final String input;
  final String output;
  final String status;
  final String at;
  final String? progress;
  final List<FileInfo> files;
  factory TurnInfo.fromJson(Map<String, dynamic> j) {
    final files = <FileInfo>[];
    final raw = j['files'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map<String, dynamic>) files.add(FileInfo.fromJson(e));
      }
    }
    return TurnInfo(
      id: (j['id'] as num).toInt(),
      source: j['source'] as String? ?? '',
      input: j['input'] as String? ?? '',
      output: j['output'] as String? ?? '',
      status: j['status'] as String? ?? '',
      at: j['at'] as String? ?? '',
      progress: j['progress'] as String?,
      files: files,
    );
  }
}

class Store {
  static const _k = 'ccc.machines';
  static Future<List<Machine>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_k) ?? [];
    return raw
        .map((e) => Machine.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  static Future<void> save(List<Machine> ms) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_k, ms.map((e) => jsonEncode(e.toJson())).toList());
  }
}

List<BotInfo> botsFrom(Map<String, dynamic> res) {
  final body = res['body'];
  final raw = body is String ? jsonDecode(body) : body;
  final list = <BotInfo>[];
  if (raw is List) {
    for (final e in raw) {
      list.add(BotInfo.fromJson(Map<String, dynamic>.from(e as Map)));
    }
  }
  return list;
}

List<QuestionInfo> questionsFrom(Map<String, dynamic> res) {
  final body = res['body'];
  final raw = body is String ? jsonDecode(body) : body;
  final list = <QuestionInfo>[];
  if (raw is List) {
    for (final e in raw) {
      list.add(QuestionInfo.fromJson(Map<String, dynamic>.from(e as Map)));
    }
  }
  return list;
}

class HubSession {
  HubSession(this.identity, this.machine);
  final HubIdentity identity;
  final Machine machine;
  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _ping;
  Timer? _retry;
  bool _want = false;
  int _backoff = 1;
  int _gen = 0;
  Future<void>? _opening;
  int _rpc = 0;
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  final _listeners = <void Function(String kind, Map<String, dynamic> body)>[];

  void addListener(void Function(String kind, Map<String, dynamic> body) f) =>
      _listeners.add(f);
  void removeListener(
    void Function(String kind, Map<String, dynamic> body) f,
  ) => _listeners.remove(f);

  static Future<HubIdentity> loadIdentity() async {
    const store = FlutterSecureStorage();
    var privHex = await store.read(key: 'ccc.priv');
    var pubHex = await store.read(key: 'ccc.pub');
    if (privHex == null || pubHex == null) {
      final priv = nacl.PrivateKey.generate();
      privHex = _hex(priv.asTypedList);
      pubHex = _hex(priv.publicKey.asTypedList);
      await store.write(key: 'ccc.priv', value: privHex);
      await store.write(key: 'ccc.pub', value: pubHex);
    }
    return HubIdentity(_unhex(privHex), _unhex(pubHex));
  }

  Future<void> connect() async {
    _want = true;
    if (_ch != null) return;
    _backoff = 1;
    _opening ??= _open().whenComplete(() => _opening = null);
    await _opening;
  }

  void wake() {
    _want = true;
    if (_ch == null) {
      connect();
      return;
    }
    try {
      _ch!.sink.add(jsonEncode({'v': 1, 't': 'ping'}));
    } catch (_) {
      _dropped();
    }
  }

  Future<void> _open() async {
    await _tear();
    if (!_want) return;
    final gen = _gen;
    try {
      _ch = IOWebSocketChannel.connect(
        _ws(machine.hub),
        pingInterval: const Duration(seconds: 20),
      );
      _ch!.sink.add(
        jsonEncode({'v': 1, 't': 'open', 'role': 'device', 'pk': identity.id}),
      );
      _sub = _ch!.stream.listen(
        _onFrame,
        onError: (_) {
          if (gen == _gen) _dropped();
        },
        onDone: () {
          if (gen == _gen) _dropped();
        },
        cancelOnError: true,
      );
      _ping = Timer.periodic(const Duration(seconds: 30), (_) {
        try {
          _ch?.sink.add(jsonEncode({'v': 1, 't': 'ping'}));
        } catch (_) {}
      });
      _backoff = 1;
      for (final f in List.of(_listeners)) {
        f('up', {});
      }
    } catch (_) {
      if (gen == _gen) _dropped();
    }
  }

  void _dropped() {
    if (!_want) return;
    _failPending('disconnected');
    _ping?.cancel();
    _ping = null;
    if (_retry?.isActive ?? false) return;
    final wait = Duration(seconds: _backoff);
    _backoff = min(30, _backoff * 2);
    _retry = Timer(wait, () {
      if (_want) _open();
    });
  }

  void _failPending(Object e) {
    final pending = Map<String, Completer<Map<String, dynamic>>>.from(_pending);
    _pending.clear();
    for (final c in pending.values) {
      if (!c.isCompleted) c.completeError(e);
    }
  }

  Future<void> _tear() async {
    _gen++;
    _ping?.cancel();
    _ping = null;
    _retry?.cancel();
    _retry = null;
    await _sub?.cancel();
    _sub = null;
    try {
      await _ch?.sink.close();
    } catch (_) {}
    _ch = null;
  }

  Uri _ws(String hub) {
    var u = Uri.parse(hub);
    if (u.scheme == 'https') u = u.replace(scheme: 'wss');
    if (u.scheme == 'http') u = u.replace(scheme: 'ws');
    return u.replace(path: '/v1/ws');
  }

  void _onFrame(dynamic raw) {
    final f = jsonDecode(raw as String) as Map<String, dynamic>;
    final t = f['t'] as String? ?? '';
    if (t == 'err') {
      final id = f['id'] as String?;
      if (id != null) _pending.remove(id)?.completeError(f['err'] ?? 'err');
      return;
    }
    if (t != 'fwd' && t != 'pair') return;
    final nonce = _b64(f['n'] as String? ?? '');
    final ct = _b64(f['b'] as String? ?? '');
    if (nonce.length != 24) return;
    final box = nacl.Box(
      myPrivateKey: nacl.PrivateKey(identity.private),
      theirPublicKey: nacl.PublicKey(_unhex(machine.pk)),
    );
    final opened = box.decrypt(
      nacl.EncryptedMessage(cipherText: ct, nonce: nonce),
    );
    final rpc = jsonDecode(utf8.decode(opened)) as Map<String, dynamic>;
    final kind = rpc['kind'] as String? ?? '';
    if (kind == 'event') {
      var body = <String, dynamic>{};
      final rawBody = rpc['body'];
      if (rawBody is Map<String, dynamic>) body = rawBody;
      if (rawBody is String && rawBody.isNotEmpty) {
        try {
          body = jsonDecode(rawBody) as Map<String, dynamic>;
        } catch (_) {}
      }
      final method = rpc['method'] as String? ?? 'event';
      for (final f in List.of(_listeners)) {
        f(method, body);
      }
      return;
    }
    if (kind == 'pair') {
      _pending.remove('pair')?.complete(rpc);
      return;
    }
    final id = rpc['id'] as String? ?? '';
    _pending.remove(id)?.complete(rpc);
  }

  Future<Map<String, dynamic>> pair(Pairing p) async {
    final c = Completer<Map<String, dynamic>>();
    _pending['pair'] = c;
    final intro = jsonEncode({'name': 'phone', 'pk': identity.id});
    final sealed = _seal(utf8.encode(intro), p.instancePk);
    _ch!.sink.add(
      jsonEncode({
        'v': 1,
        't': 'pair',
        'code': p.code,
        'n': _b64e(sealed.$1),
        'b': _b64e(sealed.$2),
      }),
    );
    return c.future.timeout(const Duration(seconds: 20));
  }

  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 20),
  ]) async {
    final id = '${++_rpc}';
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    final payload = jsonEncode({
      'kind': 'req',
      'id': id,
      'method': method,
      'params': ?params,
    });
    final sealed = _seal(utf8.encode(payload), machine.pk);
    _ch!.sink.add(
      jsonEncode({
        'v': 1,
        't': 'fwd',
        'to': machine.id,
        'id': id,
        'n': _b64e(sealed.$1),
        'b': _b64e(sealed.$2),
      }),
    );
    final rpc = await c.future.timeout(timeout);
    if (rpc['ok'] == false) {
      throw rpc['error'] ?? 'error';
    }
    return rpc;
  }

  Map<String, dynamic> _rpcBody(Map<String, dynamic> rpc) {
    final body = rpc['body'];
    if (body is Map<String, dynamic>) return body;
    if (body is String && body.isNotEmpty) {
      final j = jsonDecode(body);
      if (j is Map<String, dynamic>) return j;
    }
    return {};
  }

  Future<void> sendBytes({
    required int botId,
    required String name,
    required String mime,
    required Uint8List bytes,
    String text = '',
  }) async {
    if (bytes.length > hubFileMaxBytes) {
      throw 'File is too large (max 50 MB)';
    }
    if (bytes.length <= hubFileInlineMax) {
      await rpc('send', {
        'bot_id': botId,
        if (text.isNotEmpty) 'text': text,
        'file': {'name': name, 'mime': mime, 'data': base64Encode(bytes)},
      }, const Duration(seconds: 40));
      return;
    }
    final begin = _rpcBody(
      await rpc('put_begin', {
        'bot_id': botId,
        'name': name,
        'mime': mime,
        'size': bytes.length,
        if (text.isNotEmpty) 'text': text,
      }),
    );
    final uploadId = begin['upload_id'] as String? ?? '';
    final n = (begin['n'] as num?)?.toInt() ?? 1;
    if (uploadId.isEmpty) throw 'upload failed';
    for (var i = 0; i < n; i++) {
      final start = i * hubChunkBytes;
      var end = start + hubChunkBytes;
      if (end > bytes.length) end = bytes.length;
      await rpc('put_chunk', {
        'upload_id': uploadId,
        'i': i,
        'data': base64Encode(bytes.sublist(start, end)),
      }, const Duration(seconds: 40));
    }
    await rpc('put_commit', {
      'upload_id': uploadId,
      if (text.isNotEmpty) 'text': text,
    }, const Duration(seconds: 40));
  }

  Future<Uint8List> fetchFile(int fileId) async {
    final first = _rpcBody(
      await rpc('get_chunk', {
        'file_id': fileId,
        'i': 0,
      }, const Duration(seconds: 40)),
    );
    final n = (first['n'] as num?)?.toInt() ?? 1;
    final size = (first['size'] as num?)?.toInt() ?? 0;
    final out = BytesBuilder(copy: false);
    void addChunk(Map<String, dynamic> chunk) {
      final data = chunk['data'] as String? ?? '';
      out.add(base64Decode(data));
    }

    addChunk(first);
    for (var i = 1; i < n; i++) {
      addChunk(
        _rpcBody(
          await rpc('get_chunk', {
            'file_id': fileId,
            'i': i,
          }, const Duration(seconds: 40)),
        ),
      );
    }
    final bytes = out.toBytes();
    if (size > 0 && bytes.length != size) {
      throw 'download truncated (${bytes.length}/$size)';
    }
    return bytes;
  }

  (Uint8List, Uint8List) _seal(List<int> plain, String theirHex) {
    final box = nacl.Box(
      myPrivateKey: nacl.PrivateKey(identity.private),
      theirPublicKey: nacl.PublicKey(_unhex(theirHex)),
    );
    final nonce = Uint8List(24);
    final r = Random.secure();
    for (var i = 0; i < 24; i++) {
      nonce[i] = r.nextInt(256);
    }
    final enc = box.encrypt(Uint8List.fromList(plain), nonce: nonce);
    return (Uint8List.fromList(enc.nonce), Uint8List.fromList(enc.cipherText));
  }

  Future<void> close() async {
    _want = false;
    _failPending('closed');
    await _tear();
  }
}

Uint8List _b64(String s) {
  var t = s.replaceAll('-', '+').replaceAll('_', '/');
  while (t.length % 4 != 0) {
    t += '=';
  }
  return Uint8List.fromList(base64.decode(t));
}

String _b64e(List<int> b) => base64Url.encode(b).replaceAll('=', '');
