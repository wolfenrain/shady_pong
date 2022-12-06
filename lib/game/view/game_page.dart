import 'dart:async';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shady_pong/game/game.dart';

class GamePage extends StatelessWidget {
  const GamePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: GameView());
  }
}

class GameView extends StatefulWidget {
  const GameView({super.key});

  @override
  State<GameView> createState() => _GameViewState();
}

class _GameViewState extends State<GameView> {
  late final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;

  double lightPositionX = 0.5;
  double lightPositionY = 0.7;
  double shadow = 0.2;

  bool paused = true;
  bool showMemory = false;
  double aiSpeed = 0.5;

  Color backgroundColor = const ui.Color(0xFF543B24);

  int fps = 60;
  double delta = 0;
  Timer? timer;

  Future<ui.FragmentProgram>? _program;
  FragmentShader? shader;

  @override
  void initState() {
    super.initState();

    _program = ui.FragmentProgram.fromAsset('shaders/shady_pong.glsl');

    /// Represents the minimum time between frames.
    final milliseconds = ((1 / fps) * 1000).toInt();

    // The Timer is used to simulate a game loop. A better approach would be to
    // use Flame and have it handle the game loop for you.
    timer = Timer.periodic(Duration(milliseconds: milliseconds), (_) {
      setState(() => delta = 1 / fps);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Text monospaced(String text) {
    return Text(
      text,
      style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
    );
  }

  Widget buildLightControls() {
    return IntrinsicWidth(
      child: Column(
        children: [
          Row(
            children: [
              monospaced('Light X'),
              const Spacer(),
              Slider(
                thumbColor: Colors.black,
                activeColor: Colors.black.withOpacity(shadow),
                inactiveColor: Colors.grey,
                value: lightPositionX,
                onChanged: (v) => setState(() => lightPositionX = v),
              ),
              monospaced(lightPositionX.toStringAsFixed(2)),
            ],
          ),
          Row(
            children: [
              monospaced('Light Y'),
              const Spacer(),
              Slider(
                thumbColor: Colors.black,
                activeColor: Colors.black.withOpacity(shadow),
                inactiveColor: Colors.grey,
                value: lightPositionY,
                onChanged: (v) => setState(() => lightPositionY = v),
              ),
              monospaced(lightPositionY.toStringAsFixed(2)),
            ],
          ),
          Row(
            children: [
              monospaced('Shadow Strength'),
              const Spacer(),
              Slider(
                thumbColor: Colors.black,
                activeColor: Colors.black.withOpacity(shadow),
                inactiveColor: Colors.grey,
                value: shadow,
                onChanged: (v) => setState(() => shadow = v),
              ),
              monospaced(shadow.toStringAsFixed(2)),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildColorControls() {
    return IntrinsicWidth(
      child: Column(
        children: [
          Row(
            children: [
              monospaced('Red'),
              const Spacer(),
              Slider(
                thumbColor: backgroundColor,
                activeColor: backgroundColor.withOpacity(0.5),
                inactiveColor: backgroundColor.withOpacity(0.25),
                value: backgroundColor.red / 255,
                onChanged: (v) => setState(() {
                  backgroundColor = backgroundColor.withRed((v * 255).round());
                }),
              ),
              monospaced((backgroundColor.red / 255).toStringAsFixed(2)),
            ],
          ),
          Row(
            children: [
              monospaced('Green'),
              const Spacer(),
              Slider(
                thumbColor: backgroundColor,
                activeColor: backgroundColor.withOpacity(0.5),
                inactiveColor: backgroundColor.withOpacity(0.25),
                value: backgroundColor.green / 255,
                onChanged: (v) => setState(() {
                  backgroundColor = backgroundColor.withGreen(
                    (v * 255).round(),
                  );
                }),
              ),
              monospaced((backgroundColor.green / 255).toStringAsFixed(2)),
            ],
          ),
          Row(
            children: [
              monospaced('Blue'),
              const Spacer(),
              Slider(
                thumbColor: backgroundColor,
                activeColor: backgroundColor.withOpacity(0.5),
                inactiveColor: backgroundColor.withOpacity(0.25),
                value: backgroundColor.blue / 255,
                onChanged: (v) => setState(() {
                  backgroundColor = backgroundColor.withBlue((v * 255).round());
                }),
              ),
              monospaced((backgroundColor.blue / 255).toStringAsFixed(2)),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildExtra() {
    return IntrinsicWidth(
      child: Column(
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              monospaced('Pause Game'),
              const Spacer(),
              Checkbox(
                fillColor: MaterialStatePropertyAll(backgroundColor),
                value: paused,
                onChanged: (v) => setState(() => paused = v!),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              monospaced('Show memory'),
              const Spacer(),
              Checkbox(
                fillColor: MaterialStatePropertyAll(backgroundColor),
                value: showMemory,
                onChanged: (v) => setState(() => showMemory = v!),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              monospaced('AI Speed'),
              const Spacer(),
              Slider(
                thumbColor: Colors.black,
                activeColor: Colors.black.withOpacity(shadow),
                inactiveColor: Colors.grey,
                value: aiSpeed,
                onChanged: (v) => setState(() => aiSpeed = v),
              ),
              monospaced(aiSpeed.toStringAsFixed(2)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [buildLightControls(), buildExtra(), buildColorControls()],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraint) {
              return FutureBuilder<FragmentProgram>(
                future: _program,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.expand();
                  shader ??= snapshot.data!.fragmentShader();

                  return FrameSampler(
                    showMemory: showMemory,
                    paused: paused,
                    // The child is a black box because the shader draw
                    // everything with the alpha channel set to 0 unless the
                    // pixel is a memory pixel.
                    //
                    // By using the black color (0, 0, 0, 1) we can xor the
                    // the pixels to make the memory pixels invisible and the
                    // transparent pixels visible.
                    //
                    // Allowing us to store the game state in the alpha channel
                    // of certain pixels.
                    child: const SizedBox.expand(
                      child: ColoredBox(color: Colors.black),
                    ),
                    (Canvas canvas, ui.Image memory) {
                      final size = constraint.biggest;

                      final devicePixelRatio = this.devicePixelRatio;
                      shader!
                        // Setting the size.
                        ..setFloat(0, size.width / devicePixelRatio)
                        ..setFloat(1, size.height / devicePixelRatio)
                        // Setting the light position.
                        ..setFloat(2, lightPositionX)
                        ..setFloat(3, lightPositionY)
                        // Setting the shadow color.
                        ..setFloat(4, 0)
                        ..setFloat(5, 0)
                        ..setFloat(6, 0)
                        ..setFloat(7, shadow)
                        // Setting the background color.
                        ..setFloat(8, backgroundColor.red / 255)
                        ..setFloat(9, backgroundColor.green / 255)
                        ..setFloat(10, backgroundColor.blue / 255)
                        // Setting the delta time.
                        ..setFloat(11, delta)
                        // Setting the AI speed.
                        ..setFloat(12, aiSpeed)
                        // Setting the memory sampler.
                        // NOTE: this is currently a massive memory leak.
                        ..setImageSampler(0, memory);

                      canvas.drawRect(
                        Offset.zero & size,
                        Paint()..shader = shader,
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
