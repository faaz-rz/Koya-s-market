import 'package:flutter/material.dart';

class KoyasLogo extends StatelessWidget {
  const KoyasLogo({this.compact = false, super.key});

  static const symbolAsset = 'assets/branding/koya-symbol-app-icon.png';
  static const fullAsset = 'assets/branding/koya-stores-full-logo.png';

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Koya Stores',
      image: true,
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 10 : 12),
          child: Image.asset(
            compact ? symbolAsset : fullAsset,
            width: compact ? 42 : 280,
            height: compact ? 42 : 140,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}
