import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:spm_app/ConnectScreen.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: SmartPowerApp(),
  ));
}

class SmartPowerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.yellow,
      ),
      home: ConnectScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class PowerDashboard extends StatefulWidget {
  final String deviceId;
  final FlutterReactiveBle flutterReactiveBle;
  final Uuid serviceUuid;
  final Uuid characteristicUuid;

  const PowerDashboard({
    Key? key,
    required this.deviceId,
    required this.flutterReactiveBle,
    required this.serviceUuid,
    required this.characteristicUuid,
  }) : super(key: key);

  @override
  _PowerDashboardState createState() => _PowerDashboardState();
}

class _PowerDashboardState extends State<PowerDashboard> {
  double voltage = 4.8;
  double current = 0.65;
  double power = 0.0;
  String loadSource = "Main";
  bool relayOn = true;
  bool autoMode = false;
  String systemStatus = "Normal";
  String lastUpdated = "-";
  String appVersion = "v1.0.3"; // Updated version number
  String integrityGrade = "Good";
  List<FlSpot> voltageHistory = [];
  List<FlSpot> currentHistory = [];
  int time = 0;
  List<String> messageLog = [];
  bool _isProcessingData = false; // Flag to prevent reentrancy

  // Maximum number of data points to display in charts
  final int maxDataPoints = 10; // Reduced from 20 to 10 for better performance
  // Maximum number of messages to keep in log
  final int maxLogMessages = 15; // Reduced from 20 to 15

  // Throttling variables
  DateTime _lastUIUpdate = DateTime.now();
  DateTime _lastChartUpdate = DateTime.now();

  StreamSubscription<List<int>>? _dataSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  bool isConnected = true;

  // Buffer for handling high-frequency incoming data
  final List<String> _messageBuffer = [];

  @override
  void initState() {
    super.initState();
    _setupBleConnection();

    // Reduce update frequency from 1s to 2s
    Timer.periodic(Duration(seconds: 2), (_) => updateChartData());

    // Separate timer for processing buffered messages
    Timer.periodic(Duration(milliseconds: 300), (_) {

      if (!_isProcessingData) {
        processBufferedMessages();
      }
    });
  }

  // Throttle control for UI updates
  bool _canUpdateUI() {
    final now = DateTime.now();
    if (now.difference(_lastUIUpdate).inMilliseconds > 300) {
      _lastUIUpdate = now;
      return true;
    }
    return false;
  }

  // Process buffered messages periodically instead of immediately
  void processBufferedMessages() {
    if (_messageBuffer.isEmpty || !mounted) return;

    // Set processing flag to prevent reentrancy
    _isProcessingData = true;

    try {
      // Take a snapshot of the buffer and clear it atomically
      final List messagesToProcess = List.from(_messageBuffer);
      _messageBuffer.clear();

      // Process all messages in batch
      for (final message in messagesToProcess) {
        processESP32Message(message);

        // Add to log
        messageLog.add(message);
        print(message); // This only goes to debug console
      }

      // Efficiently trim message log if needed
      if (messageLog.length > maxLogMessages) {
        messageLog = messageLog.sublist(messageLog.length - maxLogMessages);
      }

      // Update UI to show messages in messageLog
      setState(() {
        lastUpdated = DateTime.now().toLocal().toString().substring(0, 19);
        // Make sure you're actually displaying messageLog somewhere in your UI
      });

    } finally {
      // Always reset processing flag
      _isProcessingData = false;
    }
  }
  void _setupBleConnection() {
    // Monitor connection state
    _connectionSubscription = widget.flutterReactiveBle.connectToDevice(
      id: widget.deviceId,
    ).listen((connectionState) {
      print("Connection state: ${connectionState.connectionState}");

      // Only update UI if connection state actually changed
      final bool newConnectionState =
          connectionState.connectionState == DeviceConnectionState.connected;

      if (newConnectionState != isConnected) {
        setState(() {
          isConnected = newConnectionState;
        });

        if (!isConnected) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("❌ Disconnected from ESP32")),
          );
        }
      }
    });

    // Subscribe to notifications
    final characteristic = QualifiedCharacteristic(
      deviceId: widget.deviceId,
      serviceId: widget.serviceUuid,
      characteristicId: widget.characteristicUuid,
    );

    _dataSubscription = widget.flutterReactiveBle
        .subscribeToCharacteristic(characteristic)
        .listen((data) {
      final message = String.fromCharCodes(data);
      print("📥 Dashboard received: $message");

      // Don't process immediately, just buffer the message
      if (mounted && _messageBuffer.length < 100) { // Prevent buffer overflow
        _messageBuffer.add(message);
      }
    }, onError: (error) {
      print("Subscription error: $error");
    });
  }

  void processESP32Message(String message) {
    // Process Generator status
    if (message.contains("Generator: ON")) {
      setState(() {
        relayOn = false;
        loadSource = "Generator";
      });
    } else if (message.contains("Generator: OFF")) {
      setState(() {
        relayOn = true;
        loadSource = "Main";
      });
    }

    // Process Buzzer/LED status for system status
    if (message.contains("Buzzer: ON") || message.contains("LED: ON")) {
      setState(() {
        systemStatus = "Critical";
        integrityGrade = "Poor";
      });
    }

    // Process overload messages
    if (message.contains("Overload!")) {
      setState(() {
        systemStatus = "Critical";
        integrityGrade = "Poor";
        // Simulate voltage drop during overload
        voltage = 4.2;
      });
    }
  }

  void updateChartData() {
    if (!mounted) return;

    // Only update charts if enough time has passed
    final now = DateTime.now();
    if (now.difference(_lastChartUpdate).inMilliseconds < 1000) {
      return;
    }
    _lastChartUpdate = now;

    // Calculate new data outside setState
    double newVoltage = voltage;
    double newCurrent = current;

    // Only update these values if we haven't received specific data from ESP32
    if (systemStatus != "Critical") {
      newVoltage = (4.5 + (0.5 * (0.5 - (DateTime.now().second % 10) / 10)));
    }

    newCurrent = 0.6 + (0.05 * (DateTime.now().second % 5));
    double newPower = newVoltage * newCurrent;
    String newStatus = newVoltage < 4.3 ? "Critical" : (newVoltage < 4.6 ? "Warning" : "Normal");
    String newGrade = newVoltage < 4.3 ? "Poor" : (newVoltage < 4.6 ? "Moderate" : "Good");

    // Update chart data outside setState to avoid rebuilding
    voltageHistory.add(FlSpot(time.toDouble(), newVoltage));
    currentHistory.add(FlSpot(time.toDouble(), newCurrent));

    // Efficient batch trimming of history lists
    if (voltageHistory.length > maxDataPoints) {
      voltageHistory = voltageHistory.sublist(voltageHistory.length - maxDataPoints);
    }

    if (currentHistory.length > maxDataPoints) {
      currentHistory = currentHistory.sublist(currentHistory.length - maxDataPoints);
    }

    time++;

    // Now update the UI
    setState(() {
      voltage = newVoltage;
      current = newCurrent;
      power = newPower;
      systemStatus = newStatus;
      integrityGrade = newGrade;
    });
  }

  void toggleRelay() {
    setState(() {
      relayOn = !relayOn;
      loadSource = relayOn ? "Main" : "Generator";
    });
  }

  void toggleAutoMode(bool value) {
    setState(() {
      autoMode = value;
    });
  }

  // Method to return to connect screen safely
  void _backToConnectScreen() {
    // Cancel subscriptions to prevent data processing in background
    _dataSubscription?.cancel();
    _connectionSubscription?.cancel();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => ConnectScreen()),
    );
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _connectionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Smart Power Dashboard - Client',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.yellow,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black),
          onPressed: _backToConnectScreen, // Use custom back method
        ),
        actions: [
          // Connection status indicator
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: isConnected ? Colors.green : Colors.red,
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("System Status", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: systemStatus == "Normal"
                                ? Colors.green
                                : (systemStatus == "Warning" ? Colors.orange : Colors.red),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            systemStatus,
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 20),
                    dataRow("Voltage", "${voltage.toStringAsFixed(2)} V"),
                    dataRow("Current", "${current.toStringAsFixed(2)} A"),
                    dataRow("Power", "${power.toStringAsFixed(2)} W"),
                    dataRow("Load Source", loadSource),
                    dataRow("Integrity Grade", integrityGrade),
                    dataRow("Last Updated", lastUpdated),
                    dataRow("App Version", appVersion),
                  ],
                ),
              ),
            ),

            SizedBox(height: 20),

            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Controls", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Relay Switch", style: TextStyle(fontSize: 16)),
                        Switch(
                          value: relayOn,
                          onChanged: (_) => toggleRelay(),
                          activeColor: Colors.yellow,
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Auto Mode", style: TextStyle(fontSize: 16)),
                        Switch(
                          value: autoMode,
                          onChanged: toggleAutoMode,
                          activeColor: Colors.red,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 20),

            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Voltage Chart", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    SizedBox(height: 10),
                    Container(
                      height: 200,
                      child: voltageChart(),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 20),

            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Current Chart", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    SizedBox(height: 10),
                    Container(
                      height: 200,
                      child: currentChart(),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 20),

            // Message log from ESP32
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("ESP32 Data Log", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text("${messageLog.length} messages", style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                    SizedBox(height: 10),
                    Container(
                      height: 150,
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListView.builder(
                        // Use a more efficient approach for lists
                        itemCount: messageLog.length,
                        itemBuilder: (context, index) {
                          return Text(
                            messageLog[index],
                            style: TextStyle(
                              color: messageLog[index].contains("Overload")
                                  ? Colors.red
                                  : Colors.green,
                              fontFamily: 'monospace',
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget dataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 16)),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget voltageChart() {
    // Check if the data list is empty before rendering
    if (voltageHistory.isEmpty) {
      return Center(child: Text('No voltage data available'));
    }

    // Calculate chart range based on available data
    double minX = voltageHistory.isNotEmpty ? voltageHistory.first.x : 0;
    double maxX = voltageHistory.isNotEmpty ? voltageHistory.last.x : 20;

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: 4.0,
        maxY: 5.2,
        titlesData: FlTitlesData(
          show: true,
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
        ),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          LineChartBarData(
            spots: voltageHistory,
            isCurved: true,
            color: Colors.greenAccent,
            barWidth: 3,
            belowBarData: BarAreaData(
              show: true,
              color: Colors.greenAccent.withOpacity(0.3),
            ),
            dotData: FlDotData(show: false),
          ),
        ],
      ),
    );
  }
  Widget currentChart() {
    // Check if the data list is empty before rendering
    if (currentHistory.isEmpty) {
      return Center(child: Text('No current data available'));
    }

    // Calculate chart range based on available data
    double minX = currentHistory.isNotEmpty ? currentHistory.first.x : 0;
    double maxX = currentHistory.isNotEmpty ? currentHistory.last.x : 20;

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: 0.5,
        maxY: 1.2,
        titlesData: FlTitlesData(
          show: true,
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
        ),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          LineChartBarData(
            spots: currentHistory,
            isCurved: true,
            color: Colors.blueAccent,
            barWidth: 3,
            belowBarData: BarAreaData(
              show: true,
              color: Colors.blueAccent.withOpacity(0.3),
            ),
            dotData: FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}