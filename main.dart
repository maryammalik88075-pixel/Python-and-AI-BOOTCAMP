import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ble_manager.dart';
import 'storage_service.dart';
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const SmartInsoleApp());

class SmartInsoleApp extends StatelessWidget {
  const SmartInsoleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF0D47A1),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      ),
      home: const MainNavigationContainer(),
    );
  }
}

class MainNavigationContainer extends StatefulWidget {
  const MainNavigationContainer({super.key});

  @override
  State<MainNavigationContainer> createState() =>
      _MainNavigationContainerState();
}

class _MainNavigationContainerState extends State<MainNavigationContainer> {
  int _selectedIndex = 0;

  bool isLConnected = false;
  bool isRConnected = false;

  late BleManager bleManager;

  List<double> leftData = [0, 0, 0, 0, 0];
  List<double> rightData = [0, 0, 0, 0, 0];

  List<double> leftOffsets = [0, 0, 0, 0, 0];
  List<double> rightOffsets = [0, 0, 0, 0, 0];

  Timer? _streamWatchdog;
  DateTime? _lastLeftPacket;
  DateTime? _lastRightPacket;

  bool leftStreaming = false;
  bool rightStreaming = false;

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  @override
  void initState() {
    super.initState();
    bleManager = BleManager();
    _initBle();
  }

  @override
  void dispose() {
    _streamWatchdog?.cancel();
    bleManager.dispose();
    super.dispose();
  }

  Future<void> _showSnack(String message) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _initBle() async {
    await _requestPermissions();

    _streamWatchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      final now = DateTime.now();

      setState(() {
        leftStreaming = _lastLeftPacket != null &&
            now.difference(_lastLeftPacket!).inSeconds < 4;

        rightStreaming = _lastRightPacket != null &&
            now.difference(_lastRightPacket!).inSeconds < 4;
      });
    });

    await bleManager.startScan(
      (foot, data) {
        if (!mounted) return;

        setState(() {
          if (foot == "Left") {
            _lastLeftPacket = DateTime.now();
            leftData = List<double>.from(data);
          }

          if (foot == "Right") {
            _lastRightPacket = DateTime.now();
            rightData = List<double>.from(data);
          }
        });
      },
      (foot, status) {
        if (!mounted) return;

        setState(() {
          if (foot == "Left") isLConnected = status;
          if (foot == "Right") isRConnected = status;
        });
      },
    );
  }

  // ================= CALIBRATION ACTIONS =================

  Future<void> _handleCalibrateAllZero() async {
    await bleManager.calibrateAllZero();
    await _showSnack(
      "Global zero calibration sent. Keep both insoles unloaded for about 3 seconds.",
    );
  }

  Future<void> _handleCalibrateFootAllZero(String foot) async {
    await bleManager.calibrateFootAllZero(foot);
    await _showSnack(
      "$foot foot zero calibration sent. Keep that insole unloaded.",
    );
  }

  Future<void> _handleSensorZero(String foot, int sensorIndex) async {
    await bleManager.calibrateSensorZero(foot, sensorIndex);
    await _showSnack(
      "$foot S$sensorIndex zero calibration sent. Make sure no load is applied.",
    );
  }

  Future<void> _handleSensorSpan(
    String foot,
    int sensorIndex,
    double knownWeight,
  ) async {
    await bleManager.calibrateSensorSpan(foot, sensorIndex, knownWeight);
    await _showSnack(
      "$foot S$sensorIndex span calibration sent with known weight $knownWeight.",
    );
  }

  Future<void> _handleClearCalibrationAll() async {
    await bleManager.clearCalibrationAll();
    await _showSnack("Calibration cleared on both insoles.");
  }

  Future<void> _handleClearCalibrationFoot(String foot) async {
    await bleManager.clearCalibrationFoot(foot);
    await _showSnack("Calibration cleared on $foot insole.");
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      InsoleHomeScreen(
        isLConnected: isLConnected,
        isRConnected: isRConnected,
        leftData: leftData,
        rightData: rightData,
        leftOffsets: leftOffsets,
        rightOffsets: rightOffsets,
        onDataUpdate: (L, R) {},
      ),

      const HistoryPage(),

      CalibrationPage(
        isAnyConnected: isLConnected || isRConnected,
        isLConnected: isLConnected,
        isRConnected: isRConnected,
        leftStreaming: leftStreaming,
        rightStreaming: rightStreaming,
        leftData: leftData,
        rightData: rightData,
        onCalibrateAllZero: _handleCalibrateAllZero,
        onCalibrateFootAllZero: _handleCalibrateFootAllZero,
        onSensorZero: _handleSensorZero,
        onSensorSpan: _handleSensorSpan,
        onClearCalibrationAll: _handleClearCalibrationAll,
        onClearCalibrationFoot: _handleClearCalibrationFoot,
      ),

      SettingsPage(
        isLConnected: isLConnected,
        isRConnected: isRConnected,
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF0D47A1),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics_rounded),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.balance),
            label: 'Calibrate',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class InsoleHomeScreen extends StatefulWidget {
  final bool isLConnected, isRConnected;
  final List<double> leftData, rightData, leftOffsets, rightOffsets;
  final Function(List<double>, List<double>) onDataUpdate;

  const InsoleHomeScreen({
    super.key,
    required this.isLConnected,
    required this.isRConnected,
    required this.leftData,
    required this.rightData,
    required this.leftOffsets,
    required this.rightOffsets,
    required this.onDataUpdate,
  });

  @override
  State<InsoleHomeScreen> createState() => _InsoleHomeScreenState();
}

class _InsoleHomeScreenState extends State<InsoleHomeScreen> {
  // ================= HELPERS =================
  double calculateCopPathLength(List<Offset> points) {
    double distance = 0;

    for (int i = 1; i < points.length; i++) {
      final dx = points[i].dx - points[i - 1].dx;
      final dy = points[i].dy - points[i - 1].dy;
      distance += sqrt(dx * dx + dy * dy);
    }

    return distance;
  }

  double _mean(List<double> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  double _rms(List<double> values) {
    if (values.isEmpty) return 0.0;
    final mean = _mean(values);
    final sumSq = values.fold<double>(
      0.0,
      (sum, v) => sum + pow(v - mean, 2).toDouble(),
    );
    return sqrt(sumSq / values.length);
  }

  // ================= LIVE TOTALS =================
  double get leftTotal =>
      widget.leftData.fold(0.0, (a, b) => a + b);

  double get rightTotal =>
      widget.rightData.fold(0.0, (a, b) => a + b);

  double get totalLoad => leftTotal + rightTotal;

  double get balancePercent =>
      totalLoad > 0 ? (leftTotal / totalLoad) * 100 : 50.0;

  double get symmetryPercent =>
      totalLoad > 0 ? ((leftTotal - rightTotal).abs() / totalLoad) * 100 : 0.0;

  double get liveCopSwayX {
    if (copHistory.length < 2) return 0.0;
    final xs = copHistory.map((e) => e.dx).toList();
    return xs.reduce(max) - xs.reduce(min);
  }

  double get liveCopSwayY {
    if (copHistory.length < 2) return 0.0;
    final ys = copHistory.map((e) => e.dy).toList();
    return ys.reduce(max) - ys.reduce(min);
  }

  String get recordingStatusLabel {
    if (isRecording) return "Recording";
    if (recordingStopped) return "Stopped";
    return "Idle";
  }

  int get recordingDurationSec {
    if (recordStartTime == null) return 0;

    final endTime = isRecording
        ? DateTime.now()
        : (recordStopTime ?? DateTime.now());

    return endTime.difference(recordStartTime!).inSeconds;
  }

  // ================= CLINICAL WORKFLOW STATE =================
  final TextEditingController patientNameController = TextEditingController();
  final TextEditingController patientIdController = TextEditingController();
  final TextEditingController ageController = TextEditingController();

  String selectedSex = "Male";
  String selectedTestType = "Quiet Standing";

  bool patientLocked = false;
  bool isRecording = false;
  bool recordingStopped = false;

  Map<String, dynamic>? currentPatient;
  Map<String, dynamic>? calculatedMetrics;

  DateTime sessionStart = DateTime.now();
  DateTime? recordStartTime;
  DateTime? recordStopTime;

  // ================= CORE SESSION VARIABLES =================
  int stepCount = 0;
  double baselinePressure = 0;
  bool stepDetected = false;

  DateTime? contactStartTime;
  DateTime startTime = DateTime.now();

  double stanceTime = 0;
  int graphIndex = 0;

  double copX = 0;
  double copY = 0;
  double prevCopX = 0;
  double prevCopY = 0;

  double stepLength = 0;
  double cadence = 0;
  double speedMps = 0;
  double speed = 0;

  String gait = "Standing";

  // ================= STEP / CONTACT STATE =================
  bool _leftInContact = false;
  bool _rightInContact = false;
  DateTime? _lastStepEventTime;

  static const Duration _stepRefractory =
      Duration(milliseconds: 300);

  static const double _footContactThreshold = 12.0;
  static const double _heelEventThreshold = 8.0;
  static const double _copMinForceThreshold = 5.0;

  // ================= SENSOR GEOMETRY =================
  // NOTE:
  // These are still symbolic normalized coordinates for prototype use.
  // For true clinical AP/ML values, later replace them with measured mm coordinates.
List<Offset> leftSensorPos = [
    const Offset(-0.25, -0.90), // Index 0: Heel
    const Offset(-0.25, -0.05), // Index 1: Midfoot
    const Offset(-0.05, 0.95),  // Index 2: Hallux/Toe
    const Offset(-0.42, 0.35),  // Index 3: Lateral Forefoot
    const Offset(-0.12, 0.35),  // Index 4: Medial Forefoot
];

List<Offset> rightSensorPos = [
    const Offset(0.25, -0.90),  // Index 0: Heel
    const Offset(0.25, -0.05),  // Index 1: Midfoot
    const Offset(0.05, 0.95),   // Index 2: Hallux/Toe
    const Offset(0.42, 0.35),   // Index 3: Lateral Forefoot
    const Offset(0.12, 0.35),   // Index 4: Medial Forefoot
];

  List<double> peakL = [0, 0, 0, 0, 0];

  // ================= LIVE DISPLAY BUFFERS =================
  List<List<double>> leftHistory = List.generate(5, (_) => []);
  List<List<double>> rightHistory = List.generate(5, (_) => []);
  List<Offset> copHistory = [];

  // ================= RECORDED SESSION BUFFERS =================
  List<Map<String, dynamic>> sessionBuffer = [];
  List<Map<String, dynamic>> recordedSamples = [];
  List<Offset> recordedCopHistory = [];

  late Timer _historyTimer;

  // ================= WORKFLOW METHODS =================
  void lockPatient() {
    final name = patientNameController.text.trim();
    final id = patientIdController.text.trim();
    final age = ageController.text.trim();

    if (name.isEmpty || id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Enter at least patient name and ID"),
        ),
      );
      return;
    }

    setState(() {
      currentPatient = {
        "name": name,
        "id": id,
        "age": age,
        "sex": selectedSex,
        "testType": selectedTestType,
      };
      patientLocked = true;
    });
  }

  void unlockPatient() {
    if (isRecording) return;

    setState(() {
      patientLocked = false;
      currentPatient = null;
    });
  }

  void startRecording() {
    if (!patientLocked || currentPatient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Lock patient details first"),
        ),
      );
      return;
    }

    if (!widget.isLConnected && !widget.isRConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No insole connected"),
        ),
      );
      return;
    }

    setState(() {
      isRecording = true;
      recordingStopped = false;
      calculatedMetrics = null;

      stepCount = 0;
      baselinePressure = 0;
      stepDetected = false;

      stanceTime = 0;
      graphIndex = 0;

      copX = 0;
      copY = 0;
      prevCopX = 0;
      prevCopY = 0;

      stepLength = 0;
      cadence = 0;
      speedMps = 0;
      speed = 0;

      gait = "Standing";
      contactStartTime = null;
      _leftInContact = false;
      _rightInContact = false;
      _lastStepEventTime = null;

      sessionStart = DateTime.now();
      startTime = sessionStart;
      recordStartTime = sessionStart;
      recordStopTime = null;

      sessionBuffer.clear();
      recordedSamples.clear();
      recordedCopHistory.clear();

      copHistory.clear();
      leftHistory = List.generate(5, (_) => []);
      rightHistory = List.generate(5, (_) => []);
    });
  }

  void stopRecording() {
    if (!isRecording) return;

    setState(() {
      isRecording = false;
      recordingStopped = true;
      recordStopTime = DateTime.now();
    });
  }

  void resetClinicalSession() {
    if (isRecording) return;

    setState(() {
      isRecording = false;
      recordingStopped = false;
      calculatedMetrics = null;

      stepCount = 0;
      baselinePressure = 0;
      stepDetected = false;

      stanceTime = 0;
      graphIndex = 0;

      copX = 0;
      copY = 0;
      prevCopX = 0;
      prevCopY = 0;

      stepLength = 0;
      cadence = 0;
      speedMps = 0;
      speed = 0;

      gait = "Standing";
      contactStartTime = null;
      _leftInContact = false;
      _rightInContact = false;
      _lastStepEventTime = null;

      sessionStart = DateTime.now();
      startTime = sessionStart;
      recordStartTime = null;
      recordStopTime = null;

      sessionBuffer.clear();
      recordedSamples.clear();
      recordedCopHistory.clear();

      copHistory.clear();
      leftHistory = List.generate(5, (_) => []);
      rightHistory = List.generate(5, (_) => []);
    });
  }

  void calculateClinicalMetrics() {
    if (recordedSamples.isEmpty || recordedCopHistory.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No recorded session to calculate"),
        ),
      );
      return;
    }

    final String testType =
        (currentPatient?["testType"] ?? selectedTestType).toString();

    final durationSec =
        recordingDurationSec > 0 ? recordingDurationSec.toDouble() : 0.1;

    final xs = recordedCopHistory.map((e) => e.dx).toList();
    final ys = recordedCopHistory.map((e) => e.dy).toList();

    final mlRange = xs.reduce(max) - xs.reduce(min);
    final apRange = ys.reduce(max) - ys.reduce(min);

    final copPath = calculateCopPathLength(recordedCopHistory);
    final meanVelocity = durationSec > 0 ? copPath / durationSec : 0.0;

    final mlRms = _rms(xs);
    final apRms = _rms(ys);

    final leftTotals = recordedSamples.map<double>((sample) {
      final left = (sample["leftData"] as List).cast<double>();
      return left.fold(0.0, (a, b) => a + b);
    }).toList();

    final rightTotals = recordedSamples.map<double>((sample) {
      final right = (sample["rightData"] as List).cast<double>();
      return right.fold(0.0, (a, b) => a + b);
    }).toList();

    final meanLeft = _mean(leftTotals);
    final meanRight = _mean(rightTotals);
    final meanTotal = meanLeft + meanRight;

    final balance = meanTotal > 0 ? (meanLeft / meanTotal) * 100 : 50.0;
    final symmetry =
        meanTotal > 0 ? ((meanLeft - meanRight).abs() / meanTotal) * 100 : 0.0;

    setState(() {
      calculatedMetrics = {
        "patientName": currentPatient?["name"],
        "patientId": currentPatient?["id"],
        "age": currentPatient?["age"],
        "sex": currentPatient?["sex"],
        "testType": testType,
        "durationSec": durationSec,

        // Common
        "meanLeftTotal": meanLeft,
        "meanRightTotal": meanRight,
        "balance": balance,
        "symmetry": symmetry,
        "copPath": copPath,
        "mlRange": mlRange,
        "apRange": apRange,
        "meanVelocity": meanVelocity,
        "mlRms": mlRms,
        "apRms": apRms,
        "samples": recordedSamples.length,

        // Gait-related
        "steps": stepCount,
        "cadence": cadence,
        "speed": speed,
      };
    });
  }

  @override
  void initState() {
    super.initState();

    _historyTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (timer) {
        if (!mounted) return;

        final now = DateTime.now();

        // ================= RIGHT FOOT =================
        final double rHeel = widget.rightData[0];
        final double rMid = widget.rightData[1];
        final double rToe = widget.rightData[2];
        final double rightTotal =
            widget.rightData.fold(0.0, (a, b) => a + b);

        // ================= LEFT FOOT =================
        final double lHeel = widget.leftData[0];
        final double lMid = widget.leftData[1];
        final double lToe = widget.leftData[2];
        final double leftTotal =
            widget.leftData.fold(0.0, (a, b) => a + b);

        // ================= CONTACT STATES =================
        final bool leftContactNow = leftTotal > _footContactThreshold;
        final bool rightContactNow = rightTotal > _footContactThreshold;

        final double totalPressure = leftTotal + rightTotal;

        // ================= GAIT LABEL =================
        if (!leftContactNow && !rightContactNow) {
          gait = "No Contact";
        } else if (leftContactNow && rightContactNow) {
          gait = "Double Support";
        } else if (leftContactNow) {
          if (lHeel > lMid && lHeel > lToe && lHeel > _heelEventThreshold) {
            gait = "Left Heel Strike";
          } else if (lToe > lHeel && lToe > lMid && lToe > _heelEventThreshold) {
            gait = "Left Toe Off";
          } else {
            gait = "Left Stance";
          }
        } else if (rightContactNow) {
          if (rHeel > rMid && rHeel > rToe && rHeel > _heelEventThreshold) {
            gait = "Right Heel Strike";
          } else if (rToe > rHeel && rToe > rMid && rToe > _heelEventThreshold) {
            gait = "Right Toe Off";
          } else {
            gait = "Right Stance";
          }
        }

        // ================= STEP COUNT =================
        if (isRecording) {
          final bool leftHeelStrike =
              !_leftInContact &&
              leftContactNow &&
              lHeel > lMid &&
              lHeel > lToe &&
              lHeel > _heelEventThreshold;

          final bool rightHeelStrike =
              !_rightInContact &&
              rightContactNow &&
              rHeel > rMid &&
              rHeel > rToe &&
              rHeel > _heelEventThreshold;

          final bool canRegisterStep =
              _lastStepEventTime == null ||
              now.difference(_lastStepEventTime!) > _stepRefractory;

          if (canRegisterStep && (leftHeelStrike || rightHeelStrike)) {
            stepCount++;
            _lastStepEventTime = now;
          }

          final double minutes =
              DateTime.now().difference(startTime).inSeconds / 60.0;

          cadence = minutes > 0 ? stepCount / minutes : 0.0;

          // estimated speed only
          speedMps = cadence * 0.7 / 60.0;
          speed = speedMps;
        }

        _leftInContact = leftContactNow;
        _rightInContact = rightContactNow;

        // ================= LIVE COP =================
        Offset weighted = const Offset(0, 0);
        double totalForce = 0;

        for (int i = 0; i < 5; i++) {
          final double lf = widget.leftData[i];
          final double rf = widget.rightData[i];

          totalForce += lf + rf;
          weighted += leftSensorPos[i] * lf;
          weighted += rightSensorPos[i] * rf;
        }

        if (totalForce > _copMinForceThreshold) {
          final Offset rawCOP = Offset(
            weighted.dx / totalForce,
            weighted.dy / totalForce,
          );

          copX = copX * 0.8 + rawCOP.dx * 0.2;
          copY = copY * 0.8 + rawCOP.dy * 0.2;

          copHistory.add(Offset(copX, copY));
          if (copHistory.length > 150) {
            copHistory.removeAt(0);
          }

          // ================= RECORD ONLY DURING SESSION =================
          if (isRecording) {
            final tempHistory = [...recordedCopHistory, Offset(copX, copY)];
            final currentCopPath = calculateCopPathLength(tempHistory);

            final xs = tempHistory.map((e) => e.dx).toList();
            final ys = tempHistory.map((e) => e.dy).toList();

            final double copSwayX =
                xs.length > 1 ? xs.reduce(max) - xs.reduce(min) : 0.0;
            final double copSwayY =
                ys.length > 1 ? ys.reduce(max) - ys.reduce(min) : 0.0;

            final sample = {
              "time": DateTime.now().toIso8601String(),
              "leftData": List<double>.from(widget.leftData),
              "rightData": List<double>.from(widget.rightData),
              "leftTotal": leftTotal,
              "rightTotal": rightTotal,
              "totalPressure": totalPressure,
              "copX": copX,
              "copY": copY,
              "copPath": currentCopPath,
              "copSwayX": copSwayX,
              "copSwayY": copSwayY,
              "steps": stepCount,
              "speed": speed,
              "cadence": cadence,
              "gait": gait,
            };

            sessionBuffer.add(sample);
            recordedSamples.add(sample);
            recordedCopHistory.add(Offset(copX, copY));
          }
        }

        // ================= LIVE GRAPH =================
        for (int i = 0; i < 5; i++) {
          leftHistory[i].add(
            widget.leftData[i].clamp(0.0, 100.0).toDouble(),
          );
          if (leftHistory[i].length > 80) {
            leftHistory[i].removeAt(0);
          }

          rightHistory[i].add(
            widget.rightData[i].clamp(0.0, 100.0).toDouble(),
          );
          if (rightHistory[i].length > 80) {
            rightHistory[i].removeAt(0);
          }
        }

        setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _historyTimer.cancel();
    patientNameController.dispose();
    patientIdController.dispose();
    ageController.dispose();
    super.dispose();
  }

  // ================= UI =================

 String _numText(dynamic value, [int decimals = 2]) {
  final double v = value is num ? value.toDouble() : 0.0;
  return v.toStringAsFixed(decimals);
}

@override
Widget build(BuildContext context) {
  return DefaultTabController(
    length: 4,
    child: Scaffold(
      appBar: AppBar(
        title: const Text("Smart Insole Clinical"),
        bottom: const TabBar(
          isScrollable: true,
          tabs: [
            Tab(text: "Patient"),
            Tab(text: "Record"),
            Tab(text: "COP Review"),
            Tab(text: "Clinical Metrics"),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          _buildPatientTab(),
          _buildRecordTab(),
          _buildCopReviewTab(),
          _buildClinicalMetricsTab(),
        ],
      ),
    ),
  );
}

// ================= TAB 1: PATIENT =================
Widget _buildPatientTab() {
  return SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Patient Details",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildClinicalTextField("Patient Name", patientNameController),
              const SizedBox(height: 12),
              _buildClinicalTextField("Patient ID / MR No.", patientIdController),
              const SizedBox(height: 12),
              _buildClinicalTextField("Age", ageController, isNumber: true),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedSex,
                items: const [
                  DropdownMenuItem(value: "Male", child: Text("Male")),
                  DropdownMenuItem(value: "Female", child: Text("Female")),
                ],
                onChanged: patientLocked
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => selectedSex = value);
                        }
                      },
                decoration: InputDecoration(
                  labelText: "Sex",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  filled: true,
                  fillColor: patientLocked ? Colors.grey.shade100 : Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedTestType,
                items: const [
                  DropdownMenuItem(
                    value: "Quiet Standing",
                    child: Text("Quiet Standing"),
                  ),
                  DropdownMenuItem(
                    value: "Gait",
                    child: Text("Gait"),
                  ),
                ],
                onChanged: patientLocked
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => selectedTestType = value);
                        }
                      },
                decoration: InputDecoration(
                  labelText: "Test Type",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  filled: true,
                  fillColor: patientLocked ? Colors.grey.shade100 : Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: patientLocked ? null : lockPatient,
                      icon: const Icon(Icons.lock_outline),
                      label: const Text("Lock Patient"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: patientLocked ? unlockPatient : null,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text("Edit Patient"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (currentPatient != null) _buildPatientSummaryCard(),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Text(
            "Workflow:\n"
            "1. Enter patient details\n"
            "2. Lock patient\n"
            "3. Go to Record tab and start recording\n"
            "4. Stop recording\n"
            "5. Review recorded COP in COP Review tab\n"
            "6. Press Calculate in Clinical Metrics tab\n"
            "7. Save session",
          ),
        ),
      ],
    ),
  );
}

Widget _buildClinicalTextField(
  String label,
  TextEditingController controller, {
  bool isNumber = false,
}) {
  return TextField(
    controller: controller,
    readOnly: patientLocked,
    keyboardType: isNumber ? TextInputType.number : TextInputType.text,
    decoration: InputDecoration(
      labelText: label,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      filled: true,
      fillColor: patientLocked ? Colors.grey.shade100 : Colors.white,
    ),
  );
}

Widget _buildPatientSummaryCard() {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Active Subject",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        _summaryRow("Name", currentPatient?["name"]?.toString() ?? "-"),
        _summaryRow("ID", currentPatient?["id"]?.toString() ?? "-"),
        _summaryRow("Age", currentPatient?["age"]?.toString() ?? "-"),
        _summaryRow("Sex", currentPatient?["sex"]?.toString() ?? "-"),
        _summaryRow("Test Type", currentPatient?["testType"]?.toString() ?? "-"),
      ],
    ),
  );
}

Widget _summaryRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.grey),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

// ================= TAB 2: RECORD =================
Widget _buildRecordTab() {
  return SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (currentPatient != null) ...[
          _buildPatientSummaryCard(),
          const SizedBox(height: 16),
        ] else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              "No patient locked yet. Go to Patient tab first.",
            ),
          ),
        const SizedBox(height: 16),
        _buildConnectionStatusCard(),
        const SizedBox(height: 16),
        _buildRecordingControlCard(),
        const SizedBox(height: 16),
        const Text(
          "Live Sensor Values",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _buildSensorValuesSection(),
        const SizedBox(height: 16),
        _buildPressureCard(),
        const SizedBox(height: 16),
        const Text(
          "Live COP",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _buildCopSection(),
        const SizedBox(height: 16),
        const Text(
          "Live Balance",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _buildComparisonPanel(),
        const SizedBox(height: 16),
        const Text(
          "Live Sensor Graphs",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _buildLiveGraphSection(),
        const SizedBox(height: 16),
        _buildFeatureSummaryCard(),
        const SizedBox(height: 16),
        _buildAlertSection(),
      ],
    ),
  );
}

Widget _buildConnectionStatusCard() {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Connection Status",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        _connectionRow("Left Insole", widget.isLConnected),
        const SizedBox(height: 8),
        _connectionRow("Right Insole", widget.isRConnected),
      ],
    ),
  );
}

Widget _connectionRow(String label, bool connected) {
  return Row(
    children: [
      Icon(
        connected ? Icons.check_circle : Icons.cancel,
        color: connected ? Colors.green : Colors.red,
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(label)),
      Text(
        connected ? "Connected" : "Disconnected",
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: connected ? Colors.green : Colors.red,
        ),
      ),
    ],
  );
}

Widget _buildRecordingControlCard() {
  final bool canStart =
      patientLocked && (widget.isLConnected || widget.isRConnected) && !isRecording;
  final bool canStop = isRecording;
  final bool canReset = !isRecording;

  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Recording Control",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: canStart ? startRecording : null,
                icon: const Icon(Icons.fiber_manual_record),
                label: const Text("Start"),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: canStop ? stopRecording : null,
                icon: const Icon(Icons.stop),
                label: const Text("Stop"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: canReset ? resetClinicalSession : null,
                icon: const Icon(Icons.refresh),
                label: const Text("Reset"),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _summaryRow("Status", recordingStatusLabel),
        _summaryRow("Elapsed Time", "${recordingDurationSec}s"),
        _summaryRow("Recorded Samples", "${recordedSamples.length}"),
      ],
    ),
  );
}

Widget _buildSensorValuesSection() {
  return Row(
    children: [
      Expanded(
        child: _sensorValueCard(
          title: "Left Foot",
          values: widget.leftData,
          connected: widget.isLConnected,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _sensorValueCard(
          title: "Right Foot",
          values: widget.rightData,
          connected: widget.isRConnected,
        ),
      ),
    ],
  );
}

Widget _sensorValueCard({
  required String title,
  required List<double> values,
  required bool connected,
}) {
  final sensorMap = [
    {"name": "S1", "index": 0}, // FSR1
    {"name": "S2", "index": 4}, // FSR2
    {"name": "S3", "index": 3}, // FSR3
    {"name": "S4", "index": 2}, // FSR4
    {"name": "S5", "index": 1}, // FSR5
  ];

  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),

        for (final sensor in sensorMap)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(sensor["name"] as String),
                Text(
                  connected
                      ? values[sensor["index"] as int].toStringAsFixed(1)
                      : "--",
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

Widget _buildFeatureSummaryCard() {
  return Column(
    children: [
      Row(
        children: [
          _featureBox("Steps", "$stepCount"),
          _featureBox("Cadence", cadence.toStringAsFixed(1)),
          _featureBox("Speed*", speed.toStringAsFixed(2)),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          _featureBox("Left Total", leftTotal.toStringAsFixed(1)),
          _featureBox("Right Total", rightTotal.toStringAsFixed(1)),
          _featureBox("Balance %", balancePercent.toStringAsFixed(1)),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          _featureBox("Symmetry %", symmetryPercent.toStringAsFixed(1)),
          _featureBox("Gait", gait),
          _featureBox("Live COP Path", calculateCopPathLength(copHistory).toStringAsFixed(2)),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          _featureBox("ML Sway", liveCopSwayX.toStringAsFixed(2)),
          _featureBox("AP Sway", liveCopSwayY.toStringAsFixed(2)),
          _featureBox("Duration", "${recordingDurationSec}s"),
        ],
      ),
      const SizedBox(height: 10),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          "* Speed is currently estimated from cadence and assumed step length.",
          style: TextStyle(fontSize: 12),
        ),
      ),
    ],
  );
}

Widget _featureBox(String title, String value) {
  return Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    ),
  );
}

// ================= TAB 3: COP REVIEW =================
Widget _buildCopReviewTab() {
  return SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (currentPatient != null) ...[
          _buildPatientSummaryCard(),
          const SizedBox(height: 16),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Recorded COP Trajectory",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "AP/ML review of the recorded session.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 280,
                child: CustomPaint(
                  painter: CopPainter(recordedCopHistory),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildRecordedCopSummaryCard(),
      ],
    ),
  );
}

Widget _buildRecordedCopSummaryCard() {
  final double mlSway = recordedCopHistory.length < 2
      ? 0.0
      : recordedCopHistory.map((e) => e.dx).reduce(max) -
          recordedCopHistory.map((e) => e.dx).reduce(min);

  final double apSway = recordedCopHistory.length < 2
      ? 0.0
      : recordedCopHistory.map((e) => e.dy).reduce(max) -
          recordedCopHistory.map((e) => e.dy).reduce(min);

  final double copPath = calculateCopPathLength(recordedCopHistory);

  return Column(
    children: [
      Row(
        children: [
          _featureBox("Recorded Points", "${recordedCopHistory.length}"),
          _featureBox("ML Sway", mlSway.toStringAsFixed(2)),
          _featureBox("AP Sway", apSway.toStringAsFixed(2)),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          _featureBox("COP Path", copPath.toStringAsFixed(2)),
          _featureBox("Duration", "${recordingDurationSec}s"),
          _featureBox("Status", recordingStatusLabel),
        ],
      ),
    ],
  );
}

// ================= TAB 4: CLINICAL METRICS =================
Widget _buildClinicalMetricsTab() {
  return SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (currentPatient != null) ...[
          _buildPatientSummaryCard(),
          const SizedBox(height: 16),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Clinical Analysis",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: recordingStopped ? calculateClinicalMetrics : null,
                      icon: const Icon(Icons.calculate_outlined),
                      label: const Text("Calculate"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (recordingStopped && calculatedMetrics != null)
                          ? saveSession
                          : null,
                      icon: const Icon(Icons.save_alt),
                      label: const Text("Save Session"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                recordingStopped
                    ? "Recording stopped. You can calculate clinical parameters."
                    : "Stop recording first to calculate clinical parameters.",
                style: TextStyle(
                  color: recordingStopped ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (calculatedMetrics == null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              "No calculated metrics yet. Record a session, stop it, then press Calculate.",
            ),
          )
        else
          _buildCalculatedMetricsCard(),
      ],
    ),
  );
}

Widget _buildCalculatedMetricsCard() {
  return Column(
    children: [
      Row(
        children: [
          _featureBox(
            "Duration",
            "${_numText(calculatedMetrics?["durationSec"], 1)} s",
          ),
          _featureBox(
            "Steps",
            "${calculatedMetrics?["steps"] ?? 0}",
          ),
          _featureBox(
            "Cadence",
            _numText(calculatedMetrics?["cadence"], 1),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          _featureBox(
            "Speed",
            _numText(calculatedMetrics?["speed"], 2),
          ),
          _featureBox(
            "Mean Left",
            _numText(calculatedMetrics?["meanLeftTotal"], 2),
          ),
          _featureBox(
            "Mean Right",
            _numText(calculatedMetrics?["meanRightTotal"], 2),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          _featureBox(
            "Balance %",
            _numText(calculatedMetrics?["balance"], 2),
          ),
          _featureBox(
            "Symmetry %",
            _numText(calculatedMetrics?["symmetry"], 2),
          ),
          _featureBox(
            "COP Path",
            _numText(calculatedMetrics?["copPath"], 2),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          _featureBox(
            "ML Sway",
            _numText(calculatedMetrics?["mlRange"], 2),
          ),
          _featureBox(
            "AP Sway",
            _numText(calculatedMetrics?["apRange"], 2),
          ),
          _featureBox(
            "Mean Velocity",
            _numText(calculatedMetrics?["meanVelocity"], 2),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          _featureBox(
            "ML RMS",
            _numText(calculatedMetrics?["mlRms"], 2),
          ),
          _featureBox(
            "AP RMS",
            _numText(calculatedMetrics?["apRms"], 2),
          ),
          _featureBox(
            "Samples",
            "${calculatedMetrics?["samples"] ?? 0}",
          ),
        ],
      ),
    ],
  );
}

// ================= COMMON VISUALS =================
Widget _buildPressureCard() {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Pressure Map",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildFootColumn(
                true,
                widget.leftData,
                widget.leftOffsets,
                widget.isLConnected,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildFootColumn(
                false,
                widget.rightData,
                widget.rightOffsets,
                widget.isRConnected,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

Widget _buildCopSection() {
  return Container(
    width: double.infinity,
    height: 240,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey.shade300, width: 1),
      boxShadow: const [
        BoxShadow(
          color: Colors.black12,
          blurRadius: 6,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CustomPaint(
              painter: CopPainter(copHistory),
            ),
          ),
        ),
        const Positioned(
          top: 8,
          left: 10,
          child: Text(
            "Live COP Trajectory",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
        ),
        Positioned(
          bottom: 6,
          left: 8,
          child: Text(
            "Points: ${copHistory.length}",
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
            ),
          ),
        ),
        const Positioned(
          bottom: 6,
          right: 8,
          child: Text(
            "Live",
            style: TextStyle(
              fontSize: 12,
              color: Colors.black54,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _buildFootColumn(
  bool isLeft,
  List<double> data,
  List<double> offsets,
  bool connected,
) {
  final String asset = isLeft ? "foot_left.svg" : "foot_right.svg";

  final List<List<dynamic>> sensorConfigs = isLeft
      ? [
          [0.80, 0.45, "1", 0],
          [0.30, 0.70, "2", 4],
          [0.32, 0.32, "3", 3],
          [0.16, 0.66, "4", 2],
          [0.52, 0.45, "5", 1],
        ]
      : [
          [0.80, 0.55, "1", 0],
          [0.30, 0.30, "2", 4],
          [0.32, 0.68, "3", 3],
          [0.16, 0.34, "4", 2],
          [0.52, 0.55, "5", 1],
        ];

  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(isLeft ? "Left Foot" : "Right Foot"),
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 150,
          child: AspectRatio(
            aspectRatio: 150 / 320,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: Center(
                    child: SvgPicture.asset(
                      "assets/svg/$asset",
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                ...sensorConfigs.map(
                  (config) => _sensor(
                    config[0],
                    config[1],
                    data[config[3]],
                    connected,
                    config[2],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

Widget _sensor(
  double top,
  double left,
  double val,
  bool connected,
  String id,
) {
  val = val < 8 ? 0 : val;

  Color color;
  if (!connected) {
    color = Colors.grey.shade400;
  } else if (val < 15) {
    color = Colors.green;
  } else if (val < 35) {
    color = Colors.lightGreen;
  } else if (val < 60) {
    color = Colors.yellow;
  } else if (val < 85) {
    color = Colors.orange;
  } else {
    color = Colors.red;
  }

  return Align(
    alignment: FractionalOffset(left, top),
    child: Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Center(
        child: Text(
          id,
          style: const TextStyle(fontSize: 11),
        ),
      ),
    ),
  );
}

Widget _buildLiveGraphSection() {
  return Column(
    children: [
      _singleGraph("Left Foot", leftHistory, widget.isLConnected),
      const SizedBox(height: 16),
      _singleGraph("Right Foot", rightHistory, widget.isRConnected),
    ],
  );
}

Widget _singleGraph(String title, List<List<double>> data, bool connected) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 180,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: SingleFootChartPainter(data, connected),
            ),
          ),
        ),
      ],
    ),
  );
}

Future<void> generateReport() async {

  final pdf = pw.Document();

  pdf.addPage(
    pw.MultiPage(
      build: (context) => [

        pw.Header(
          level: 0,
          child: pw.Text(
            'SMART INSOLE CLINICAL REPORT',
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),

        pw.SizedBox(height: 20),

        pw.Text(
          'Patient Information',
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 16,
          ),
        ),

        pw.Divider(),

        pw.Text(
            'Patient Name: ${currentPatient?["name"] ?? "-"}'),

        pw.Text(
            'Patient ID: ${currentPatient?["id"] ?? "-"}'),

        pw.Text(
            'Age: ${currentPatient?["age"] ?? "-"}'),

        pw.Text(
            'Sex: ${currentPatient?["sex"] ?? "-"}'),

        pw.Text(
            'Test Type: ${currentPatient?["testType"] ?? "-"}'),

        pw.SizedBox(height: 20),

        pw.Text(
          'Clinical Metrics',
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 16,
          ),
        ),

        pw.Divider(),

        pw.Text(
            'Recording Duration: ${recordingDurationSec}s'),

        pw.Text(
            'Steps: $stepCount'),

        pw.Text(
            'Cadence: ${cadence.toStringAsFixed(1)} steps/min'),

        pw.Text(
            'Speed: ${speed.toStringAsFixed(2)} m/s'),

        pw.Text(
            'Balance: ${balancePercent.toStringAsFixed(1)} %'),

        pw.Text(
            'Symmetry: ${symmetryPercent.toStringAsFixed(1)} %'),

        pw.Text(
            'COP Path Length: ${calculateCopPathLength(copHistory).toStringAsFixed(2)}'),

        pw.Text(
            'ML Sway: ${liveCopSwayX.toStringAsFixed(2)}'),

        pw.Text(
            'AP Sway: ${liveCopSwayY.toStringAsFixed(2)}'),

        pw.SizedBox(height: 20),

        pw.Text(
          'Generated On: ${DateTime.now()}',
        ),
      ],
    ),
  );

  final downloadsDir =
    Directory('/storage/emulated/0/Download');

if (!await downloadsDir.exists()) {
  await downloadsDir.create(recursive: true);
}

final file = File(
  '${downloadsDir.path}/SmartInsole_Report_${DateTime.now().millisecondsSinceEpoch}.pdf',
);

await file.writeAsBytes(
  await pdf.save(),
);

print("PDF SAVED AT: ${file.path}");

if (!mounted) return;

ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text(
      "PDF saved in Downloads folder",
    ),
  ),
);
}

Widget _buildComparisonPanel() {
  final double leftPercent = totalLoad > 0 ? (leftTotal / totalLoad) : 0.5;
  final int leftFlex = max(1, (leftPercent * 100).round());
  final int rightFlex = max(1, ((1 - leftPercent) * 100).round());

  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Column(
      children: [
        const Text("Left vs Right Balance"),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              flex: leftFlex,
              child: Container(height: 20, color: Colors.blue),
            ),
            Expanded(
              flex: rightFlex,
              child: Container(height: 20, color: Colors.red),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          "Left: ${(leftPercent * 100).toStringAsFixed(1)}% | "
          "Right: ${((1 - leftPercent) * 100).toStringAsFixed(1)}%",
        ),
      ],
    ),
  );
}

Widget _buildAlertSection() {
  final bool high =
      (widget.isLConnected && widget.leftData.any((v) => v > 80)) ||
      (widget.isRConnected && widget.rightData.any((v) => v > 80));

  String alert = "Normal";
  if (symmetryPercent > 20) {
    alert = "⚠️ Poor Balance";
  } else if (high) {
    alert = "⚠️ High Pressure";
  }

  String activity = "Walking";
  if (speed > 2.5) {
    activity = "Running";
  }

  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: high ? Colors.orange.shade50 : Colors.green.shade50,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(
        color: high ? Colors.orange.shade200 : Colors.green.shade200,
      ),
    ),
    child: Column(
      children: [
        Text(
          "$alert\n"
          "Activity: $activity\n"
          "Gait: $gait\n"
          "Balance: ${balancePercent.toStringAsFixed(1)}% Left\n"
          "Symmetry: ${symmetryPercent.toStringAsFixed(1)}%\n"
          "Steps: $stepCount\n"
          "Cadence: ${cadence.toStringAsFixed(1)} steps/min",
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: () async {
  await generateReport();
},
          child: const Text("Generate Report"),
        ),
      ],
    ),
  );
}

Future<void> saveSession() async {
  if (!recordingStopped || calculatedMetrics == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Stop recording and calculate metrics first"),
      ),
    );
    return;
  }

  if (currentPatient == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("No patient information available"),
      ),
    );
    return;
  }

  final session = {
    "timestamp": DateTime.now().toIso8601String(),
    "patientName": currentPatient?["name"],
    "patientId": currentPatient?["id"],
    "age": currentPatient?["age"],
    "sex": currentPatient?["sex"],
    "testType": currentPatient?["testType"],
    "duration": calculatedMetrics?["durationSec"] ?? recordingDurationSec,
    "steps": calculatedMetrics?["steps"] ?? stepCount,
    "speed": calculatedMetrics?["speed"] ?? speed,
    "cadence": calculatedMetrics?["cadence"] ?? cadence,
    "copPathLength": calculatedMetrics?["copPath"] ?? 0.0,
    "copSwayX": calculatedMetrics?["mlRange"] ?? 0.0,
    "copSwayY": calculatedMetrics?["apRange"] ?? 0.0,
    "balance": calculatedMetrics?["balance"] ?? balancePercent,
    "symmetry": calculatedMetrics?["symmetry"] ?? symmetryPercent,
    "meanVelocity": calculatedMetrics?["meanVelocity"] ?? 0.0,
    "mlRms": calculatedMetrics?["mlRms"] ?? 0.0,
    "apRms": calculatedMetrics?["apRms"] ?? 0.0,
    "samples": calculatedMetrics?["samples"] ?? recordedSamples.length,
  };

  await StorageService.saveSession(session);

  setState(() {
    isRecording = false;
    recordingStopped = false;
    calculatedMetrics = null;

    stepCount = 0;
    baselinePressure = 0;
    stepDetected = false;

    stanceTime = 0;
    graphIndex = 0;

    copX = 0;
    copY = 0;
    prevCopX = 0;
    prevCopY = 0;

    stepLength = 0;
    cadence = 0;
    speedMps = 0;
    speed = 0;

    gait = "Standing";
    contactStartTime = null;

    sessionStart = DateTime.now();
    startTime = sessionStart;
    recordStartTime = null;
    recordStopTime = null;

    sessionBuffer.clear();
    recordedSamples.clear();
    recordedCopHistory.clear();
    copHistory.clear();
    leftHistory = List.generate(5, (_) => []);
    rightHistory = List.generate(5, (_) => []);
  });

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text("Clinical session saved successfully")),
  );
}}

// ================= GRAPH =================

class FullChartPainter extends CustomPainter {
  final List<List<double>> leftHistory, rightHistory;
  final bool isL, isR;

  FullChartPainter(this.leftHistory, this.rightHistory, this.isL, this.isR);

  @override
  void paint(Canvas canvas, Size size) {
    final paddingLeft = 35.0;
    final chartWidth = size.width - paddingLeft;
    final chartHeight = size.height - 25.0;

    final gridPaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;

    final axisPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // ================= GRID =================
    for (int i = 0; i <= 5; i++) {
      double y = chartHeight * (i / 5);

      canvas.drawLine(
        Offset(paddingLeft, y),
        Offset(size.width, y),
        gridPaint,
      );

      textPainter.text = TextSpan(
        text: '${(100 - i * 20)}',
        style: const TextStyle(color: Colors.black, fontSize: 10),
      );

      textPainter.layout();
      textPainter.paint(canvas, Offset(5, y - 6));
    }

    // ================= AXES =================
    canvas.drawLine(
      Offset(paddingLeft, 0),
      Offset(paddingLeft, chartHeight),
      axisPaint,
    );

    canvas.drawLine(
      Offset(paddingLeft, chartHeight),
      Offset(size.width, chartHeight),
      axisPaint,
    );

    // ================= LEFT =================
    if (isL) {
      for (int i = 0; i < leftHistory.length; i++) {
        _drawLine(canvas, leftHistory[i], _color(i),
            paddingLeft, chartWidth, chartHeight);
      }
    }

    // ================= RIGHT =================
    if (isR) {
      for (int i = 0; i < rightHistory.length; i++) {
        _drawLine(canvas, rightHistory[i], _color(i + 5),
            paddingLeft, chartWidth, chartHeight);
      }
    }
  }

  Color _color(int i) {
    const colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.cyan,
      Colors.indigo,
      Colors.red,
      Colors.purple,
      Colors.teal,
      Colors.deepOrange,
      Colors.pink,
    ];
    return colors[i % colors.length];
  }

  void _drawLine(
  Canvas canvas,
  List<double> data,
  Color color,
  double paddingLeft,
  double chartWidth,
  double chartHeight,
) {
  if (data.length < 2) return;

  final paint = Paint()
    ..color = color
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke;

  final path = Path();

  for (int i = 0; i < data.length - 1; i++) {
    final x1 = paddingLeft + (i / data.length) * chartWidth;
    final y1 = chartHeight - (data[i] / 100) * chartHeight;

    final x2 = paddingLeft + ((i + 1) / data.length) * chartWidth;
    final y2 = chartHeight - (data[i + 1] / 100) * chartHeight;

    final midX = (x1 + x2) / 2;

    if (i == 0) path.moveTo(x1, y1);

    path.quadraticBezierTo(x1, y1, midX, (y1 + y2) / 2);
  }

  canvas.drawPath(path, paint);
}

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
class SingleFootChartPainter extends CustomPainter {
  final List<List<double>> history;
  final bool isConnected;

  SingleFootChartPainter(this.history, this.isConnected);

  @override
  void paint(Canvas canvas, Size size) {
    // ================= NO DEVICE =================
    if (!isConnected) {
      final textPainter = TextPainter(
        text: const TextSpan(
          text: "No Device Connected",
          style: TextStyle(
            color: Colors.grey,
            fontSize: 14,
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          (size.width - textPainter.width) / 2,
          (size.height - textPainter.height) / 2,
        ),
      );
      return;
    }

    // ================= GRID =================
    final gridPaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;

    for (int i = 1; i < 5; i++) {
      double y = i * size.height / 5;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    for (int i = 1; i < 8; i++) {
      double x = i * size.width / 8;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint,
      );
    }

    // ================= GRAPH LINE STYLE =================
    final paint = Paint()
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
    ];

    // ================= DRAW ALL 5 SENSOR LINES =================
    for (int s = 0; s < history.length; s++) {
      final data = history[s];

      if (data.length < 2) continue;

      paint.color = colors[s];
      final path = Path();

      for (int i = 0; i < data.length; i++) {
        final x =
            (i / (data.length - 1)) * size.width;

        final value =
            data[i].clamp(0, 100).toDouble();

        final y =
            size.height -
            (value / 100) * size.height;

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

  
class CopPainter extends CustomPainter {
  final List<Offset> points;

  // These default bounds are compatible with your CURRENT symbolic COP space.
  // Later, when you replace sensor positions with real mm coordinates,
  // update these ranges accordingly.
  final double xMin;
  final double xMax;
  final double yMin;
  final double yMax;

  CopPainter(
    this.points, {
    this.xMin = -1.0,
    this.xMax = 1.0,
    this.yMin = -1.2,
    this.yMax = 1.2,
  });

  Offset _mapPoint(Offset p, Size size) {
    final double safeWidth = size.width <= 0 ? 1 : size.width;
    final double safeHeight = size.height <= 0 ? 1 : size.height;

    final double nx = ((p.dx - xMin) / (xMax - xMin)).clamp(0.0, 1.0);
    final double ny = ((p.dy - yMin) / (yMax - yMin)).clamp(0.0, 1.0);

    return Offset(
      nx * safeWidth,
      safeHeight - (ny * safeHeight),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Paint bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, bgPaint);

    final Paint borderPaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      borderPaint,
    );

    final Paint gridPaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;

    final Paint axisPaint = Paint()
      ..color = Colors.grey.shade600
      ..strokeWidth = 1.5;

    // ================= GRID =================
    for (int i = 1; i < 4; i++) {
      final double dx = size.width * i / 4;
      final double dy = size.height * i / 4;

      canvas.drawLine(
        Offset(dx, 0),
        Offset(dx, size.height),
        gridPaint,
      );
      canvas.drawLine(
        Offset(0, dy),
        Offset(size.width, dy),
        gridPaint,
      );
    }

    // ================= CENTER AXES =================
    final Offset center = _mapPoint(const Offset(0, 0), size);

    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      axisPaint,
    );

    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      axisPaint,
    );

    // ================= AXIS LABELS =================
    final TextPainter mlLeft = TextPainter(
      text: const TextSpan(
        text: "ML-",
        style: TextStyle(fontSize: 11, color: Colors.black54),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    mlLeft.paint(
      canvas,
      Offset(6, center.dy + 4),
    );

    final TextPainter mlRight = TextPainter(
      text: const TextSpan(
        text: "ML+",
        style: TextStyle(fontSize: 11, color: Colors.black54),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    mlRight.paint(
      canvas,
      Offset(size.width - mlRight.width - 6, center.dy + 4),
    );

    final TextPainter apTop = TextPainter(
      text: const TextSpan(
        text: "AP+",
        style: TextStyle(fontSize: 11, color: Colors.black54),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    apTop.paint(
      canvas,
      Offset(center.dx + 6, 4),
    );

    final TextPainter apBottom = TextPainter(
      text: const TextSpan(
        text: "AP-",
        style: TextStyle(fontSize: 11, color: Colors.black54),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    apBottom.paint(
      canvas,
      Offset(center.dx + 6, size.height - apBottom.height - 4),
    );

    if (points.isEmpty) {
      final TextPainter noData = TextPainter(
        text: const TextSpan(
          text: "No COP data",
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      noData.paint(
        canvas,
        Offset(
          (size.width - noData.width) / 2,
          (size.height - noData.height) / 2,
        ),
      );
      return;
    }

    final Paint pathPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Paint trailPointPaint = Paint()
      ..color = Colors.red.withOpacity(0.18)
      ..style = PaintingStyle.fill;

    final Paint lastPointPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    // ================= DRAW LIGHT TRAIL POINTS =================
    for (final pt in points) {
      final mapped = _mapPoint(pt, size);
      canvas.drawCircle(mapped, 1.8, trailPointPaint);
    }

    // ================= DRAW PATH =================
    if (points.length == 1) {
      final Offset only = _mapPoint(points.first, size);
      canvas.drawCircle(only, 5, lastPointPaint);
      return;
    }

    final Path path = Path();

    for (int i = 0; i < points.length; i++) {
      final Offset p = _mapPoint(points[i], size);

      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        final Offset prev = _mapPoint(points[i - 1], size);
        final Offset mid = Offset(
          (prev.dx + p.dx) / 2,
          (prev.dy + p.dy) / 2,
        );

        path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
      }
    }

    canvas.drawPath(path, pathPaint);

    // ================= DRAW LAST POINT =================
    final Offset last = _mapPoint(points.last, size);
    canvas.drawCircle(last, 5, lastPointPaint);
  }

  @override
  bool shouldRepaint(covariant CopPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.xMin != xMin ||
        oldDelegate.xMax != xMax ||
        oldDelegate.yMin != yMin ||
        oldDelegate.yMax != yMax;
  }
}
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> sessions = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadSessions();
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  String _numText(dynamic value, [int decimals = 2]) {
    final double v = value is num ? value.toDouble() : 0.0;
    return v.toStringAsFixed(decimals);
  }

  String _safeText(dynamic value, {String fallback = "-"}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  Future<void> loadSessions() async {
    final data = await StorageService.loadSessions();

    setState(() {
      sessions = data
          .map<Map<String, dynamic>>(
            (e) => Map<String, dynamic>.from(e as Map),
          )
          .toList()
          .reversed
          .toList();
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("History"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loadSessions,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : sessions.isEmpty
              ? _emptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final s = sessions[index];
                    return _sessionCard(s);
                  },
                ),
    );
  }

  // ================= EMPTY STATE =================
  Widget _emptyState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 60, color: Colors.grey),
            SizedBox(height: 10),
            Text(
              "No clinical sessions yet",
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 5),
            Text(
              "Saved patient recordings and calculated metrics will appear here",
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ================= SESSION CARD =================
  Widget _sessionCard(Map<String, dynamic> s) {
    final DateTime time =
        DateTime.tryParse(_safeText(s["timestamp"], fallback: "")) ??
            DateTime.now();

    final String patientName = _safeText(s["patientName"]);
    final String patientId = _safeText(s["patientId"]);
    final String age = _safeText(s["age"]);
    final String sex = _safeText(s["sex"]);
    final String testType = _safeText(s["testType"]);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Session: ${_twoDigits(time.day)}/${_twoDigits(time.month)}/${time.year}  ${_twoDigits(time.hour)}:${_twoDigits(time.minute)}",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text("Patient: $patientName"),
          Text("ID: $patientId"),
          Text("Age / Sex: $age / $sex"),
          Text("Test Type: $testType"),
          const SizedBox(height: 12),
          Row(
            children: [
              _infoBox("Steps", "${s["steps"] ?? 0}"),
              _infoBox("Duration", "${_numText(s["duration"], 1)}s"),
              _infoBox("Samples", "${s["samples"] ?? 0}"),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _infoBox("Speed", _numText(s["speed"], 2)),
              _infoBox("Cadence", _numText(s["cadence"], 1)),
              _infoBox("Balance", "${_numText(s["balance"], 1)}%"),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _infoBox("Symmetry", "${_numText(s["symmetry"], 1)}%"),
              _infoBox("COP Path", _numText(s["copPathLength"], 2)),
              _infoBox("Mean Vel.", _numText(s["meanVelocity"], 2)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _infoBox("ML Sway", _numText(s["copSwayX"], 2)),
              _infoBox("AP Sway", _numText(s["copSwayY"], 2)),
              _infoBox("ML RMS", _numText(s["mlRms"], 2)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _infoBox("AP RMS", _numText(s["apRms"], 2)),
              _infoBox("Left/Right", "${_numText(s["balance"], 1)} / ${_numText((100 - ((s["balance"] is num) ? (s["balance"] as num).toDouble() : 50.0)), 1)}"),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }

  // ================= INFO BOX =================
  Widget _infoBox(String title, String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= CALIBRATION PAGE =================

class CalibrationPage extends StatefulWidget {
  final bool isAnyConnected;
  final bool isLConnected;
  final bool isRConnected;
  final bool leftStreaming;
  final bool rightStreaming;

  final List<double> leftData;
  final List<double> rightData;

  final Future<void> Function() onCalibrateAllZero;
  final Future<void> Function(String foot) onCalibrateFootAllZero;
  final Future<void> Function(String foot, int sensorIndex) onSensorZero;
  final Future<void> Function(String foot, int sensorIndex, double knownWeight)
      onSensorSpan;
  final Future<void> Function() onClearCalibrationAll;
  final Future<void> Function(String foot) onClearCalibrationFoot;

  const CalibrationPage({
    super.key,
    required this.isAnyConnected,
    required this.isLConnected,
    required this.isRConnected,
    required this.leftStreaming,
    required this.rightStreaming,
    required this.leftData,
    required this.rightData,
    required this.onCalibrateAllZero,
    required this.onCalibrateFootAllZero,
    required this.onSensorZero,
    required this.onSensorSpan,
    required this.onClearCalibrationAll,
    required this.onClearCalibrationFoot,
  });

  @override
  State<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends State<CalibrationPage> {
  late final List<TextEditingController> _leftWeightControllers;
  late final List<TextEditingController> _rightWeightControllers;

  @override
  void initState() {
    super.initState();
    _leftWeightControllers =
        List.generate(5, (_) => TextEditingController());
    _rightWeightControllers =
        List.generate(5, (_) => TextEditingController());
  }

  @override
  void dispose() {
    for (final c in _leftWeightControllers) {
      c.dispose();
    }
    for (final c in _rightWeightControllers) {
      c.dispose();
    }
    super.dispose();
  }

  double? _parseWeight(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || value <= 0) return null;
    return value;
  }

  String _estimatedLoadText(double livePercent, TextEditingController controller) {
    final knownWeight = _parseWeight(controller);

    if (knownWeight == null) {
      return "Live: ${livePercent.toStringAsFixed(1)}";
    }

    final estimated = (livePercent / 100.0) * knownWeight;
    return "Live: ${livePercent.toStringAsFixed(1)} | Est: ${estimated.toStringAsFixed(1)}";
  }

  Future<void> _handleSensorSpan(
    String foot,
    int sensorIndex,
    TextEditingController controller,
  ) async {
    final knownWeight = _parseWeight(controller);

    if (knownWeight == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Enter a valid known weight for $foot S$sensorIndex before span calibration.",
          ),
        ),
      );
      return;
    }

    await widget.onSensorSpan(foot, sensorIndex, knownWeight);
  }

  Widget _buildStatusChip(String label, bool ok) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ok ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ok ? Colors.green.shade300 : Colors.red.shade300,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: ok ? Colors.green.shade800 : Colors.red.shade800,
        ),
      ),
    );
  }

  Widget _buildTopActionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Global Calibration",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "Step 1: Keep both insoles completely unloaded and press Zero All Sensors.\n"
            "Step 2: For each sensor, place a known weight on that sensor only, then press Span.",
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed:
                      widget.isAnyConnected ? widget.onCalibrateAllZero : null,
                  icon: const Icon(Icons.exposure_zero),
                  label: const Text("Zero All Sensors"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      widget.isAnyConnected ? widget.onClearCalibrationAll : null,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text("Clear All"),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStatusChip(
                widget.isAnyConnected ? "Device Ready" : "No Device Connected",
                widget.isAnyConnected,
              ),
              _buildStatusChip(
                widget.isLConnected ? "Left Connected" : "Left Disconnected",
                widget.isLConnected,
              ),
              _buildStatusChip(
                widget.isRConnected ? "Right Connected" : "Right Disconnected",
                widget.isRConnected,
              ),
              _buildStatusChip(
                widget.leftStreaming ? "Left Streaming" : "Left Not Streaming",
                widget.leftStreaming,
              ),
              _buildStatusChip(
                widget.rightStreaming ? "Right Streaming" : "Right Not Streaming",
                widget.rightStreaming,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFootCalibrationCard({
    required String foot,
    required bool connected,
    required bool streaming,
    required List<double> values,
    required List<TextEditingController> controllers,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "$foot Foot Calibration",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _buildStatusChip(
                connected ? "Connected" : "Disconnected",
                connected,
              ),
              const SizedBox(width: 8),
              _buildStatusChip(
                streaming ? "Streaming" : "No Stream",
                streaming,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: connected
                      ? () => widget.onCalibrateFootAllZero(foot)
                      : null,
                  icon: const Icon(Icons.exposure_zero),
                  label: const Text("Zero All"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      connected ? () => widget.onClearCalibrationFoot(foot) : null,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text("Clear Foot"),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            "For span calibration, enter the known weight and apply that weight on only the selected sensor.",
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < 5; i++)
            _buildSensorRow(
              foot: foot,
              sensorIndex: i + 1,
              liveValue: values[i],
              connected: connected,
              controller: controllers[i],
            ),
        ],
      ),
    );
  }

  Widget _buildSensorRow({
    required String foot,
    required int sensorIndex,
    required double liveValue,
    required bool connected,
    required TextEditingController controller,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  "S$sensorIndex",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: Text(
                  connected ? _estimatedLoadText(liveValue, controller) : "No data",
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: "Known Weight",
                    hintText: "e.g. 500",
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: connected
                      ? () => widget.onSensorZero(foot, sensorIndex)
                      : null,
                  child: const Text("Zero"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: connected
                      ? () => _handleSensorSpan(foot, sensorIndex, controller)
                      : null,
                  child: const Text("Span"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Calibration")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildTopActionCard(),
            const SizedBox(height: 16),
            _buildFootCalibrationCard(
              foot: "Left",
              connected: widget.isLConnected,
              streaming: widget.leftStreaming,
              values: widget.leftData,
              controllers: _leftWeightControllers,
            ),
            const SizedBox(height: 16),
            _buildFootCalibrationCard(
              foot: "Right",
              connected: widget.isRConnected,
              streaming: widget.rightStreaming,
              values: widget.rightData,
              controllers: _rightWeightControllers,
            ),
          ],
        ),
      ),
    );
  }
}
// ================= SETTINGS PAGE =================

class SettingsPage extends StatelessWidget {
  final bool isLConnected, isRConnected;

  const SettingsPage({
    super.key,
    required this.isLConnected,
    required this.isRConnected,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "Device Status",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          // ================= LEFT =================
          Card(
            child: ListTile(
              leading: Icon(
                Icons.bluetooth,
                color: isLConnected ? Colors.blue : Colors.grey,
              ),
              title: const Text("Left Insole"),
              subtitle: Text(
                isLConnected ? "Connected" : "Disconnected",
              ),
              trailing: Icon(
                isLConnected ? Icons.check_circle : Icons.cancel,
                color: isLConnected ? Colors.green : Colors.red,
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ================= RIGHT =================
          Card(
            child: ListTile(
              leading: Icon(
                Icons.bluetooth,
                color: isRConnected ? Colors.blue : Colors.grey,
              ),
              title: const Text("Right Insole"),
              subtitle: Text(
                isRConnected ? "Connected" : "Disconnected",
              ),
              trailing: Icon(
                isRConnected ? Icons.check_circle : Icons.cancel,
                color: isRConnected ? Colors.green : Colors.red,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ================= INFO SECTION =================
          Card(
            color: Colors.blue.shade50,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                "Smart Insole System monitors plantar pressure, gait phases, "
                "and balance in real time using BLE-connected sensors.",
              ),
            ),
          ),
        ],
      ),
    );
  }
}