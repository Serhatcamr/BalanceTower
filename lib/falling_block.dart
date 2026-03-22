import 'dart:math';

import 'package:flame/events.dart';
import 'package:flame/components.dart' hide Vector2;
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import 'main.dart';

enum TetrominoType { I, O, T, S, Z, L, J }

enum DebuffType { none, lead, ice }

/// Düşen Tetris bloklarını temsil eden BodyComponent
class FallingBlock extends BodyComponent<BalanceTowerGame>
    with TapCallbacks, DragCallbacks, ContactCallbacks {
  final TetrominoType type;
  DebuffType debuff;

  bool isDropped = false;
  bool hasScored = false;

  late final List<Vector2> squares;
  late final Color originalColor;
  late Color color;

  FallingBlock({required this.type, this.debuff = DebuffType.none}) {
    _initSquaresAndColor();
  }

  void _initSquaresAndColor() {
    switch (type) {
      case TetrominoType.I:
        squares = [
          Vector2(-1.5, 0),
          Vector2(-0.5, 0),
          Vector2(0.5, 0),
          Vector2(1.5, 0)
        ];
        originalColor = const Color(0xFF00E5FF);
        break;
      case TetrominoType.O:
        squares = [
          Vector2(-0.5, -0.5),
          Vector2(0.5, -0.5),
          Vector2(-0.5, 0.5),
          Vector2(0.5, 0.5)
        ];
        originalColor = const Color(0xFFFFEA00);
        break;
      case TetrominoType.T:
        squares = [
          Vector2(-1.0, 0),
          Vector2(0, 0),
          Vector2(1.0, 0),
          Vector2(0, -1.0)
        ];
        originalColor = const Color(0xFFD500F9);
        break;
      case TetrominoType.S:
        squares = [
          Vector2(-1.0, 0),
          Vector2(0, 0),
          Vector2(0, -1.0),
          Vector2(1.0, -1.0)
        ];
        originalColor = const Color(0xFF00E676);
        break;
      case TetrominoType.Z:
        squares = [
          Vector2(-1.0, -1.0),
          Vector2(0, -1.0),
          Vector2(0, 0),
          Vector2(1.0, 0)
        ];
        originalColor = const Color(0xFFFF1744);
        break;
      case TetrominoType.L:
        squares = [
          Vector2(-1.0, 0),
          Vector2(0, 0),
          Vector2(1.0, 0),
          Vector2(1.0, -1.0)
        ];
        originalColor = const Color(0xFFFF9100);
        break;
      case TetrominoType.J:
        squares = [
          Vector2(-1.0, -1.0),
          Vector2(-1.0, 0),
          Vector2(0, 0),
          Vector2(1.0, 0)
        ];
        originalColor = const Color(0xFF2979FF);
        break;
    }

    // Hastalık durumuna göre rengi kilitle
    if (debuff == DebuffType.lead) {
      color = const Color(0xFF4A148C); // Koyu gri/mor - Kurşun Virüsü
    } else if (debuff == DebuffType.ice) {
      color = const Color(0xFF80D8FF); // Açık buz mavisi - Buzlanma
    } else {
      color = originalColor;
    }
  }

  @override
  Body createBody() {
    final bodyDef = BodyDef()
      ..position = Vector2(0, -15.0)
      ..type = BodyType.kinematic;

    final body = world.createBody(bodyDef);

    for (var squareCenter in squares) {
      final shape = PolygonShape()..setAsBox(0.48, 0.48, squareCenter, 0);

      double friction = 0.8;
      double density = 1.0;

      // Hastalıkların Fixture seviyesinde fiziksel etkileri
      if (debuff == DebuffType.lead) {
        density = 3.0; // 3 katı yoğun, çok ağır
      } else if (debuff == DebuffType.ice) {
        friction = 0.05; // Sabun gibi kaygan, tutunmak imkansız
      }

      final fixtureDef = FixtureDef(shape)
        ..friction = friction
        ..restitution = 0.1
        ..density = density;

      body.createFixture(fixtureDef);
    }

    return body;
  }

  void cure() {
    if (debuff == DebuffType.none) return;

    debuff = DebuffType.none;
    color = originalColor;

    for (var fixture in body.fixtures) {
      fixture.friction = 0.8;
      fixture.density = 1.0;
    }
    body.resetMassData();
  }

  @override
  void render(Canvas canvas) {
    if (body.fixtures.isEmpty) return;

    final paint = Paint()..color = color;
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.05;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    for (var square in squares) {
      final rect = Rect.fromCenter(
        center: Offset(square.x, square.y),
        width: 1.0,
        height: 1.0,
      );

      final visualRect = rect.deflate(0.04);
      final rrect =
          RRect.fromRectAndRadius(visualRect, const Radius.circular(0.15));

      canvas.drawRRect(rrect.shift(const Offset(0.05, 0.05)), shadowPaint);
      canvas.drawRRect(rrect, paint);
      canvas.drawRRect(rrect, highlightPaint);

      // Hastalık efekti olarak üzerlerine ufak bir görsel eklenti
      if (debuff == DebuffType.ice) {
        final iceOverlay = Paint()
          ..color = Colors.white.withValues(alpha: 0.3)
          ..style = PaintingStyle.fill;
        canvas.drawRRect(rrect.deflate(0.1), iceOverlay);
      }
    }
  }

  @override
  void update(double dt) {
    if (game.isGameOver) return;
    super.update(dt);

    // Blok çok aşağı yönde düşerse Oyun Biter (Kule yıkılması kontrolü)
    if (isDropped && body.position.y > 25.0) {
      game.triggerGameOver();
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (game.isGameOver) return;

    if (game.antidoteActiveNotifier.value && debuff != DebuffType.none) {
      cure();
      game.antidoteActiveNotifier.value = false;
      return;
    }

    if (!isDropped) {
      body.setTransform(body.position, body.angle + pi / 2);
    }
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (!isDropped && !game.isGameOver) {
      final dx = event.canvasDelta.x / game.camera.viewfinder.zoom;
      body.setTransform(body.position + Vector2(dx, 0), body.angle);
    }
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (!isDropped && !game.isGameOver) {
      isDropped = true;
      body.setType(BodyType.dynamic);
    }
  }

  @override
  void beginContact(Object other, Contact contact) {
    if (!hasScored && isDropped && !game.isGameOver) {
      // Çarpışma parçacıkları (Particles - Cila)
      _spawnParticles();

      if (other is PivotPlatform || other is Ground || other is FallingBlock) {
        hasScored = true;
        game.addScore(squares.length);

        // Haptic Feedback (Hafif çarpışma - Cila)
        Vibration.hasVibrator().then((hasVib) {
          if (hasVib == true) Vibration.vibrate(duration: 15, amplitude: 50);
        });
      }
    }
  }

  void _spawnParticles() {
    final rnd = Random();
    final parts = List.generate(10, (i) {
      final size = 0.3 * rnd.nextDouble();
      // Y,X parameters from Dart's internal double representation bypass the strict class
      final vx = (rnd.nextDouble() - 0.5) * 15;
      final vy = (rnd.nextDouble() - 0.8) * 10;
      final px = body.position.x;
      final py = body.position.y;
      final rcolor = color;
      
      return TimerComponent(
        period: 0.6,
        removeOnFinish: true,
        onTick: () {},
      )..add(
        _CustomParticle(
          vx: vx,
          vy: vy,
          px: px,
          py: py,
          sizeVal: size,
          col: rcolor,
        )
      );
    });
    
    for (var p in parts) {
      game.world.add(p);
    }
  }
}

class _CustomParticle extends PositionComponent {
  double vx;
  double vy;
  double px;
  double py;
  double sizeVal;
  Color col;
  double age = 0;
  final double maxAge = 0.6;

  _CustomParticle({
    required this.vx,
    required this.vy,
    required this.px,
    required this.py,
    required this.sizeVal,
    required this.col,
  }) {
    position.setValues(px, py);
    size.setValues(sizeVal, sizeVal);
  }

  @override
  void update(double dt) {
    super.update(dt);
    age += dt;
    vy += 15 * dt; // Gravity
    position.x += vx * dt;
    position.y += vy * dt;
    if (age >= maxAge) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    if (age >= maxAge) return;
    double progress = age / maxAge;
    
    canvas.drawRect(
      Rect.fromLTWH(0, 0, sizeVal, sizeVal),
      Paint()..color = col.withValues(alpha: (1 - progress).clamp(0.0, 1.0)),
    );
  }
}
