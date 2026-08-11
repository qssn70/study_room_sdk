import 'package:flutter/material.dart';

class StudyBackgroundOption {
  const StudyBackgroundOption({
    required this.id,
    required this.label,
    required this.background,
  });

  final String id;
  final String label;
  final StudyBackground background;

  static const builtIns = <StudyBackgroundOption>[
    StudyBackgroundOption(
      id: 'midnight',
      label: '深夜',
      background: StudyBackground.color(Color(0xFF16231E), maskOpacity: 0.3),
    ),
    StudyBackgroundOption(
      id: 'forest',
      label: '森林',
      background: StudyBackground.gradient(
        colors: [Color(0xFF18392B), Color(0xFF101A2A)],
        maskOpacity: 0.28,
      ),
    ),
  ];
}

const studyFocusDefaultBackground = StudyBackground.gradient(
  colors: [Color(0xFF10241D), Color(0xFF17263A), Color(0xFF241B35)],
  maskOpacity: 0.2,
);

enum StudyBackgroundType { color, image, gradient }

class StudyBackground {
  const StudyBackground.color(Color color, {double maskOpacity = 0.35})
    : this._(
        type: StudyBackgroundType.color,
        color: color,
        maskOpacity: maskOpacity,
      );

  const StudyBackground.image({
    required ImageProvider image,
    double maskOpacity = 0.45,
  }) : this._(
         type: StudyBackgroundType.image,
         image: image,
         maskOpacity: maskOpacity,
       );

  const StudyBackground.gradient({
    required List<Color> colors,
    double maskOpacity = 0.35,
  }) : this._(
         type: StudyBackgroundType.gradient,
         gradientColors: colors,
         maskOpacity: maskOpacity,
       );

  const StudyBackground._({
    required this.type,
    this.color,
    this.image,
    this.gradientColors = const [],
    double maskOpacity = 0.35,
  }) : maskOpacity = maskOpacity < 0
           ? 0
           : maskOpacity > 0.85
           ? 0.85
           : maskOpacity;

  final StudyBackgroundType type;
  final Color? color;
  final ImageProvider? image;
  final List<Color> gradientColors;
  final double maskOpacity;

  StudyBackground withMaskOpacity(double maskOpacity) {
    return StudyBackground._(
      type: type,
      color: color,
      image: image,
      gradientColors: gradientColors,
      maskOpacity: maskOpacity,
    );
  }
}

class StudyBackgroundLayer extends StatelessWidget {
  const StudyBackgroundLayer({
    required this.background,
    required this.child,
    super.key,
  });

  final StudyBackground background;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(child: _background()),
        ExcludeSemantics(
          child: ColoredBox(
            color: Colors.black.withValues(alpha: background.maskOpacity),
          ),
        ),
        child,
      ],
    );
  }

  Widget _background() {
    if (background.type == StudyBackgroundType.image &&
        background.image != null) {
      return Image(
        image: background.image!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const ColoredBox(color: Color(0xFF16231E));
        },
      );
    }
    return DecoratedBox(decoration: _decoration());
  }

  BoxDecoration _decoration() {
    return switch (background.type) {
      StudyBackgroundType.color => BoxDecoration(
        color: background.color ?? const Color(0xFFF6F7F9),
      ),
      StudyBackgroundType.image => const BoxDecoration(
        color: Color(0xFF16231E),
      ),
      StudyBackgroundType.gradient => BoxDecoration(
        gradient: LinearGradient(
          colors: background.gradientColors.isEmpty
              ? const [Color(0xFFF6F7F9), Colors.white]
              : background.gradientColors,
        ),
      ),
    };
  }
}

class BackgroundSettingsView extends StatelessWidget {
  const BackgroundSettingsView({required this.background, super.key});

  final StudyBackground background;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Row(
        children: [
          _BackgroundSwatch(background: background),
          const SizedBox(width: 12),
          Expanded(
            child: Slider(value: background.maskOpacity, onChanged: null),
          ),
        ],
      ),
    );
  }
}

class _BackgroundSwatch extends StatelessWidget {
  const _BackgroundSwatch({required this.background});

  final StudyBackground background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
        color: background.color,
        gradient: background.type == StudyBackgroundType.gradient
            ? LinearGradient(colors: background.gradientColors)
            : null,
        image: background.image == null
            ? null
            : DecorationImage(image: background.image!, fit: BoxFit.cover),
      ),
    );
  }
}
