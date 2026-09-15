import 'package:ccc_app/hub.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses ccc pair URI', () {
    const raw = 'ccc://pair/v1?h=wss://hub.getccc.dev&i=ab&k=cd&n=c0ffee';
    final p = Pairing.parse(raw)!;
    expect(p.hub, 'wss://hub.getccc.dev');
    expect(p.instanceId, 'ab');
    expect(p.code, 'c0ffee');
  });
}
