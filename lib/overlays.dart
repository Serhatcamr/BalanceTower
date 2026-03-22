import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'main.dart'; // BalanceTowerGame & globalHighScore'a erişim için

enum AugmentType {
  gyro('Denge Çubuğu', 15, Icons.balance),
  freeze('Sabitleme', 25, Icons.ac_unit),
  antidote('Panzehir', 10, Icons.healing),
  refresh('Yenileme', 2, Icons.refresh);

  final String name;
  final int cost;
  final IconData icon;

  const AugmentType(this.name, this.cost, this.icon);
}

/// Market arayüzü
class MarketOverlay extends StatefulWidget {
  final BalanceTowerGame game;

  const MarketOverlay({super.key, required this.game});

  @override
  State<MarketOverlay> createState() => _MarketOverlayState();
}

class _MarketOverlayState extends State<MarketOverlay> {
  late List<AugmentType> slots;

  @override
  void initState() {
    super.initState();
    _refreshSlots();
  }

  void _refreshSlots() {
    slots = List.generate(3, (_) => _getRandomAugment());
  }

  AugmentType _getRandomAugment() {
    final rand = Random().nextInt(100);
    if (rand < 15) return AugmentType.refresh; // %15
    if (rand < 40) return AugmentType.antidote; // %25
    if (rand < 70) return AugmentType.gyro; // %30
    return AugmentType.freeze; // %30
  }

  Future<void> _buyAugment(AugmentType type, int index) async {
    if (widget.game.scoreNotifier.value >= type.cost) {
      widget.game.scoreNotifier.value -= type.cost;
      widget.game.syncScoreText();

      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: 50, amplitude: 100);
      }

      if (type == AugmentType.refresh) {
        setState(() {
          _refreshSlots();
        });
      } else if (type == AugmentType.freeze) {
        widget.game.activateFreeze();
        setState(() {
          slots[index] = _getRandomAugment();
        });
      } else if (type == AugmentType.gyro) {
        widget.game.activateGyro();
        setState(() {
          slots[index] = _getRandomAugment();
        });
      } else if (type == AugmentType.antidote) {
        widget.game.activateAntidote();
        setState(() {
          slots[index] = _getRandomAugment();
        });
      }
    } else {
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(pattern: [0, 50, 50, 50]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.game.isGameOver) return const SizedBox.shrink();

    return Positioned(
      bottom: 20,
      left: 20,
      right: 20,
      child: ValueListenableBuilder<int>(
        valueListenable: widget.game.scoreNotifier,
        builder: (context, score, _) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2), width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(3, (index) {
                    final augment = slots[index];
                    final canAfford = score >= augment.cost;
                    return _AugmentCard(
                      augment: augment,
                      canAfford: canAfford,
                      onTap: () => _buyAugment(augment, index),
                    );
                  }),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AugmentCard extends StatefulWidget {
  final AugmentType augment;
  final bool canAfford;
  final VoidCallback onTap;

  const _AugmentCard({
    required this.augment,
    required this.canAfford,
    required this.onTap,
  });

  @override
  State<_AugmentCard> createState() => _AugmentCardState();
}

class _AugmentCardState extends State<_AugmentCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.9,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (widget.canAfford) _controller.reverse();
      },
      onTapUp: (_) {
        if (widget.canAfford) {
          _controller.forward();
          widget.onTap();
        } else {
          widget.onTap();
        }
      },
      onTapCancel: () {
        if (widget.canAfford) _controller.forward();
      },
      child: ScaleTransition(
        scale: _controller,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: widget.canAfford ? 1.0 : 0.4,
          child: Container(
            width: 90,
            height: 110,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.blueAccent.withValues(alpha: 0.8),
                  Colors.purpleAccent.withValues(alpha: 0.8)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Colors.white
                      .withValues(alpha: widget.canAfford ? 0.6 : 0.1),
                  width: 2),
              boxShadow: widget.canAfford
                  ? [
                      BoxShadow(
                          color: Colors.purple.withValues(alpha: 0.5),
                          blurRadius: 8,
                          spreadRadius: 1)
                    ]
                  : [],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.augment.icon, color: Colors.white, size: 36),
                const SizedBox(height: 8),
                Text(
                  widget.augment.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${widget.augment.cost} Pts',
                    style: TextStyle(
                      color: widget.canAfford
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GyroOverlay extends StatelessWidget {
  final BalanceTowerGame game;

  const GyroOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    if (game.isGameOver) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: game.gyroActiveNotifier,
      builder: (context, isActive, child) {
        if (!isActive) return const SizedBox.shrink();

        return Positioned(
          top: 80,
          left: 40,
          right: 40,
          child: Column(
            children: [
              const Text(
                'Denge Sensörü Aktif',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(blurRadius: 4, color: Colors.blueAccent)]),
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<double>(
                valueListenable: game.platformAngleNotifier,
                builder: (context, angle, child) {
                  double normalized = (angle + 0.5) / 1.0;
                  normalized = normalized.clamp(0.0, 1.0);

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: normalized,
                          minHeight: 24,
                          backgroundColor:
                              Colors.redAccent.withValues(alpha: 0.8),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.greenAccent),
                        ),
                      ),
                      Container(width: 4, height: 28, color: Colors.white),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class AntidoteOverlay extends StatelessWidget {
  final BalanceTowerGame game;

  const AntidoteOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    if (game.isGameOver) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: game.antidoteActiveNotifier,
      builder: (context, isActive, child) {
        if (!isActive) return const SizedBox.shrink();

        return Positioned(
          top: 100,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: Colors.green, blurRadius: 10)
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.healing, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Panzehir Aktif! \nHastalıklı bir bloğa dokun.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class ActiveAugmentTimers extends StatelessWidget {
  final BalanceTowerGame game;
  const ActiveAugmentTimers({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    if (game.isGameOver) return const SizedBox.shrink();
    return Positioned(
      top: 160,
      right: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ValueListenableBuilder<double>(
            valueListenable: game.freezeTimerNotifier,
            builder: (context, val, child) {
              if (val <= 0) return const SizedBox.shrink();
              return _TimerBar(
                  label: 'Sabitleme',
                  value: val / 10.0,
                  color: Colors.cyanAccent);
            },
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<double>(
            valueListenable: game.gyroTimerNotifier,
            builder: (context, val, child) {
              if (val <= 0) return const SizedBox.shrink();
              return _TimerBar(
                  label: 'Denge',
                  value: val / 15.0,
                  color: Colors.orangeAccent);
            },
          ),
        ],
      ),
    );
  }
}

class _TimerBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _TimerBar(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(color: Colors.black, blurRadius: 2)])),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 12,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
      ],
    );
  }
}

/// Game Over Ekranı (iOS Light Blur Stilinde)
class GameOverOverlay extends StatelessWidget {
  final BalanceTowerGame game;

  const GameOverOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: 320,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85), // iOS Light overlay
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3), blurRadius: 30)
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Oyun Bitti!',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 24),

              // Skor Kutusu
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Text(
                      'Skorunuz: ${game.scoreNotifier.value}',
                      style: const TextStyle(
                          fontSize: 22,
                          color: Colors.black87,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'En Yüksek Skor: $globalHighScore',
                      style: const TextStyle(
                          fontSize: 16,
                          color: Colors.blueAccent,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // Tekrar Dene Butonu
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => game.retry(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 5,
                  ),
                  child: const Text('Tekrar Dene',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
