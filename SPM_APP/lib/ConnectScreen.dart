import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import 'main.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({Key? key}) : super(key: key);

  @override
  _ConnectScreenState createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final flutterReactiveBle = FlutterReactiveBle();

  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _dataSubscription;

  List<DiscoveredDevice> _devicesList = [];
  List<String> _receivedMessages = [];
  bool _isScanning = false;
  bool _permissionDenied = false;
  bool _isConnected = false;
  String _connectedDeviceId = "";
  bool _hasNavigatedToDashboard = false; // Flag to prevent multiple navigations

  // UUIDs from your ESP32 code
  final Uuid serviceUuid = Uuid.parse("12345678-1234-1234-1234-1234567890ab");
  final Uuid characteristicUuid = Uuid.parse("abcdefab-1234-1234-1234-abcdefabcdef");

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndStartScan();
  }

  Future<void> _checkPermissionsAndStartScan() async {
    // Request location permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    // Check if location permission is granted
    if (statuses[Permission.location]!.isGranted) {
      _startScan();
    } else {
      setState(() {
        _permissionDenied = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Location permission is required for Bluetooth scanning"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _startScan() {
    setState(() {
      _isScanning = true;
      _devicesList = [];
    });

    _scanSubscription?.cancel();
    _scanSubscription = flutterReactiveBle.scanForDevices(
      withServices: [], // Empty list means scan for all devices
      scanMode: ScanMode.lowLatency,
    ).listen(
            (device) {
          // Look for devices with "ESP32" in the name
          if (device.name.contains('ESP32') &&
              !_devicesList.any((d) => d.id == device.id)) {
            setState(() {
              _devicesList.add(device);
            });
          }
        },
        onError: (e) {
          print("Scan error: $e");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Scan error: $e")),
          );
          setState(() {
            _isScanning = false;
          });
        },
        onDone: () {
          setState(() {
            _isScanning = false;
          });
        }
    );

    // Stop scanning after 15 seconds
    Future.delayed(const Duration(seconds: 15), () {
      if (_isScanning) {
        _stopScan();
      }
    });
  }

  void _stopScan() {
    _scanSubscription?.cancel();
    setState(() {
      _isScanning = false;
    });
  }

  Future<void> _connectToDevice(DiscoveredDevice device) async {
    try {
      setState(() {
        _isConnected = false;
        _connectedDeviceId = "";
        _hasNavigatedToDashboard = false; // Reset navigation flag when connecting to a new device
      });

      // Cancel any existing connection
      await _connectionSubscription?.cancel();
      await _dataSubscription?.cancel();

      // Connect to the device
      _connectionSubscription = flutterReactiveBle.connectToDevice(
        id: device.id,
        connectionTimeout: const Duration(seconds: 15),
      ).listen(
            (connectionState) {
          print("Connection state: ${connectionState.connectionState}");

          if (connectionState.connectionState == DeviceConnectionState.connected) {
            setState(() {
              _isConnected = true;
              _connectedDeviceId = device.id;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("✅ Connected to ESP32")),
            );

            // After connection, discover services and subscribe to the characteristic
            _discoverServicesAndSubscribe(device.id);
          } else if (connectionState.connectionState == DeviceConnectionState.disconnected) {
            setState(() {
              _isConnected = false;
              _connectedDeviceId = "";
            });

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("❌ Disconnected from device")),
            );
          }
        },
        onError: (error) {
          print("Connection error: $error");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("❌ Connection error: $error")),
          );
          setState(() {
            _isConnected = false;
            _connectedDeviceId = "";
          });
        },
      );
    } catch (e) {
      print("Error connecting to device: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Connection failed: $e")),
      );
    }
  }

  Future<void> _discoverServicesAndSubscribe(String deviceId) async {
    try {
      print("Discovering services...");

      // Create a qualified characteristic for the ESP32's notification characteristic
      final characteristic = QualifiedCharacteristic(
        deviceId: deviceId,
        serviceId: serviceUuid,
        characteristicId: characteristicUuid,
      );

      // Subscribe to the characteristic
      _dataSubscription = flutterReactiveBle.subscribeToCharacteristic(characteristic).listen(
            (data) {
          // Convert the data to a string (the ESP32 is sending strings)
          final receivedMessage = String.fromCharCodes(data);
          // print("📥 Received: $receivedMessage");

          setState(() {
            _receivedMessages.add(receivedMessage);
            // Keep only the last 10 messages
            if (_receivedMessages.length > 10) {
              _receivedMessages.removeAt(0);
            }
          });

          // Don't automatically navigate - we'll use a button instead
        },
        onError: (error) {
          print("Subscription error: $error");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("❌ Subscription error: $error")),
          );
        },
      );
    } catch (e) {
      print("Error discovering services: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error discovering services: $e")),
      );
    }
  }

  // Method to navigate to the dashboard when the button is pressed
  void _navigateToDashboard() {
    if (!_hasNavigatedToDashboard) {
      setState(() {
        _hasNavigatedToDashboard = true;
      });

      // Cancel data subscription to prevent background processing
      // _dataSubscription?.cancel();

      Navigator.pushReplacement( // Using pushReplacement instead of push
        context,
        MaterialPageRoute(
          builder: (context) => PowerDashboard(
            deviceId: _connectedDeviceId,
            flutterReactiveBle: flutterReactiveBle,
            serviceUuid: serviceUuid,
            characteristicUuid: characteristicUuid,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _dataSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Connect to SmartPower',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.yellow,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_permissionDenied)
              Column(
                children: [
                  const Text(
                    '❌ Location permission denied',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _checkPermissionsAndStartScan,
                    child: const Text('Request Permissions'),
                  ),
                ],
              )
            else if (_isScanning && _devicesList.isEmpty)
              Column(
                children: const [
                  Text('🔍 Scanning for ESP32 devices...'),
                  SizedBox(height: 20),
                  CircularProgressIndicator(),
                ],
              )
            else if (_devicesList.isEmpty)
                Column(
                  children: [
                    const Text('No ESP32 devices found'),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _startScan,
                      child: const Text('Scan Again'),
                    ),
                  ],
                )
              else
                Expanded(
                  child: Column(
                    children: [
                      const Text('📱 Available Devices',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _devicesList.length,
                          itemBuilder: (context, index) {
                            final device = _devicesList[index];
                            final bool isConnected = _isConnected && device.id == _connectedDeviceId;

                            return Card(
                              elevation: 3,
                              margin: EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                              child: ListTile(
                                title: Text(device.name),
                                subtitle: Text(device.id),
                                trailing: isConnected
                                    ? Icon(Icons.bluetooth_connected, color: Colors.green)
                                    : Icon(Icons.bluetooth, color: Colors.blue),
                                leading: CircleAvatar(
                                  backgroundColor: isConnected ? Colors.green : Colors.blue,
                                  child: Text(device.name.substring(0, 1)),
                                ),
                                onTap: () => _connectToDevice(device),
                              ),
                            );
                          },
                        ),
                      ),

                      if (_receivedMessages.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text('📊 Data Stream',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                        ),
                        const SizedBox(height: 10),
                        Container(
                          height: 150,
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ListView.builder(
                            itemCount: _receivedMessages.length,
                            itemBuilder: (context, index) {
                              return Text('• ${_receivedMessages[index]}');
                            },
                          ),
                        ),

                        // Add View Dashboard button when we have received messages
                        if (_receivedMessages.length > 3 && _isConnected)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16.0),
                            child: ElevatedButton(
                              onPressed: _navigateToDashboard,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.yellow,
                                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                              ),
                              child: Text(
                                'View Dashboard',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isScanning ? null : _startScan,
        backgroundColor: _isScanning ? Colors.grey : Colors.yellow,
        child: Icon(Icons.refresh, color: Colors.black),
      ),
    );
  }
}