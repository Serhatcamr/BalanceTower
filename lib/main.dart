import 'dart:math';

import 'package:flame/components.dart' hide Vector2;
import 'package:flame/game.dart' hide Vector2;
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import 'falling_block.dart';
import 'overlays.dart';

// Prototype için High Score'u bellekte saklıyoruz (Uygulama kapanana kadar durur).
int globalHighScore = 0;

void main() {
  final gameInstance = BalanceTowerGame();

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
        // iOS Tarzı Dinamik Arka Plan
        body: ValueListenableBuilder<int>(
          valueListenable: gameInstance.scoreNotifier,
          builder: (context, score, child) {
            // Skor 0 iken Gündüz (1.0), Skor 200 iken Gece (0.0) -> Akşam oluyor hissi
            double transition = 1.0 - (score / 200.0).clamp(0.0, 1.0);

            // Gündüz Renkleri (#F5F7FA -> #B8C6DB)
            Color dayTop = const Color(0xFFF5F7FA);
            Color dayBottom = const Color(0xFFB8C6DB);

            // Gece Renkleri (Koyu iOS Grisi/Lacivert)
            Color nightTop = const Color(0xFF1C1C1E);
            Color nightBottom = const Color(0xFF2C2C2E);

            return AnimatedContainer(
              duration: const Duration(seconds: 1),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(nightTop, dayTop, transition)!,
                    Color.lerp(nightBottom, dayBottom, transition)!,
                  ],
                ),
              ),
              child: child,
            );
          },
          child: GameWidget<BalanceTowerGame>(
            game: gameInstance,
            overlayBuilderMap: {
              'MarketOverlay': (context, game) => MarketOverlay(game: game),
              'GyroOverlay': (context, game) => GyroOverlay(game: game),
              'ActiveAugmentTimers': (context, game) =>
                  ActiveAugmentTimers(game: game),
              'AntidoteOverlay': (context, game) => AntidoteOverlay(game: game),
              'GameOverOverlay': (context, game) => GameOverOverlay(game: game),
            },
            initialActiveOverlays: const [
              'MarketOverlay',
              'GyroOverlay',
              'ActiveAugmentTimers',
              'AntidoteOverlay'
            ],
          ),
        ),
      ),
    ),
  );
}

/// Oyunun ana sınıfı. Forge2DGame'den türer ve yerçekimini ayarlar.
class BalanceTowerGame extends Forge2DGame {
  BalanceTowerGame() : super(gravity: Vector2(0, 15.0));

  final ValueNotifier<int> scoreNotifier = ValueNotifier(0);
  final ValueNotifier<double> platformAngleNotifier = ValueNotifier(0.0);
  final ValueNotifier<bool> gyroActiveNotifier = ValueNotifier(false);

  final ValueNotifier<double> freezeTimerNotifier = ValueNotifier(0.0);
  final ValueNotifier<double> gyroTimerNotifier = ValueNotifier(0.0);
  final ValueNotifier<bool> antidoteActiveNotifier = ValueNotifier(false);

  late PivotPlatform platform;
  late TextComponent scoreText;

  bool isGameOver = false;
  double warningTimer = 0.0;

  @override
  Color backgroundColor() =>
      Colors.transparent; // Arka planı Flutter widget'ı çizer

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    camera.viewfinder.position.setZero();
    camera.viewfinder.zoom = 15.0;

    final ground = Ground();
    await world.add(ground);

    platform = PivotPlatform(groundBody: ground.body);
    await world.add(platform);

    scoreText = TextComponent(
      text: 'Score: 0',
      textRenderer: TextPaint(
        style: const TextStyle(
          fontSize: 24,
          color: Colors.white,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
        ),
      ),
    );
    scoreText.position.setValues(20, 50);
    camera.viewport.add(scoreText);

    spawnNewBlock();
  }

  void addScore(int points) {
    if (isGameOver) return;
    scoreNotifier.value += points;
    syncScoreText();

    Future.delayed(const Duration(milliseconds: 500), () {
      if (!isGameOver) spawnNewBlock();
    });
  }

  void syncScoreText() {
    scoreText.text = 'Score: ${scoreNotifier.value}';
  }

  void spawnNewBlock() {
    if (isGameOver) return;

    final types = TetrominoType.values;
    final randomType = types[Random().nextInt(types.length)];

    double debuffChance = (scoreNotifier.value ~/ 50) * 0.20;
    debuffChance = debuffChance.clamp(0.0, 0.8);

    DebuffType debuff = DebuffType.none;
    if (Random().nextDouble() < debuffChance) {
      debuff = Random().nextBool() ? DebuffType.lead : DebuffType.ice;
    }

    world.add(FallingBlock(type: randomType, debuff: debuff));
  }

  void activateFreeze() {
    freezeTimerNotifier.value = 10.0;
    platform.body.setType(BodyType.kinematic);
    platform.body.angularVelocity = 0;
  }

  void activateGyro() {
    gyroTimerNotifier.value = 15.0;
    gyroActiveNotifier.value = true;
  }

  void activateAntidote() {
    antidoteActiveNotifier.value = true;
  }

  Future<void> triggerGameOver() async {
    if (isGameOver) return;
    isGameOver = true;

    // Şiddetli Oyun Sonu Titreşimi
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 500, amplitude: 255);
    }

    if (scoreNotifier.value > globalHighScore) {
      globalHighScore = scoreNotifier.value;
    }

    pauseEngine();
    overlays.add('GameOverOverlay');
  }

  void retry() {
    isGameOver = false;
    scoreNotifier.value = 0;
    syncScoreText();

    freezeTimerNotifier.value = 0.0;
    gyroTimerNotifier.value = 0.0;
    gyroActiveNotifier.value = false;
    antidoteActiveNotifier.value = false;

    overlays.remove('GameOverOverlay');

    // Dünyadaki tüm nesneleri (bloklar & parçacıklar) temizle
    final components = world.children.toList();
    for (var component in components) {
      if (component is FallingBlock || component is ParticleSystemComponent) {
        component.removeFromParent();
      }
    }

    // Platformu sıfırla
    platform.body.setTransform(Vector2(0, 10), 0);
    platform.body.angularVelocity = 0;
    platform.body.linearVelocity.setZero();
    platform.body.setType(BodyType.dynamic);

    resumeEngine();
    spawnNewBlock();
  }

  @override
  void update(double dt) async {
    if (isGameOver) return;
    super.update(dt);

    if (gyroActiveNotifier.value) {
      platformAngleNotifier.value = platform.body.angle;
      gyroTimerNotifier.value -= dt;
      if (gyroTimerNotifier.value <= 0) {
        gyroActiveNotifier.value = false;
      }
    }

    if (freezeTimerNotifier.value > 0) {
      freezeTimerNotifier.value -= dt;
      if (freezeTimerNotifier.value <= 0) {
        platform.body.setType(BodyType.dynamic);
      }
    }

    // --- OYUN BİTİŞ KONTROLLERİ VE HAPTIC UYARI ---
    double angleAbs = platform.body.angle.abs();

    // 30 dereceyi aştıysa (~0.52 rad) tehlike titreşimleri başlar
    if (angleAbs > 0.52 && angleAbs <= (pi / 4)) {
      warningTimer += dt;
      if (warningTimer > 0.4) {
        Vibration.hasVibrator().then((hasVib) {
          if (hasVib == true) Vibration.vibrate(duration: 30, amplitude: 150);
        });
        warningTimer = 0.0;
      }
    } else {
      warningTimer = 0.0;
    }

    // 45 dereceyi (%45 = pi/4 radyan) geçerse Game Over!
    if (angleAbs > (pi / 4)) {
      triggerGameOver();
    }

    double targetGravity = 15.0 + (scoreNotifier.value / 50.0) * 1.5;
    targetGravity = targetGravity.clamp(15.0, 30.0);
    world.gravity.setValues(0, targetGravity);
  }
}

class Ground extends BodyComponent {
  @override
  Body createBody() {
    final shape = PolygonShape()..setAsBox(50.0, 2.0, Vector2.zero(), 0.0);
    final fixtureDef = FixtureDef(shape)..friction = 0.5;
    final bodyDef = BodyDef()
      ..position = Vector2(0, 30.0)
      ..type = BodyType.static;
    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }
}

class PivotPlatform extends BodyComponent {
  final Body groundBody;
  PivotPlatform({required this.groundBody});

  @override
  Body createBody() {
    final shape = PolygonShape()..setAsBox(6.0, 0.2, Vector2.zero(), 0.0);
    final fixtureDef = FixtureDef(shape)
      ..friction = 0.8
      ..density = 10.0;

    final bodyDef = BodyDef()
      ..position = Vector2(0, 10.0)
      ..type = BodyType.dynamic;

    final platformBody = world.createBody(bodyDef)..createFixture(fixtureDef);

    final jointDef = RevoluteJointDef()
      ..initialize(groundBody, platformBody, Vector2(0, 10.0));

    world.createJoint(RevoluteJoint(jointDef));
    return platformBody;
  }
}
