import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pinenacl/x25519.dart' as nacl;
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
  Pairing({required this.hub, required this.instanceId, required this.instancePk, required this.code});
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
  Machine({required this.hub, required this.id, required this.pk, required this.name});
  final String hub;
  final String id;
  final String pk;
  String name;
  Map<String, dynamic> toJson() => {'hub': hub, 'id': id, 'pk': pk, 'name': name};
  static Machine fromJson(Map<String, dynamic> j) => Machine(
        hub: j['hub'] as String,
        id: j['id'] as String,
        pk: j['pk'] as String,
        name: j['name'] as String? ?? 'ccc',
      );
}

class BotInfo {
  BotInfo({required this.id, required this.name, required this.role, required this.status, required this.engine, this.last});
  final int id;
  final String name;
  final String role;
  final String status;
  final String engine;
  final String? last;
  factory BotInfo.fromJson(Map<String, dynamic> j) => BotInfo(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? '',
        role: j['role'] as String? ?? '',
        status: j['status'] as String? ?? '',
        engine: j['engine'] as String? ?? '',
        last: j['last'] as String?,
      );
}

class TurnInfo {
  TurnInfo({required this.id, required this.source, required this.input, required this.output, required this.status, required this.at});
  final int id;
  final String source;
  final String input;
  final String output;
  final String status;
  final String at;
  factory TurnInfo.fromJson(Map<String, dynamic> j) => TurnInfo(
        id: (j['id'] as num).toInt(),
        source: j['source'] as String? ?? '',
        input: j['input'] as String? ?? '',
        output: j['output'] as String? ?? '',
        status: j['status'] as String? ?? '',
        at: j['at'] as String? ?? '',
      );
}

class HubSession {
  HubSession(this.identity, this.machine);
  final HubIdentity identity;
  final Machine machine;
  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  int _rpc = 0;
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  void Function(String kind, Map<String, dynamic> body)? onEvent;

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
    await close();
    _ch = WebSocketChannel.connect(_ws(machine.hub));
    _ch!.sink.add(jsonEncode({'v': 1, 't': 'open', 'role': 'device', 'pk': identity.id}));
    _sub = _ch!.stream.listen(_onFrame, onError: (_) {}, cancelOnError: true);
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
    final opened = box.decrypt(nacl.EncryptedMessage(cipherText: ct, nonce: nonce));
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
      onEvent?.call(rpc['method'] as String? ?? 'event', body);
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
    _ch!.sink.add(jsonEncode({
      'v': 1,
      't': 'pair',
      'code': p.code,
      'n': _b64e(sealed.$1),
      'b': _b64e(sealed.$2),
    }));
    return c.future.timeout(const Duration(seconds: 20));
  }

  Future<Map<String, dynamic>> rpc(String method, [Map<String, dynamic>? params]) async {
    final id = '${++_rpc}';
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    final payload = jsonEncode({
      'kind': 'req',
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    });
    final sealed = _seal(utf8.encode(payload), machine.pk);
    _ch!.sink.add(jsonEncode({
      'v': 1,
      't': 'fwd',
      'to': machine.id,
      'id': id,
      'n': _b64e(sealed.$1),
      'b': _b64e(sealed.$2),
    }));
    return c.future.timeout(const Duration(seconds: 20));
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
    await _sub?.cancel();
    _sub = null;
    await _ch?.sink.close();
    _ch = null;
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
