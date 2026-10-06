import 'package:hive/hive.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:ble_peer_session/ble_peer_session.dart';
import 'package:firebase_database/firebase_database.dart';

class OfflineService {
  static final Box _msgBox = Hive.box('offline_messages');
  static final Peer _peer = Peer.create(appName: 'SLine');

  static Future<void> init() async {
    await Hive.openBox('offline_messages');
    await _peer.initialize();
    _startBluetoothListener();
  }

  static void _startBluetoothListener() {
    _peer.nearbyHostsStream.listen((hosts) {
      if (hosts.isEmpty) return;
      for (var host in hosts) {
        _peer.connect(host).then((conn) {
          conn.onTextMessage.listen((msg) {
            _saveMessage(msg);
          });
        });
      }
    });
  }

  static Future<void> sendMessage(String chatKey, String content, bool isText) async {
    final localId = DateTime.now().millisecondsSinceEpoch.toString();
    final msg = {
      'id': localId,
      'content': content,
      'type': isText ? 'text' : 'voice',
      'timestamp': DateTime.now().toIso8601String(),
      'offline': true,
      'chatKey': chatKey,
    };

    // 1. Hive (полностью оффлайн)
    await _msgBox.put(localId, msg);

    // 2. Firebase (даже без интернета — в очередь)
    await FirebaseDatabase.instance.ref('offline_msgs/$chatKey/$localId').set(msg);

    // 3. Bluetooth (P2P, если другой телефон рядом)
    if (_peer.isConnected) {
      await _peer.sendTextMessage('SLine', content);
    }
  }

  static List<Map> getOfflineMessages(String chatKey) {
    return _msgBox.values
        .where((m) => m['chatKey'] == chatKey || m['id'].startsWith(chatKey))
        .toList()
      ..sort((a, b) => (a['timestamp'] as String).compareTo(b['timestamp'] as String));
  }

  static void _saveMessage(Map msg) {
    _msgBox.put(msg['id'], msg);
  }
}