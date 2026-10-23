import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';
import 'package:universal_can/universal_can.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Universal CAN Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const TestScreen(),
    );
  }
}

class TestScreen extends StatefulWidget {
  const TestScreen({super.key});

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
// Bluetooth CAN client provided by the package
  final BluetoothCanClient _bluetoothClient = BluetoothCanClient();

  String _status = 'Not connected';
  final List<BluetoothDevice> _devices = [];
  StreamSubscription? _btCanSub;

  int _btReceivedFrameCount = 0;
  int _btErrorFrameCount = 0;
  Timer? _mockSendTimer;

  final List<String> _logs = [];

  @override
  void dispose() {
    _btCanSub?.cancel();
    _mockSendTimer?.cancel();
    _bluetoothClient.dispose();
    super.dispose();
  }

  void _addLog(String message) {
    setState(() {
      _logs.insert(0, '[${DateTime.now().toString().substring(11, 19)}] $message');
      if (_logs.length > 100) _logs.removeLast();
    });
  }

  // ==========================================
  // Bluetooth 장치 검색 및 연결
  // ==========================================
  Future<void> startDiscovery() async {
    try {
      _addLog('Start searching for Bluetooth devices...');
      await FlutterBluetoothSerial.instance.cancelDiscovery();
      _devices.clear();

      FlutterBluetoothSerial.instance.startDiscovery().listen(
            (result) {
          const targetAddress = "E0:5A:1B:05:A0:5A";
          if (result.device.address == targetAddress) {
            if (!_devices.contains(result.device)) {
              setState(() {
                _devices.add(result.device);
              });
              _addLog('Target device found: ${result.device.name ?? 'UNKNOWN'} (${result.device.address})');
            }
          }
        },
        onDone: () {
          _addLog('Bluetooth search complete');
        },
      );
    } catch (e) {
      _addLog('Bluetooth search error: $e');
    }
  }

  Future<void> connectBluetooth(String address) async {
    _addLog('Attempting to connect via Bluetooth... ($address)');

    try {
      final result = await _bluetoothClient.connect(address);

      if (result) {
        setState(() {
          _status = 'Bluetooth connection successful';
        });
        _addLog('Bluetooth connection successful!');

        // Calls the package's connectCan API (internally auto-handles scConnect and CRC)
        final canConnect = await _bluetoothClient.connectCan(
          channel: 0,
          baudRate: CanBaudRate.cb125k,
          busMode: CanBusMode.cbmNormal,
        );

        _addLog('CAN bus initialization result: $canConnect');

        if (canConnect) {
          setState(() {
            _status = 'Bluetooth CAN initialization complete';
          });
        }

        // Subscribe to parsed frame streams inside the package
        _btCanSub?.cancel();
        _btCanSub = _bluetoothClient.frames.listen(
              (frame) {
            setState(() {
              _btReceivedFrameCount++;
            });
            _addLog('RX [ID: 0x${frame.id.toRadixString(16)}] Ch: ${frame.channel} Data: ${frame.data}');
          },
          onError: (error) {
            setState(() {
              _btErrorFrameCount++;
            });
            _addLog('Stream Error: $error');
          },
        );
        _addLog('Frame listening stream subscription complete');

      } else {
        setState(() {
          _status = 'Bluetooth connection failed';
        });
        _addLog('Bluetooth connection refused');
      }
    } catch (e, stack) {
      _addLog('Exception occurred during connection: $e');
      debugPrint('$stack');
      setState(() {
        _status = 'Bluetooth connection error occurred';
      });
    }
  }

  // ==========================================
  // CAN 데이터 전송 (패키지 표준 API 활용)
  // ==========================================
  Future<void> sendTestCanFrame() async {
    try {
      final success = await _bluetoothClient.sendCanFrame(
        0x123,
        Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        channel: 0,
        isExtended: false,
      );

      _addLog('Result of single test frame transmission: ${success ? "success" : "failure}"}');
    } catch (e) {
      _addLog('TX error: $e');
    }
  }

  void startSendingMockData() {
    _mockSendTimer?.cancel();

    _mockSendTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        int counter = timer.tick % 256;
        final payload = Uint8List.fromList([
          counter,
          0xAA,
          0x55,
          0x01,
          0x00,
          0x00,
          0x00,
          0xFF,
        ]);

        final success = await _bluetoothClient.sendCanFrame(
          0x123,
          payload,
          channel: 0,
          isExtended: false,
        );

        if (success) {
          _addLog('TX [Virtual Data Loop]: Counter $counter transmission successful');
        } else {
          _addLog('TX [Virtual Data Loop]: Transmission Rejected');
        }
      } catch (e) {
        _addLog('Virtual data transmission error: $e');
        timer.cancel();
      }
    });
    _addLog('Start virtual data transmission loop');
  }

  void stopSendingMockData() {
    _mockSendTimer?.cancel();
    _mockSendTimer = null;
    _addLog('Stop virtual data transmission loop');
  }

  // ==========================================
  // UI
  // ==========================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Universal CAN Example'),
        elevation: 2,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 상태 카드
            Card(
              color: Colors.deepPurple.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  'Current status: $_status',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 기기 검색 및 리스트
            ElevatedButton.icon(
              onPressed: startDiscovery,
              icon: const Icon(Icons.search),
              label: const Text('Search for target devices (E0:5A:1B:05:A0:5A)'),
            ),
            const SizedBox(height: 8),

            SizedBox(
              height: 100,
              child: ListView.builder(
                itemCount: _devices.isEmpty ? 1 : _devices.length,
                itemBuilder: (context, index) {
                  if (_devices.isEmpty) {
                    return const Center(
                      child: Text('No devices found. Please press the button to search.', style: TextStyle(color: Colors.grey)),
                    );
                  }
                  final device = _devices[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text(device.name ?? 'No name'),
                      subtitle: Text(device.address),
                      trailing: ElevatedButton(
                        onPressed: () => connectBluetooth(device.address),
                        child: const Text('connection'),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 24),

            // CAN 제어 버튼 영역
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: sendTestCanFrame,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                    child: const Text('Single frame transmission'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: startSendingMockData,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    child: const Text('Start loop'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: stopSendingMockData,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                    child: const Text('Stop loop'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 카운터 통계
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text(
                  'General reception: $_btReceivedFrameCount',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                ),
                Text(
                  'Error: $_btErrorFrameCount ',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 로그 콘솔 영역
            const Text(
              'Real-time communication logs',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    return Text(
                      _logs[index],
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}