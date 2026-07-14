import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'rig_buttons.dart';

// ────────────────────────── Protocol constants ──────────────────────────

const int HPSDR_PORT = 1024;
const int DISCOVERY_PACKET_SIZE = 60;
const int COMMAND_PACKET_SIZE = 64;
const int IQ_PACKET_SIZE = 1032;

// Discovery packet: 0xEF 0xFE 0x02 + 57 zeros
final Uint8List discoveryPacket = Uint8List.fromList(
  [0xEF, 0xFE, 0x02] + List.filled(57, 0x00),
);

// ────────────────────────── Board discovery ──────────────────────────

enum HpsdrBoardKind {
  metis,
  hermes,
  hermesII,
  angelia,
  orion,
  orionMkII,
  hermesLite2,
  hermesC10,
  unknown,
}

class HermesBoard {
  final InternetAddress ip;
  final String macAddress;
  final HpsdrBoardKind boardKind;
  final String firmwareString;
  final bool busy;
  final int numReceivers;
  final int protocolSupported;
  final int codeVersion;
  final int betaVersion;
  const HermesBoard({
    required this.ip,
    required this.macAddress,
    required this.boardKind,
    required this.firmwareString,
    required this.busy,
    required this.numReceivers,
    required this.protocolSupported,
    required this.codeVersion,
    required this.betaVersion,
  });
}

class HermesDiscovery {
  static Future<HermesBoard?> probe(
    String ip, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final target = InternetAddress(ip);
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;

    // Send the standard Protocol 2 discovery packet
    socket.send(discoveryPacket, target, HPSDR_PORT);

    final completer = Completer<HermesBoard?>();
    Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(null);
    });

    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null || datagram.data.length < 24) return;
      if (datagram.address.address != ip) return;
      final board = _parseReply(datagram.data, datagram.address);
      if (board != null && !completer.isCompleted) {
        completer.complete(board);
        socket.close();
      }
    });

    final result = await completer.future;
    socket.close();
    return result;
  }

  static HermesBoard? _parseReply(Uint8List raw, InternetAddress fromIp) {
    // Standard reply: 0xEF 0xFE 0x02 0x02 or 0x03 etc.
    if (raw.length < 24) return null;
    if (raw[0] != 0xEF || raw[1] != 0xFE || raw[2] != 0x02) return null;
    final status = raw[3];
    if (status != 0x02 && status != 0x03) return null;

    final macBytes = Uint8List.sublistView(raw, 4, 10);
    final mac = macBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':');
    final rawBoardId = raw[10];
    final boardKind = _mapBoard(rawBoardId);
    final protocolSupported = raw[11];
    final codeVersion = raw[12];
    final numReceivers = raw[19];
    final betaVersion = raw.length > 22 ? raw[22] : 0;
    final firmwareString = _formatFirmware(codeVersion, betaVersion);

    return HermesBoard(
      ip: fromIp,
      macAddress: mac,
      boardKind: boardKind,
      firmwareString: firmwareString,
      busy: status == 0x03,
      numReceivers: numReceivers,
      protocolSupported: protocolSupported,
      codeVersion: codeVersion,
      betaVersion: betaVersion,
    );
  }

  static HpsdrBoardKind _mapBoard(int raw) => switch (raw) {
    0x00 => HpsdrBoardKind.metis,
    0x01 => HpsdrBoardKind.hermes,
    0x02 => HpsdrBoardKind.hermesII,
    0x03 => HpsdrBoardKind.angelia,
    0x04 => HpsdrBoardKind.orion,
    0x05 => HpsdrBoardKind.orionMkII,
    0x06 => HpsdrBoardKind.hermesLite2,
    0x0A => HpsdrBoardKind.orionMkII,
    0x14 => HpsdrBoardKind.hermesC10,
    _ => HpsdrBoardKind.unknown,
  };

  static String _formatFirmware(int codeVersion, int betaVersion) {
    final major = codeVersion ~/ 10;
    final minor = codeVersion % 10;
    return betaVersion == 0 ? '$major.$minor' : '$major.${minor}b$betaVersion';
  }
}

// ───────────────────── Proper Protocol 2 command builder ─────────────────────

class HermesCommand {
  int sequence = 0;
  bool mox = false; // transmit if true
  bool internalKeyer = false;
  bool iambicModeB = false;
  bool reversePaddles = false;
  int sampleRateCode = 1; // 0=48k, 1=96k, 2=192k, 3=384k
  bool preAmp = false;
  bool externalClock = false;
  bool alexOverride = false;
  bool cwKeyJack = false;
  int txAttenuation = 0; // 0..255
  int vfoAFreq = 7030000; // Hz
  int vfoBFreq = 0;
  int alexFilter = 0; // 0=auto, 1..7 for bands
  int cwSpeed = 20; // 1..60 WPM
  int sidetonePitch = 700; // Hz
  int sidetoneVolume = 127;
  int openCollector = 0;
  int txPhase = 0;
  int rxPhaseDdc1 = 0;
  int rxPhaseDdc2 = 0;
  int pureSignalTxAtt = 0;
  int pureSignalRxAtt = 0;

  Uint8List build() {
    final frame = Uint8List(COMMAND_PACKET_SIZE);
    final view = ByteData.sublistView(frame);

    // Magic header (bytes 0-2): 0xEF 0xFE 0x00
    view.setUint8(0, 0xEF);
    view.setUint8(1, 0xFE);
    view.setUint8(2, 0x00);

    // Byte 3: sequence number (increment each time)
    view.setUint8(3, sequence & 0xFF);
    sequence++;

    // Byte 4: MOX, keyer settings
    int b4 = 0;
    if (mox) b4 |= 0x01;
    if (internalKeyer) b4 |= 0x20;
    if (iambicModeB) b4 |= 0x40;
    if (reversePaddles) b4 |= 0x80;
    view.setUint8(4, b4);

    // Byte 5: sample rate
    view.setUint8(5, sampleRateCode.clamp(0, 3));

    // Byte 6: hardware options
    int b6 = 0;
    if (preAmp) b6 |= 0x01;
    if (externalClock) b6 |= 0x02;
    if (alexOverride) b6 |= 0x04;
    if (cwKeyJack) b6 |= 0x10;
    view.setUint8(6, b6);

    // Byte 7: TX attenuation
    view.setUint8(7, txAttenuation.clamp(0, 255));

    // Bytes 8-11: VFO A (big-endian)
    view.setUint32(8, vfoAFreq, Endian.big);

    // Bytes 12-15: VFO B
    view.setUint32(12, vfoBFreq, Endian.big);

    // Byte 16: Alex filter
    view.setUint8(16, alexFilter.clamp(0, 7));

    // Byte 17: CW speed
    view.setUint8(17, cwSpeed.clamp(1, 60));

    // Bytes 18-19: sidetone pitch
    view.setUint16(18, sidetonePitch, Endian.big);

    // Byte 20: sidetone volume
    view.setUint8(20, sidetoneVolume.clamp(0, 255));

    // Byte 21: open collector mask
    view.setUint8(21, openCollector & 0xFF);

    // Bytes 22-25: TX phase offset
    view.setInt32(22, txPhase, Endian.big);

    // Bytes 26-29: DDC1 phase
    view.setInt32(26, rxPhaseDdc1, Endian.big);

    // Bytes 30-33: DDC2 phase
    view.setInt32(30, rxPhaseDdc2, Endian.big);

    // Byte 34: PureSignal TX att
    view.setUint8(34, pureSignalTxAtt.clamp(0, 255));

    // Byte 35: PureSignal RX att
    view.setUint8(35, pureSignalRxAtt.clamp(0, 255));

    // Bytes 36-63: reserved (zero)
    // Already zero because Uint8List is zero-initialised.

    return frame;
  }
}

// ───────────────────── UDP connection with periodic commands ─────────────────────

class HermesConnection {
  final InternetAddress boardIp;
  final int port = HPSDR_PORT;

  RawDatagramSocket? _socket;
  StreamSubscription? _subscription;
  Timer? _heartbeatTimer;
  final HermesCommand _command = HermesCommand();
  int _packetCount = 0;
  bool _connected = false;

  HermesConnection({required this.boardIp});

  int get packetCount => _packetCount;
  bool get isConnected => _connected;

  Future<void> connect() async {
    if (_connected) return;

    // Bind to port 1024 – the Hermes will send data back to this source port.
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
    _socket!.broadcastEnabled = false; // not needed for unicast

    // Listen for incoming UDP packets (both I/Q data and telemetry)
    _subscription = _socket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = _socket!.receive();
        if (dg != null && dg.address.address == boardIp.address) {
          _packetCount++;
          // Print first 10 bytes of the first 3 packets
          if (_packetCount <= 3) {
            final hex = dg.data
                .take(10)
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join(' ');
            print('Packet $_packetCount, size=${dg.data.length}, header: $hex');
          }
        }
      }
    });

    // Start the watchdog timer: send command every 200 ms.
    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 200), (
      timer,
    ) {
      _sendCommand();
    });

    // Send an initial command immediately.
    _sendCommand();

    _connected = true;
    print('Hermes connection established, sending commands every 200 ms.');
  }

  void _sendCommand() {
    if (_socket == null || !_connected) return;
    final frame = _command.build();
    _socket!.send(frame, boardIp, port);
  }

  Future<void> disconnect() async {
    _connected = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
    _packetCount = 0;
    print('Disconnected.');
  }

  void dispose() => disconnect();

  // Convenience methods to change frequency, etc.
  void setFrequency(int freqHz) {
    _command.vfoAFreq = freqHz;
  }

  void setSampleRate(int code) {
    _command.sampleRateCode = code.clamp(0, 3);
  }
}

// ────────────────────────── UI ──────────────────────────

void main() => runApp(const MaterialApp(home: HermesDiscoveryTest()));

class HermesDiscoveryTest extends StatefulWidget {
  const HermesDiscoveryTest({super.key});
  @override
  State<HermesDiscoveryTest> createState() => _HermesDiscoveryTestState();
}

class _HermesDiscoveryTestState extends State<HermesDiscoveryTest> {
  HermesConnection? _connection;
  bool _connecting = false;
  int _packetCount = 0;
  HermesBoard? _probedBoard;
  Timer? _uiTimer;

  // Rig control state variables
  int _currentFrequency = 7030000; // default VFO A = 7.030.000 Hz (40m QRP CW)
  bool _mox = false; // transmit indicator
  bool _preAmp = false;
  bool _externalClock = false;
  bool _cwKeyJack = false;
  bool _alexOverride = false;
  int _sampleRateCode = 1; // 0=48k, 1=96k, 2=192k, 3=384k
  double _signalLevel = 0.0; // S-meter / PO level

  final Map<String, int> _bands = {
    '160M': 1800000,
    '80M': 3500000,
    '40M': 7030000,
    '20M': 1407400,
    '15M': 2107400,
    '10M': 2807400,
  };

  @override
  void dispose() {
    _connection?.dispose();
    _uiTimer?.cancel();
    super.dispose();
  }

  Future<void> _probeAndConnect() async {
    setState(() => _connecting = true);
    try {
      final board = await HermesDiscovery.probe('192.168.1.24');
      if (board == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No Hermes board found at 192.168.1.24'),
              backgroundColor: Color(0xFFFF5252),
            ),
          );
        }
        setState(() => _connecting = false);
        return;
      }
      setState(() => _probedBoard = board);

      // Create connection and configure options before starting
      final conn = HermesConnection(boardIp: board.ip);
      conn.setFrequency(_currentFrequency);
      conn.setSampleRate(_sampleRateCode);
      conn._command.mox = _mox;
      conn._command.preAmp = _preAmp;
      conn._command.externalClock = _externalClock;
      conn._command.cwKeyJack = _cwKeyJack;
      conn._command.alexOverride = _alexOverride;

      await conn.connect();
      _connection = conn;

      // Start the UI timer to update packet counts & simulate S-Meter
      _uiTimer?.cancel();
      _uiTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
        if (mounted && _connection == conn) {
          final int currentCount = conn.packetCount;
          final int diff = currentCount - _packetCount;
          _packetCount = currentCount;

          setState(() {
            if (_mox) {
              // TX: power meter is high with small variations (e.g. 95W output)
              _signalLevel = 0.9 + (math.Random().nextDouble() * 0.05);
            } else if (diff > 0) {
              // Active packet flow: simulate active RX signal fluctuations (S7 to S9)
              _signalLevel = 0.5 + (math.Random().nextDouble() * 0.35);
            } else {
              // Connected but no packets: background static (S1)
              _signalLevel = 0.1 + (math.Random().nextDouble() * 0.05);
            }
          });
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFFF5252),
          ),
        );
      }
      print('Connection error: $e');
    } finally {
      setState(() => _connecting = false);
    }
  }

  Future<void> _disconnect() async {
    _uiTimer?.cancel();
    _uiTimer = null;
    await _connection?.disconnect();
    setState(() {
      _connection = null;
      _packetCount = 0;
      _signalLevel = 0.0;
    });
  }

  void _onPowerToggled(bool value) {
    if (value) {
      _probeAndConnect();
    } else {
      _disconnect();
    }
  }

  void _onMoxChanged(bool isTx) {
    setState(() {
      _mox = isTx;
      if (_connection != null) {
        _connection!._command.mox = _mox;
      }
    });
  }

  void _onTune(int deltaHz) {
    setState(() {
      _currentFrequency = (_currentFrequency + deltaHz).clamp(100000, 60000000);
      if (_connection != null) {
        _connection!.setFrequency(_currentFrequency);
      }
    });
  }

  void _selectBand(String band, int defaultFreq) {
    setState(() {
      _currentFrequency = defaultFreq;
      if (_connection != null) {
        _connection!.setFrequency(_currentFrequency);
      }
    });
  }

  void _togglePreAmp() {
    setState(() {
      _preAmp = !_preAmp;
      if (_connection != null) {
        _connection!._command.preAmp = _preAmp;
      }
    });
  }

  void _toggleExtClock() {
    setState(() {
      _externalClock = !_externalClock;
      if (_connection != null) {
        _connection!._command.externalClock = _externalClock;
      }
    });
  }

  void _toggleKeyJack() {
    setState(() {
      _cwKeyJack = !_cwKeyJack;
      if (_connection != null) {
        _connection!._command.cwKeyJack = _cwKeyJack;
      }
    });
  }

  void _toggleAlexOverride() {
    setState(() {
      _alexOverride = !_alexOverride;
      if (_connection != null) {
        _connection!._command.alexOverride = _alexOverride;
      }
    });
  }

  void _cycleSampleRate() {
    setState(() {
      _sampleRateCode = (_sampleRateCode + 1) % 4;
      if (_connection != null) {
        _connection!.setSampleRate(_sampleRateCode);
      }
    });
  }

  String _formatFrequency(int freqHz) {
    final s = freqHz.toString().padLeft(8, '0');
    if (s.length <= 8) {
      final mhz = s.substring(0, 2);
      final khz = s.substring(2, 5);
      final hz = s.substring(5, 8);
      return '$mhz.$khz.$hz';
    } else {
      final len = s.length;
      final mhz = s.substring(0, len - 6);
      final khz = s.substring(len - 6, len - 3);
      final hz = s.substring(len - 3, len);
      return '$mhz.$khz.$hz';
    }
  }

  String _getSampleRateLabel(int code) => switch (code) {
    0 => '48 kHz',
    1 => '96 kHz',
    2 => '192 kHz',
    3 => '384 kHz',
    _ => 'Unknown',
  };

  @override
  Widget build(BuildContext context) {
    final bool isConnected = _connection != null;

    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F1218),
      ),
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Container(
                margin: const EdgeInsets.all(16),
                constraints: const BoxConstraints(maxWidth: 920),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E242F), // Metal cabinet base color
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF2D3646), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.8),
                      blurRadius: 16,
                      offset: const Offset(4, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // --- 1. Top Panel Ribbon (SDR Status Info & Title) ---
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFF151921),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(6),
                          topRight: Radius.circular(6),
                        ),
                        border: Border(
                          bottom: BorderSide(
                            color: Color(0xFF262F3F),
                            width: 1.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.radio,
                            color: Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'YAESU FTDX-101D SDR CONSOLE',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const Spacer(),
                          // Connection Indicator Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isConnected
                                  ? const Color(0x1F4CAF50)
                                  : const Color(0x1FFF5252),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isConnected
                                    ? const Color(0xFF4CAF50)
                                    : const Color(0xFFFF5252),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isConnected
                                        ? const Color(0xFF4CAF50)
                                        : const Color(0xFFFF5252),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isConnected ? 'ONLINE' : 'OFFLINE',
                                  style: TextStyle(
                                    color: isConnected
                                        ? const Color(0xFF4CAF50)
                                        : const Color(0xFFFF5252),
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // --- 2. Main Hardware Panel ---
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // --- Left Control Column (Power, RX/TX, Actions) ---
                          Column(
                            children: [
                              const Text(
                                'POWER',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              RigPowerButton(
                                isPressed: isConnected,
                                onChanged: _onPowerToggled,
                              ),
                              if (_connecting) ...[
                                const SizedBox(height: 12),
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF00E5FF),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 24),
                              const Text(
                                'MOX',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              RigRxTxButton(
                                label: 'RX',
                                type: RxTxType.rx,
                                isActive: !_mox,
                                onTap: () => _onMoxChanged(false),
                              ),
                              const SizedBox(height: 8),
                              RigRxTxButton(
                                label: 'TX',
                                type: RxTxType.tx,
                                isActive: _mox,
                                onTap: () => _onMoxChanged(true),
                              ),
                            ],
                          ),

                          const SizedBox(width: 20),

                          // --- Middle Column (LCD Screen + Grid buttons) ---
                          Expanded(
                            child: Column(
                              children: [
                                // LCD Digital Display Screen
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF070B11),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: const Color(0xFF1E2836),
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF00E5FF,
                                        ).withValues(alpha: 0.03),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Top info bar on LCD Screen
                                      Row(
                                        children: [
                                          const Text(
                                            'VFO-A',
                                            style: TextStyle(
                                              color: Color(0xFF00E5FF),
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 1,
                                            ),
                                            color: _mox
                                                ? const Color(0x3FFF3D00)
                                                : const Color(0x1F00E5FF),
                                            child: Text(
                                              _mox ? 'TX' : 'RX',
                                              style: TextStyle(
                                                color: _mox
                                                    ? const Color(0xFFFF3D00)
                                                    : const Color(0xFF00E5FF),
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            'SR: ${_getSampleRateLabel(_sampleRateCode)}',
                                            style: TextStyle(
                                              color: const Color(
                                                0xFF00E5FF,
                                              ).withValues(alpha: 0.8),
                                              fontSize: 9,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),

                                      // Giant LED Glowing Frequency
                                      Center(
                                        child: Text(
                                          _formatFrequency(_currentFrequency),
                                          style: TextStyle(
                                            color: const Color(0xFF00E5FF),
                                            fontFamily: 'monospace',
                                            fontSize: 40,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.5,
                                            shadows: [
                                              BoxShadow(
                                                color: const Color(
                                                  0xFF00E5FF,
                                                ).withValues(alpha: 0.4),
                                                blurRadius: 10,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      // S-Meter Widget
                                      SizedBox(
                                        height: 48,
                                        width: double.infinity,
                                        child: CustomPaint(
                                          painter: SMeterPainter(
                                            signal: _signalLevel,
                                            isTx: _mox,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 16),

                                // Band Select Row
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF151921),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: const Color(0xFF242C3A),
                                      width: 1,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.only(bottom: 6.0),
                                        child: Text(
                                          'BAND SELECT',
                                          style: TextStyle(
                                            color: Colors.white30,
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: _bands.entries.map((entry) {
                                          final isSel =
                                              (_currentFrequency >=
                                                  entry.value &&
                                              (_bands.values
                                                      .where(
                                                        (v) => v > entry.value,
                                                      )
                                                      .isEmpty ||
                                                  _currentFrequency <
                                                      _bands.values.firstWhere(
                                                        (v) => v > entry.value,
                                                      )));
                                          return RigBandButton(
                                            label: entry.key,
                                            isSelected: isSel,
                                            onTap: () => _selectBand(
                                              entry.key,
                                              entry.value,
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 12),

                                // Function Keys Row
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    RigFunctionButton(
                                      label: 'PRE-AMP',
                                      hasDotIndicator: true,
                                      isIndicatorOn: _preAmp,
                                      onTap: _togglePreAmp,
                                    ),
                                    RigFunctionButton(
                                      label: 'EXT CLK',
                                      hasDotIndicator: true,
                                      isIndicatorOn: _externalClock,
                                      onTap: _toggleExtClock,
                                    ),
                                    RigFunctionButton(
                                      label: 'KEY JACK',
                                      hasDotIndicator: true,
                                      isIndicatorOn: _cwKeyJack,
                                      onTap: _toggleKeyJack,
                                    ),
                                    RigFunctionButton(
                                      label: 'ALEX OVR',
                                      hasDotIndicator: true,
                                      isIndicatorOn: _alexOverride,
                                      onTap: _toggleAlexOverride,
                                    ),
                                    RigFunctionButton(
                                      label: 'SMP RATE',
                                      hasDotIndicator: false,
                                      onTap: _cycleSampleRate,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 24),

                          // --- Right Column (Tuning Section) ---
                          Column(
                            children: [
                              const Text(
                                'VFO-A TUNE',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              RigTuningDial(
                                onFrequencyDelta: _onTune,
                                size: 130,
                              ),
                              const SizedBox(height: 12),
                              // Direction indicators
                              Row(
                                children: [
                                  Icon(
                                    Icons.arrow_left,
                                    color: Colors.grey.shade600,
                                    size: 16,
                                  ),
                                  Text(
                                    'STEP: 100 Hz',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_right,
                                    color: Colors.grey.shade600,
                                    size: 16,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // --- 3. Telemetry Footer bar (Optional board details) ---
                    if (_probedBoard != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xFF151921),
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(6),
                            bottomRight: Radius.circular(6),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'BOARD: ${_probedBoard!.boardKind.name.toUpperCase()}',
                              style: const TextStyle(
                                color: Colors.white30,
                                fontSize: 9,
                                fontFamily: 'monospace',
                              ),
                            ),
                            Text(
                              'FIRMWARE: V${_probedBoard!.firmwareString}',
                              style: const TextStyle(
                                color: Colors.white30,
                                fontSize: 9,
                                fontFamily: 'monospace',
                              ),
                            ),
                            Text(
                              'MAC: ${_probedBoard!.macAddress.toUpperCase()}',
                              style: const TextStyle(
                                color: Colors.white30,
                                fontSize: 9,
                                fontFamily: 'monospace',
                              ),
                            ),
                            Text(
                              'PACKETS: $_packetCount',
                              style: TextStyle(
                                color: isConnected
                                    ? const Color(0xFF00E5FF)
                                    : Colors.white30,
                                fontSize: 9,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Color(0xFF151921),
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(6),
                            bottomRight: Radius.circular(6),
                          ),
                        ),
                        child: const Text(
                          'BOARD OFFLINE — TOGGLE POWER BUTTON TO PROBE',
                          style: TextStyle(
                            color: Colors.white24,
                            fontSize: 9,
                            letterSpacing: 0.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────── S-Meter / Level Meter Painter ─────────────────────

class SMeterPainter extends CustomPainter {
  final double signal; // 0.0 to 1.0
  final bool isTx;

  SMeterPainter({required this.signal, required this.isTx});

  @override
  void paint(Canvas canvas, Size size) {
    final paintBg = Paint()
      ..color = const Color(0xFF10141D)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(2),
      ),
      paintBg,
    );

    final double barY = size.height * 0.45;
    final double barHeight = 5.0;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // Draw ticks
    final tickPaint = Paint()..strokeWidth = 1.0;
    for (int i = 0; i <= 10; i++) {
      final double x = (size.width - 20) * (i / 10) + 10;
      final isMajor = i % 2 == 0;
      tickPaint.color = i > 7
          ? const Color(0xFFFF5252)
          : const Color(0xFF00E5FF).withValues(alpha: 0.5);
      canvas.drawLine(
        Offset(x, barY - (isMajor ? 4 : 2)),
        Offset(x, barY),
        tickPaint,
      );

      if (isMajor) {
        String label = '';
        if (i == 0) {
          label = 'S1';
        } else if (i == 4)
          label = 'S5';
        else if (i == 7)
          label = 'S9';
        else if (i == 10)
          label = '+60';

        textPainter.text = TextSpan(
          text: label,
          style: TextStyle(
            color: i > 7
                ? const Color(0xFFFF5252)
                : const Color(0xFF00E5FF).withValues(alpha: 0.6),
            fontSize: 7.5,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x - textPainter.width / 2, barY - 14));
      }
    }

    // Draw active level bar
    final double activeWidth = (size.width - 20) * signal;
    if (activeWidth > 0) {
      final activePaint = Paint()
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          colors: [
            const Color(0xFF00E5FF),
            const Color(0xFF00E5FF),
            const Color(0xFFFFD54F),
            const Color(0xFFFF5252),
          ],
          stops: const [0.0, 0.7, 0.85, 1.0],
        ).createShader(Rect.fromLTWH(10, barY, size.width - 20, barHeight));

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(10, barY, activeWidth, barHeight),
          const Radius.circular(1),
        ),
        activePaint,
      );
    }

    // Bottom Labels
    textPainter.text = TextSpan(
      text: isTx ? 'TX POWER' : 'SIG STRENGTH (S)',
      style: TextStyle(
        color: isTx
            ? const Color(0xFFFF5252)
            : const Color(0xFF00E5FF).withValues(alpha: 0.8),
        fontSize: 8.5,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(10, barY + barHeight + 4));

    // Show textual level on right
    String valStr = '';
    if (isTx) {
      valStr = '${(signal * 100).round()} W';
    } else {
      int sVal = (signal * 9).round();
      if (sVal <= 9) {
        valStr = 'S$sVal';
      } else {
        valStr = 'S9+${((signal - 0.9) * 600).round().clamp(0, 60)}dB';
      }
    }
    textPainter.text = TextSpan(
      text: valStr,
      style: TextStyle(
        color: isTx ? const Color(0xFFFF5252) : const Color(0xFF00E5FF),
        fontSize: 9.5,
        fontWeight: FontWeight.bold,
        fontFamily: 'monospace',
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(size.width - 10 - textPainter.width, barY + barHeight + 3),
    );
  }

  @override
  bool shouldRepaint(covariant SMeterPainter oldDelegate) {
    return oldDelegate.signal != signal || oldDelegate.isTx != isTx;
  }
}
