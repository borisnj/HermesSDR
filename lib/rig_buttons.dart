import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A collection of premium, highly tactile, skeuomorphic buttons
/// inspired by the Yaesu FTDX101D HF transceiver rig.
///
/// These widgets mimic the physical buttons, glowing LEDs, and
/// metallic textures found on amateur radio hardware.

// ---------------------------------------------------------------------
// 1. Rig Power Button (ON/OFF)
// ---------------------------------------------------------------------
class RigPowerButton extends StatefulWidget {
  final bool isPressed;
  final ValueChanged<bool> onChanged;

  const RigPowerButton({
    super.key,
    required this.isPressed,
    required this.onChanged,
  });

  @override
  State<RigPowerButton> createState() => _RigPowerButtonState();
}

class _RigPowerButtonState extends State<RigPowerButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final glowColor = const Color(0xFF00E5FF); // Cyber Cyan/Blue glow
    final baseColor = const Color(0xFF1E2631);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () => widget.onChanged(!widget.isPressed),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: widget.isPressed
                  ? glowColor.withValues(alpha: 0.8)
                  : (_isHovered
                        ? const Color(0xFF546E7A)
                        : const Color(0xFF37474F)),
              width: 1.5,
            ),
            boxShadow: [
              // Outer drop shadow for tactile depth
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                offset: const Offset(2, 2),
                blurRadius: 3,
              ),
              // Inner glowing shadow when ON
              if (widget.isPressed)
                BoxShadow(
                  color: glowColor.withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
            ],
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.isPressed
                  ? [const Color(0xFF101B2B), const Color(0xFF071120)]
                  : [const Color(0xFF2C3540), const Color(0xFF151B22)],
            ),
          ),
          child: Center(
            child: Icon(
              Icons.power_settings_new,
              size: 24,
              color: widget.isPressed ? glowColor : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// 2. Rig Band Button (With LED Bar Indicator above)
// ---------------------------------------------------------------------
class RigBandButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const RigBandButton({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ledGlowColor = const Color(0xFFFFB300); // Amber LED indicator

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // LED Bar Indicator
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 24,
            height: 3,
            decoration: BoxDecoration(
              color: isSelected ? ledGlowColor : const Color(0xFF263238),
              borderRadius: BorderRadius.circular(1),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: ledGlowColor.withValues(alpha: 0.8),
                        blurRadius: 4,
                        spreadRadius: 0.5,
                      ),
                    ]
                  : [],
            ),
          ),
          const SizedBox(height: 6),
          // Button Cap
          Container(
            width: 48,
            height: 24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: const Color(0xFF212121), width: 1),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF3E4651), // Top sheen
                  Color(0xFF1F242C), // Dark face
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  offset: const Offset(1, 1),
                  blurRadius: 1,
                ),
              ],
            ),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// 3. Rig RX/TX Curved Pill Button
// ---------------------------------------------------------------------
enum RxTxType { rx, tx }

class RigRxTxButton extends StatelessWidget {
  final String label;
  final RxTxType type;
  final bool isActive;
  final VoidCallback onTap;

  const RigRxTxButton({
    super.key,
    required this.label,
    required this.type,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Green glow for RX (Receive), Red/Orange for TX (Transmit)
    final glowColor = type == RxTxType.rx
        ? const Color(0xFF4CAF50)
        : const Color(0xFFFF3D00);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive
                ? glowColor.withValues(alpha: 0.8)
                : const Color(0xFF263238),
            width: 1.5,
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isActive
                ? [
                    glowColor.withValues(alpha: 0.25),
                    glowColor.withValues(alpha: 0.05),
                  ]
                : [const Color(0xFF2A313C), const Color(0xFF171B22)],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              offset: const Offset(1.5, 1.5),
              blurRadius: 2,
            ),
            if (isActive)
              BoxShadow(
                color: glowColor.withValues(alpha: 0.3),
                blurRadius: 6,
                spreadRadius: 0.5,
              ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? glowColor : Colors.grey.shade400,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// 4. Rig Under-Screen Flat Function Key
// ---------------------------------------------------------------------
class RigFunctionButton extends StatelessWidget {
  final String label;
  final bool hasDotIndicator;
  final bool isIndicatorOn;
  final VoidCallback onTap;

  const RigFunctionButton({
    super.key,
    required this.label,
    this.hasDotIndicator = false,
    this.isIndicatorOn = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 28,
        decoration: BoxDecoration(
          color: const Color(0xFF1E222A),
          border: Border.all(color: const Color(0xFF2D3543), width: 1),
          borderRadius: BorderRadius.circular(1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              offset: const Offset(1, 1),
              blurRadius: 1,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Text Label
            Positioned(
              top: 4,
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            // Tiny LED indicator dot in the bottom center
            if (hasDotIndicator)
              Positioned(
                bottom: 3,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isIndicatorOn
                        ? const Color(0xFFFF5252)
                        : const Color(0xFF263238),
                    boxShadow: isIndicatorOn
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xFFFF5252,
                              ).withValues(alpha: 0.8),
                              blurRadius: 2,
                              spreadRadius: 0.5,
                            ),
                          ]
                        : [],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// 5. Rig Tuning Dial (Continuous Rotation Knob)
// ---------------------------------------------------------------------
class RigTuningDial extends StatefulWidget {
  final ValueChanged<int> onFrequencyDelta;
  final double size;

  const RigTuningDial({
    super.key,
    required this.onFrequencyDelta,
    this.size = 140.0,
  });

  @override
  State<RigTuningDial> createState() => _RigTuningDialState();
}

class _RigTuningDialState extends State<RigTuningDial> {
  double _rotationAngle = 0.0;
  double _lastAngle = 0.0;

  void _onPanStart(DragStartDetails details, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final position = details.localPosition - center;
    _lastAngle = position.direction;
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final position = details.localPosition - center;
    final currentAngle = position.direction;

    double delta = currentAngle - _lastAngle;

    // Normalize difference for the jump between -pi and pi
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;

    _lastAngle = currentAngle;

    if (delta != 0.0) {
      setState(() {
        _rotationAngle += delta;
      });

      // 1 full turn (2 * pi) is 100,000 Hz (100 kHz)
      // So delta is (delta / (2 * pi)) * 100,000
      double freqDeltaDouble = (delta / (2 * math.pi)) * 100000;
      int freqDelta = freqDeltaDouble.round();
      if (freqDelta != 0) {
        widget.onFrequencyDelta(freqDelta);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final widgetSize = Size(widget.size, widget.size);
    return GestureDetector(
      onPanStart: (details) => _onPanStart(details, widgetSize),
      onPanUpdate: (details) => _onPanUpdate(details, widgetSize),
      child: CustomPaint(
        size: widgetSize,
        painter: _KnobPainter(angle: _rotationAngle),
      ),
    );
  }
}

class _KnobPainter extends CustomPainter {
  final double angle;

  _KnobPainter({required this.angle});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Draw outer textured grippy ring shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center + const Offset(2, 2), radius - 2, shadowPaint);

    // 2. Outer ring (textured metal)
    final outerRingPaint = Paint()
      ..shader = const SweepGradient(
        colors: [
          Color(0xFF2C323D),
          Color(0xFF101318),
          Color(0xFF38404E),
          Color(0xFF2C323D),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, outerRingPaint);

    // 3. Dial Face (Brushed metallic gradient)
    final faceRadius = radius * 0.85;
    final dialFacePaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFF3E4856), Color(0xFF1E232A), Color(0xFF0F1216)],
      ).createShader(Rect.fromCircle(center: center, radius: faceRadius));
    canvas.drawCircle(center, faceRadius, dialFacePaint);

    // Conical sheen effect for brushed metal look
    final sheenPaint = Paint()
      ..shader = const SweepGradient(
        colors: [
          Color(0x00FFFFFF),
          Color(0x1AFFFFFF),
          Color(0x00FFFFFF),
          Color(0x1AFFFFFF),
          Color(0x00FFFFFF),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: faceRadius));
    canvas.drawCircle(center, faceRadius, sheenPaint);

    // 4. Dot Indicator / Finger Dimple
    final dimpleOffset = Offset(
      center.dx + (faceRadius * 0.65) * math.cos(angle),
      center.dy + (faceRadius * 0.65) * math.sin(angle),
    );

    // Inner dimple shadow
    final dimpleShadow = Paint()..color = Colors.black.withValues(alpha: 0.5);
    canvas.drawCircle(
      dimpleOffset + const Offset(0.5, 0.5),
      faceRadius * 0.12,
      dimpleShadow,
    );

    // Inner dimple face
    final dimpleFace = Paint()
      ..color = const Color(0xFF12151B)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(dimpleOffset, faceRadius * 0.12, dimpleFace);

    // Silver/Metallic ring around dimple
    final dimpleBorder = Paint()
      ..color = const Color(0xFF6B7A90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(dimpleOffset, faceRadius * 0.12, dimpleBorder);
  }

  @override
  bool shouldRepaint(covariant _KnobPainter oldDelegate) {
    return oldDelegate.angle != angle;
  }
}
