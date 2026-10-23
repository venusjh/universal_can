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
  // 패키지가 제공하는 블루투스 CAN 클라이언트
  final BluetoothCanClient _bluetoothClient = BluetoothCanClient();

  String _status = '연결 안 됨';
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
      _addLog('Bluetooth 장치 검색 시작...');
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
              _addLog('타겟 장치 발견: ${result.device.name ?? '알 수 없음'} (${result.device.address})');
            }
          }
        },
        onDone: () {
          _addLog('Bluetooth 검색 완료');
        },
      );
    } catch (e) {
      _addLog('Bluetooth 검색 에러: $e');
    }
  }

  Future<void> connectBluetooth(String address) async {
    _addLog('블루투스 연결 시도 중... ($address)');

    try {
      final result = await _bluetoothClient.connect(address);

      if (result) {
        setState(() {
          _status = 'Bluetooth 연결 성공';
        });
        _addLog('Bluetooth 연결 성공!');

        // 패키지의 connectCan API 호출 (내부적으로 scConnect 및 CRC 자동 처리)
        final canConnect = await _bluetoothClient.connectCan(
          channel: 0,
          baudRate: CanBaudRate.cb125k,
          busMode: CanBusMode.cbmNormal,
        );

        _addLog('CAN 버스 초기화 결과: $canConnect');

        if (canConnect) {
          setState(() {
            _status = 'Bluetooth CAN 초기화 완료';
          });
        }

        // 패키지 내부의 파싱된 프레임 스트림 구독
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
        _addLog('프레임 리스닝 스트림 구독 완료');

      } else {
        setState(() {
          _status = 'Bluetooth 연결 실패';
        });
        _addLog('Bluetooth 연결 거부됨');
      }
    } catch (e, stack) {
      _addLog('연결 중 예외 발생: $e');
      debugPrint('$stack');
      setState(() {
        _status = 'Bluetooth 연결 에러 발생';
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

      _addLog('단발 테스트 프레임 전송 결과: ${success ? "성공" : "실패"}');
    } catch (e) {
      _addLog('TX 에러: $e');
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
          _addLog('TX [가상 데이터 루프]: 카운터 $counter 전송 성공');
        } else {
          _addLog('TX [가상 데이터 루프]: 전송 거부됨');
        }
      } catch (e) {
        _addLog('가상 데이터 전송 에러: $e');
        timer.cancel();
      }
    });
    _addLog('가상 데이터 송신 루프 시작');
  }

  void stopSendingMockData() {
    _mockSendTimer?.cancel();
    _mockSendTimer = null;
    _addLog('가상 데이터 송신 루프 중지');
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
                  '현재 상태: $_status',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 기기 검색 및 리스트
            ElevatedButton.icon(
              onPressed: startDiscovery,
              icon: const Icon(Icons.search),
              label: const Text('타겟 장치 검색 (E0:5A:1B:05:A0:5A)'),
            ),
            const SizedBox(height: 8),

            SizedBox(
              height: 100,
              child: ListView.builder(
                itemCount: _devices.isEmpty ? 1 : _devices.length,
                itemBuilder: (context, index) {
                  if (_devices.isEmpty) {
                    return const Center(
                      child: Text('검색된 장치가 없습니다. 버튼을 눌러 검색하세요.', style: TextStyle(color: Colors.grey)),
                    );
                  }
                  final device = _devices[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text(device.name ?? '이름 없음'),
                      subtitle: Text(device.address),
                      trailing: ElevatedButton(
                        onPressed: () => connectBluetooth(device.address),
                        child: const Text('연결'),
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
                    child: const Text('단발 프레임 전송'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: startSendingMockData,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    child: const Text('루프 시작'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: stopSendingMockData,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                    child: const Text('루프 중지'),
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
                  '정상 수신: $_btReceivedFrameCount 개',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                ),
                Text(
                  '에러: $_btErrorFrameCount 개',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 로그 콘솔 영역
            const Text(
              '실시간 통신 로그',
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