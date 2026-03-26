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
  final Vector2 initialSlotPosition;
  DebuffType debuff;
  late Paint paint;
  bool isDropped = false;
  bool hasScored = false;
  bool _dragged = false;
  Vector2 _virtualPosition = Vector2.zero();
  double _droppedTime = 0.0;
  late final List<Vector2> squares;
  late final Color originalColor;
  late Color color;

  FallingBlock({required this.type, required this.initialSlotPosition, this.debuff = DebuffType.none}) {
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
      ..position = initialSlotPosition
      // Ağırlık sönümleme: Yüksek istiflerde titremeyi ve ezilmeyi durdurur.
      ..angularDamping = 5.0
      ..linearDamping = 1.0
      ..type = BodyType.kinematic;

    final body = world.createBody(bodyDef);

    for (var squareCenter in squares) {
      // 0.450 yapıldı. Daha fazla boşluk (buffer) bırakarak üst üste binen blokların birbirini 'ezmesini' engelliyoruz.
      // Bu sayede bloklar sıkışmak yerine birbirlerinin üzerinden kayabilirler.
      final shape = PolygonShape()..setAsBox(0.450, 0.450, squareCenter, 0);

      double friction = 0.26; // Blokların tam 15 derecede kaymaya başlaması için çok hassas oranlandı (tan(15)=-0.26)
      double density = 0.1; // ÇOK HAFİF yapıldı (1.0 -> 0.1). Kule yükseldiğinde alttaki taşların 'ezilip' titremesini önler.

      // Hastalıkların Fixture seviyesinde fiziksel etkileri
      if (debuff == DebuffType.lead) {
        density = 3.0; // 3 katı yoğun, çok ağır
      } else if (debuff == DebuffType.ice) {
        friction = 0.05; // Sabun gibi kaygan, tutunmak imkansız
      }

      final fixtureDef = FixtureDef(shape)
        ..friction = friction
        ..restitution = 0.0
        ..density = 1.0
        ..isSensor = true; // Sürüklerken platforma çarpmasın (Ghost modu)

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

      final visualRect = rect.deflate(0.0);
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

  double _rotationOffset = 0;

  @override
  void update(double dt) {
    if (game.isGameOver) return;
    super.update(dt);

    if (!isDropped) {
      // Sürüklenirken platformun açısını kopyala ki tam açıyla otursun
      if (_dragged) {
        body.setTransform(body.position, game.platform.body.angle + _rotationOffset);
      } else {
        body.setTransform(body.position, _rotationOffset);
      }
    } else {
      _droppedTime += dt;
      // Düşen bloklar sonsuza kadar birikmesin, 5 sn sonra erisin (y-limit 30.0)
      if (_droppedTime > 5.0 && body.position.y > 30.0) {
        removeFromParent();
      }

      // 1. Kule tamamen döküldüyse (Platform boş kaldıysa) oyunu bitir (Haksızlığı önle)
      if (game.hasDroppedFirstBlock && !game.isAvalanching && !game.isGameOver) {
        bool blocksOnPlatform = world.children.any((c) => 
          c is FallingBlock && c.isDropped && c.body.position.y < 30.0
        );
        if (!blocksOnPlatform) {
          game.triggerGameOver();
          return;
        }
      }

      // 2. 'Sanal Tahta' (1010): Eğim < 15 derece ve blok platformun ÜSTÜNDEYSE toplu durur.
      final localPos = game.platform.body.localPoint(body.position);
      double angleAbs = game.platform.body.angle.abs();
      
      // DESTEK KONTROLÜ (Denge): Blok sadece ağırlık merkezi (karelerin ortalaması) platform üzerindeyse kilitli kalır.
      double sumLocalX = 0;
      int rotationSteps = (_rotationOffset / (pi / 2)).round();
      int steps = (rotationSteps % 4 + 4) % 4;

      for (var sq in squares) {
          double sx = sq.x, sy = sq.y;
          for (int i = 0; i < steps; i++) {
              double t = sx;
              sx = -sy;
              sy = t;
          }
          final sqLocal = localPos + Vector2(sx, sy);
          sumLocalX += sqLocal.x;
      }
      
      double averageLocalX = sumLocalX / squares.length;
      // Denge Sınırı: Ağırlık merkezi platformun (16 birim) dışındaysa takla başlar.
      bool isBalanced = averageLocalX.abs() <= 8.0;

      if (angleAbs < 0.26 && isBalanced) {
          // PLATFORM ÜSTÜNDEYİZ VE DENGEDEYİZ: Dik durmaya 'çalış' (Yumuşak yaklaşım)
          double targetAngle = game.platform.body.angle + _rotationOffset;
          double angleDiff = targetAngle - body.angle;
          while (angleDiff > pi) angleDiff -= 2 * pi;
          while (angleDiff < -pi) angleDiff += 2 * pi;
          body.angularVelocity = angleDiff * 6.0;

          // HIZ KONTROLLÜ YERLEŞİM (Settling Snap): 
          // Taş hareket halindeyken mıknatıs KAPALI, sadece durunca 'Cuk' diye yerine oturur.
          double linearSpeed = body.linearVelocity.length;
          
          if (linearSpeed < 0.3) {
              double sqX = squares[0].x;
              double sqY = squares[0].y;
          int steps = (rotationSteps % 4 + 4) % 4;
          for (int i = 0; i < steps; i++) {
              double temp = sqX;
              sqX = -sqY;
              sqY = temp;
          }
          double rem = (sqX.abs() % 1.0);
          double fractionalOffset = (rem < 0.25 || rem > 0.75) ? 0.5 : 0.0;
          double snappedLocalX = (localPos.x - fractionalOffset).roundToDouble() + fractionalOffset;

          // Sınır koruması (22 birimlik genişlik kılavuzuna göre)
          double minX = 100, maxX = -100;
          for (var sq in squares) {
            double sx = sq.x, sy = sq.y;
            for (int i = 0; i < steps; i++) {
              double t = sx;
              sx = -sy;
              sy = t;
            }
            if (sx < minX) minX = sx;
            if (sx > maxX) maxX = sx;
          }
          double maxAllowedX = 11.0 - (maxX + 0.5);
          double minAllowedX = -11.0 - (minX - 0.5);
          snappedLocalX = snappedLocalX.clamp(minAllowedX, maxAllowedX);

          // EZİLMEYİ ÖNLE: Magnet yüksekliği asla platform yüzeyinin (~ -0.5) altına inemez.
          double snappedLocalY = localPos.y.clamp(-25.0, -0.6); // 0.1 buffer

          final targetWorldPos = game.platform.body.worldPoint(Vector2(snappedLocalX, snappedLocalY));
          final diff = targetWorldPos - body.position;
          
          double dist = diff.length;
          double forceMagnitude = dist < 0.15 ? 70.0 : (dist < 0.4 ? 20.0 : 2.0);

          // EZİLMEYİ (Overlap) ÖNLEME: Hedef kare eğer başka bir blok tarafından işgal edildiyse Mıknatısı KAPAT.
          bool isOccupied = false;
          final otherBlocks = world.children.whereType<FallingBlock>().where((b) => b != this && b.isDropped);
          for (final ob in otherBlocks) {
              if (ob.containsPoint(targetWorldPos)) {
                  isOccupied = true;
                  break;
              }
          }

              if (!isOccupied) {
                  body.applyForce(diff * body.mass * forceMagnitude); 
              }
              body.linearDamping = 4.0; 
          } else {
              body.linearDamping = 0.5; // Hareket halindeyken serbest kayma
          } 
      } else {
          // KENARDAN DÜŞÜYORUZ VEYA ÇIĞ BAŞLADI: Gerçek fizik (takla/devrilme) başlar!
          if (game.isAvalanching) {
            // ÇIĞ SIRASINDA: Taşlar 'sabun' gibi kaysınlar (Hızlı dökülme için)
            body.angularDamping = 0.1;
            body.linearDamping = 0.1;
            for (var f in body.fixtures) {
              f.friction = 0.0;
            }
          }
      }
    }
  }

  @override
  bool containsPoint(Vector2 point) {
    if (super.containsPoint(point)) return true;
    
    if (!isDropped && isMounted) {
      // Yuvadayken vurmayı kolaylaştıran 3 birimlik yarıçapında dev görünmez pencere
      return point.distanceTo(body.position) < 3.0;
    }
    return false;
  }

  @override
  void onTapUp(TapUpEvent event) {
    super.onTapUp(event);
    if (game.isGameOver || game.isAvalanching || _dragged) return;

    if (game.antidoteActiveNotifier.value && debuff != DebuffType.none) {
      cure();
      game.antidoteActiveNotifier.value = false;
      return;
    }

    if (!isDropped) {
      _rotationOffset += pi / 2;
      body.setTransform(body.position, _rotationOffset);
    }
    _dragged = false;
  }

  Vector2 _dragStartPos = Vector2.zero();

  @override
  void onDragStart(DragStartEvent event) {
    if (game.isAvalanching || game.isGameOver) return;
    super.onDragStart(event);
    _dragged = false;
    _dragStartPos = event.canvasPosition;
    _virtualPosition = body.position.clone();
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (!isDropped && !game.isGameOver && !game.isAvalanching) {
      // Yalnızca parmak gerçek manada sürüklendiyse rotasyonu kitle, mikro titremeleri affet.
      if ((event.canvasEndPosition - _dragStartPos).length > 5.0) {
        _dragged = true;
      }
      final dx = event.canvasDelta.x / game.camera.viewfinder.zoom;
      final dy = event.canvasDelta.y / game.camera.viewfinder.zoom;
      
      // TAŞLAR SÜRÜKLERKEN TAMAMIYLA SERBEST! (Snapping kaldırıldı)
      _virtualPosition += Vector2(dx, dy);
      body.setTransform(_virtualPosition, game.platform.body.angle + _rotationOffset);
    }
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    _dragged = false;
    if (!isDropped && !game.isGameOver) {
      // Platform Y=6.0 merkezli. Üst yüzeyi ~5.8. 
      // İlk sıraya yerleşime izin vermek için sınırı 5.6'ya çektik.
      bool isTooLow = body.position.y > 5.6;

      if (isTooLow) {
        // Platformun çok altında bırakıldı, yuvaya geri dön.
        body.setTransform(initialSlotPosition, _rotationOffset);
        _virtualPosition = initialSlotPosition.clone();
      } else {
        // BEN BIRAKTIĞIMDA TAHTAYA CUK DİYE OTURMALI!
        final localPos = game.platform.body.localPoint(body.position);
        
        // EZİLMEYİ ÖNLE: Bırakırken de asla platform içine (y > -0.6) snap'leme.
        double targetLocalY = localPos.y.clamp(-25.0, -0.6); 
        
        int rotationSteps = (_rotationOffset / (pi / 2)).round();
        double sqX = squares[0].x;
        double sqY = squares[0].y;
        int steps = (rotationSteps % 4 + 4) % 4;
        for (int i = 0; i < steps; i++) {
            double temp = sqX;
            sqX = -sqY;
            sqY = temp;
        }
        double rem = (sqX.abs() % 1.0);
        double fractionalOffset = (rem < 0.25 || rem > 0.75) ? 0.5 : 0.0;
        double snappedLocalX = (localPos.x - fractionalOffset).roundToDouble() + fractionalOffset;
        
        // 1010 MEKANİĞİ: Eğer seçilen hücre doluysa, yanındaki boş hücrelere bak (Slide-to-Empty)
        double finalLocalX = snappedLocalX;
        Vector2 targetWorld = game.platform.body.worldPoint(Vector2(finalLocalX, targetLocalY));
        
        if (_checkOverlap(targetWorld)) {
            // Doluysa -1 or +1 yana bak
            if (!_checkOverlap(game.platform.body.worldPoint(Vector2(snappedLocalX + 1.0, targetLocalY)))) {
                finalLocalX = snappedLocalX + 1.0;
            } else if (!_checkOverlap(game.platform.body.worldPoint(Vector2(snappedLocalX - 1.0, targetLocalY)))) {
                finalLocalX = snappedLocalX - 1.0;
            } else {
                // Her yer doluysa yuvaya geri dön (Haksızlığı önler)
                body.setTransform(initialSlotPosition, _rotationOffset);
                _virtualPosition = initialSlotPosition.clone();
                return;
            }
        }
        
        // Sınır koruması - Yeni 22 birimlik platforma göre (11-11)
        double minX = 100, maxX = -100;
        for (var sq in squares) {
            double sx = sq.x, sy = sq.y;
            for (int i = 0; i < steps; i++) {
                double t = sx;
                sx = -sy;
                sy = t;
            }
            if (sx < minX) minX = sx;
            if (sx > maxX) maxX = sx;
        }
        double maxAllowedX = 11.0 - (maxX + 0.5);
        double minAllowedX = -11.0 - (minX - 0.5);
        finalLocalX = finalLocalX.clamp(minAllowedX, maxAllowedX);

        final snappedWorldPos = game.platform.body.worldPoint(Vector2(finalLocalX, targetLocalY));
        
        // CUK! (Snap before making it dynamic)
        body.setTransform(snappedWorldPos, game.platform.body.angle + _rotationOffset);

        isDropped = true;
        body.setType(BodyType.dynamic);
        body.isBullet = true; // Mermi fiziği: Sıkışma altında bile iç içe geçmeyi (tunneling) önler.
        
        // Sürükleme bitince Ghost modundan çıkart ki fiziksel çarpışmalar başlasın
        for (var fixture in body.fixtures) {
          fixture.setSensor(false);
        }

        if (!hasScored) {
          hasScored = true;
          game.addScore(squares.length);
          _spawnParticles();
        }

        game.hasDroppedFirstBlock = true;
        game.refillSlots();
      }
    }
  }

  @override
  void beginContact(Object other, Contact contact) {
    if (isDropped && !game.isGameOver) {
      // Haptic Feedback (Hafif çarpışmalar)
      if (other is PivotPlatform || other is Ground || other is FallingBlock) {
        Vibration.hasVibrator().then((hasVib) {
          if (hasVib == true) Vibration.vibrate(duration: 10, amplitude: 40);
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

  bool _checkOverlap(Vector2 worldPos) {
    // Mevcut parça squares listesini alıp, worldPos'a göre dünya koordinatlarını çıkarıyoruz
    final List<Vector2> myWorldSquares = [];
    int rotationSteps = (_rotationOffset / (pi / 2)).round();
    int steps = (rotationSteps % 4 + 4) % 4;

    for (var sq in squares) {
      double sx = sq.x, sy = sq.y;
      for (int i = 0; i < steps; i++) {
        double t = sx;
        sx = -sy;
        sy = t;
      }
      myWorldSquares.add(worldPos + Vector2(sx, sy));
    }

    // Oyundaki diğer tüm drop edilmiş bloklarla karşılaştır
    for (var other in game.world.children.whereType<FallingBlock>()) {
      if (other == this || !other.isDropped) continue;

      final List<Vector2> otherWorldSquares = [];
      int oRotationSteps = (other._rotationOffset / (pi / 2)).round();
      int oSteps = (oRotationSteps % 4 + 4) % 4;

      for (var oSq in other.squares) {
        double osx = oSq.x, osy = oSq.y;
        for (int i = 0; i < oSteps; i++) {
          double t = osx;
          osx = -osy;
          osy = t;
        }
        otherWorldSquares.add(other.body.position + Vector2(osx, osy));
      }

      // Herhangi bir kare çakışıyor mu? (1.0 mesafeden küçükse çakışma sayıyoruz)
      for (var mySq in myWorldSquares) {
        for (var oSq in otherWorldSquares) {
          if (mySq.distanceTo(oSq) < 0.8) {
            return true; // ÇAKŞIMA VAR!
          }
        }
      }
    }
    return false;
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
