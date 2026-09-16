import 'package:ccc_app/hub.dart';
import 'package:ccc_app/notify.dart';
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

  test('notifies on post unless that chat is open', () {
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
  });

  test('parses notification payload', () {
    final p = parseNotifyPayload('{"machine":"abc","bot_id":9}');
    expect(p?.machine, 'abc');
    expect(p?.bot, 9);
    expect(parseNotifyPayload('nope'), isNull);
  });
}
