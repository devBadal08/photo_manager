import 'package:dice_bear/dice_bear.dart';
import 'package:flutter/material.dart';

class DiceBearAvatar extends StatelessWidget {
  final String seed;
  final double size;
  final DiceBearSprite sprite; // 👈 allow different styles

  const DiceBearAvatar({
    super.key,
    required this.seed,
    this.size = 48,
    this.sprite = DiceBearSprite.avataaars, // default
  });

  @override
  Widget build(BuildContext context) {
    // Build the avatar with chosen sprite + seed
    final avatar = DiceBearBuilder(sprite: sprite, seed: seed).build();

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: Colors.grey.shade200,
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: avatar.toImage(width: size, height: size, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
