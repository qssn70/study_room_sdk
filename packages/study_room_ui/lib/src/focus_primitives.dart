import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

const studyFocusAccent = Color(0xFF81C784);
const studyFocusRest = Color(0xFFFFB74D);

class StudyFocusSizing {
  const StudyFocusSizing({
    required this.timerSize,
    required this.coreMaxWidth,
    required this.clusterGap,
    required this.goalGap,
    required this.controlButtonSize,
    required this.controlGap,
  });

  final double timerSize;
  final double coreMaxWidth;
  final double clusterGap;
  final double goalGap;
  final double controlButtonSize;
  final double controlGap;

  factory StudyFocusSizing.fromConstraints(
    BoxConstraints constraints, {
    required bool landscape,
  }) {
    final width = _finiteDimension(constraints.maxWidth, fallback: 390);
    final height = _finiteDimension(constraints.maxHeight, fallback: 844);
    final timerSize = landscape
        ? math.min(width * 0.25, height * 0.48).clamp(176.0, 380.0).toDouble()
        : math.min(width * 0.58, height * 0.32).clamp(220.0, 340.0).toDouble();
    final scale = (timerSize / 220).clamp(0.85, 1.25).toDouble();

    return StudyFocusSizing(
      timerSize: timerSize,
      coreMaxWidth: math
          .max(342.0, timerSize + 96)
          .clamp(342.0, 520.0)
          .toDouble(),
      clusterGap: 24 * scale,
      goalGap: 32 * scale,
      controlButtonSize: 56 * scale,
      controlGap: 24 * scale,
    );
  }

  static double _finiteDimension(double value, {required double fallback}) {
    if (!value.isFinite || value <= 0) {
      return fallback;
    }
    return value;
  }
}

class StudyFocusGlassPanel extends StatelessWidget {
  const StudyFocusGlassPanel({
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.padding = const EdgeInsets.all(14),
    super.key,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            borderRadius: borderRadius,
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
