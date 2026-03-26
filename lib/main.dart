import 'dart:math';

import 'package:flame/components.dart' hide Vector2;
import 'package:flame/game.dart' hide Vector2;
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'falling_block.dart';
import 'overlays.dart';

// Prototype için High Score'u bellekte saklıyoruz (Uygulama kapanana kadar durur).
int globalHighScore = 0;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  globalHighScore = prefs.getInt('globalHighScore') ?? 0;

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
  bool isAvalanching = false;
  double warningTimer = 0.0;
  bool hasDroppedFirstBlock = false;
  final List<Vector2> dockSlots = [
    Vector2(-7, 15),
    Vector2(0, 15),
    Vector2(7, 15),
  ];

  @override
  Color backgroundColor() =>
      Colors.transparent; // Arka planı Flutter widget'ı çizer

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Çarpışma çözücü Hassasiyetini artır (Ezilmeyi önler)
    // Forge2D'de varsayılan 8/3'tür. 10/10 yaparak kuleyi çok daha 'katı' hale getiriyoruz.
    // world.velocityIterations = 10; 
    // world.positionIterations = 10;
    // Not: Forge2D'nin bazı sürümlerinde bunlar doğrudan world'de değil, update içinde set edilir.

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

    refillSlots();
  }

  void addScore(int points) {
    if (isGameOver) return;
    scoreNotifier.value += points;
    syncScoreText();
  }

  void syncScoreText() {
    scoreText.text = 'Score: ${scoreNotifier.value}';
  }

  void refillSlots() {
    if (isGameOver) return;

    final types = TetrominoType.values;

    for (var slotPos in dockSlots) {
      bool isEmpty = true;
      for (var block in world.children.whereType<FallingBlock>()) {
        if (!block.isDropped && block.initialSlotPosition == slotPos) {
          isEmpty = false;
          break;
        }
      }

      if (isEmpty) {
        final randomType = types[Random().nextInt(types.length)];

        double debuffChance = (scoreNotifier.value ~/ 50) * 0.20;
        debuffChance = debuffChance.clamp(0.0, 0.8);

        DebuffType debuff = DebuffType.none;
        if (Random().nextDouble() < debuffChance) {
          debuff = Random().nextBool() ? DebuffType.lead : DebuffType.ice;
        }

        world.add(FallingBlock(type: randomType, initialSlotPosition: slotPos, debuff: debuff));
      }
    }
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('globalHighScore', globalHighScore);
    }

    pauseEngine();
    overlays.add('GameOverOverlay');
  }

  void retry() {
    isGameOver = false;
    isAvalanching = false;
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
      if (component is FallingBlock) {
        component.isDropped = true; // Yeniden doldururken dolu sanmasın diye state hilesi
        component.removeFromParent();
      } else if (component is ParticleSystemComponent) {
        component.removeFromParent();
      }
    }

    // Platformu sıfırla
    platform.body.setTransform(Vector2(0, 6), 0);
    platform.body.angularVelocity = 0;
    platform.body.linearVelocity.setZero();
    platform.body.setType(BodyType.dynamic);

    resumeEngine();
    hasDroppedFirstBlock = false;
    refillSlots();
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

    // Tahta 22 dereceye (0.38 rad) kadar oyuncuya şans tanır.
    if (angleAbs > 0.38 && !isAvalanching) {
      isAvalanching = true;
      platform.body.angularDamping = 0.5; // Kilidi çöz, serbest sallansın
      platform.body.applyAngularImpulse(300.0 * (platform.body.angle > 0 ? 1 : -1));
      
      Vibration.hasVibrator().then((hasVib) {
        if (hasVib == true) Vibration.vibrate(duration: 200, amplitude: 255);
      });
    }

    // Tahta aşırı eğilirse (1.2 radyan ~ 70 derece) Game Over tetiklenir (veya platform boşalınca).
    if (angleAbs > 1.2) {
      triggerGameOver();
    }

    if (hasDroppedFirstBlock) {
      // Platform çok eğildiğinde taşlar dökülürken hemen Game Over olmasın. 
      // Aşağıdaki yer seviyesine (Y=40) yaklaşana kadar (Y=38) tarama yapıyoruz ki dökülüşü tam izleyebilsinler.
      final activeBlocks = world.children.whereType<FallingBlock>().where((b) => b.isDropped && b.body.position.y <= 38.0);
      if (activeBlocks.isEmpty) {
        triggerGameOver();
      }
    }

    double targetGravity = 15.0 + (scoreNotifier.value / 50.0) * 1.5;
    targetGravity = targetGravity.clamp(15.0, 30.0);
    world.gravity.setValues(0, targetGravity);
  }
}

class Ground extends BodyComponent {
  @override
  Body createBody() {
    final shape = PolygonShape()..setAsBox(50.0, 5.0, Vector2.zero(), 0.0);
    final fixtureDef = FixtureDef(shape)..friction = 0.8;
    final bodyDef = BodyDef()
      ..position = Vector2(0, 40.0)
      ..type = BodyType.static;
    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }
}

class PivotPlatform extends BodyComponent {
  final Body groundBody;
  PivotPlatform({required this.groundBody});

  @override
  Body createBody() {
    // Kalınlık 0.5 yapıldı (Toplam 1.0 birim). İnce yüzeylerde 'tunneling' (içinden geçme) sorununu önler.
    final shape = PolygonShape()..setAsBox(8.0, 0.5, Vector2.zero(), 0.0);
    final fixtureDef = FixtureDef(shape)
      ..friction = 1.0
      ..density = 50.0;

    final bodyDef = BodyDef()
      ..position = Vector2(0, 6.3) // Yüksekliği hafifçe aşağı çektik çünkü box kalınlaştı (Yüzey yine ~5.8'de kalsın diye)
      ..angularDamping = 30.0
      ..type = BodyType.dynamic;

    final platformBody = world.createBody(bodyDef)..createFixture(fixtureDef);

    final jointDef = RevoluteJointDef()
      ..initialize(groundBody, platformBody, Vector2(0, 6.0));

    world.createJoint(RevoluteJoint(jointDef));
    return platformBody;
  }

  @override
  void render(Canvas canvas) {
    // Platformun kendi gövdesini (beyaz çubuk) çiz - Fiziksel kalınlık 0.5 (Toplam 1.0)
    final paint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(-8.0, -0.5, 16.0, 1.0), paint);

    // 1010-Stili Görünmez (Şu an görünür) Tahta Izgarası - 22 Kare Genişlik (-11.0 to 11.0)
    final gridLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.05;

    final cellPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;

    // Izgara çizgilerini platformun ÜST YÜZEYİNDEN (-0.5) itibaren başlatıyoruz
    // Dikey Çizgiler
    for (int i = 0; i <= 22; i++) {
        double x = -11.0 + i;
        canvas.drawLine(Offset(x, -0.5), Offset(x, -22.5), gridLinePaint);
    }

    // Yatay Çizgiler
    for (int i = 0; i <= 22; i++) {
        double y = -0.5 - i;
        canvas.drawLine(Offset(-11.0, y), Offset(11.0, y), gridLinePaint);
    }

    // Karelerin içini hafifçe doldurarak "tahta" hissi ver
    for (int x = 0; x < 22; x++) {
      for (int y = 0; y < 22; y++) {
        canvas.drawRect(
          Rect.fromLTWH(-11.0 + x, -1.2 - y, 1.0, 1.0),
          cellPaint,
        );
      }
    }
  }
}
