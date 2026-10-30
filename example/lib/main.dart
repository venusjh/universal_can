import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:universal_can/universal_can.dart';

void main() => runApp(const CanExampleApp());

class CanExampleApp extends StatelessWidget {
  const CanExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Universal CAN Example',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const CanExampleScreen(),
      );
}

class CanExampleScreen extends StatefulWidget {
  const CanExampleScreen({super.key});

  @override
  State<CanExampleScreen> createState() => _CanExampleScreenState();
}

class _CanExampleScreenState extends State<CanExampleScreen> {
  final _client = BluetoothCanClient();
  final _addressController = TextEditingController();
  final _log = <String>[];
  StreamSubscription<CanDataPackType>? _frames;
  bool _connected = false;
  bool _canStarted = false;

  void _addLog(String message) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, message);
      if (_log.length > 50) _log.removeLast();
    });
  }

  Future<void> _connect() async {
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      _addLog('Enter the Bluetooth Classic device address.');
      return;
    }

    final connected = await _client.connect(address);
    if (!mounted) return;
    setState(() => _connected = connected);
    _addLog(connected ? 'Bluetooth connected.' : 'Connection failed.');
    if (!connected) return;

    _frames = _client.frames.listen((frame) {
      _addLog('RX 0x${frame.id.toRadixString(16)}: ${frame.data}');
    });

    final started = await _client.connectCan(
      channel: 0,
      baudRate: CanBaudRate.cb125k,
      busMode: CanBusMode.cbmNormal,
    );
    if (!mounted) return;
    setState(() => _canStarted = started);
    _addLog(started ? 'CAN channel opened.' : 'Could not open CAN channel.');
  }

  Future<void> _sendFrame() async {
    final sent = await _client.sendCanFrame(
      0x123,
      Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
      channel: 0,
      isExtended: false,
    );
    _addLog(sent ? 'TX frame sent.' : 'TX frame failed.');
  }

  Future<void> _disconnect() async {
    await _frames?.cancel();
    _frames = null;
    if (_canStarted) await _client.disconnectCan(channel: 0);
    await _client.disconnect();
    if (!mounted) return;
    setState(() {
      _connected = false;
      _canStarted = false;
    });
    _addLog('Disconnected.');
  }

  @override
  void dispose() {
    _frames?.cancel();
    _addressController.dispose();
    unawaited(_client.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Universal CAN Example')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Connect to a Bluetooth Classic serial device that implements '
              'the package binary protocol.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressController,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Bluetooth device address',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: _connected ? null : _connect,
                  child: const Text('Connect and start CAN'),
                ),
                OutlinedButton(
                  onPressed: _connected ? _disconnect : null,
                  child: const Text('Disconnect'),
                ),
                OutlinedButton(
                  onPressed: _canStarted ? _sendFrame : null,
                  child: const Text('Send test frame'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Status: ${_canStarted ? 'CAN active' : _connected ? 'Connected' : 'Disconnected'}',
            ),
            const Divider(),
            for (final entry in _log) Text(entry),
          ],
        ),
      );
}
