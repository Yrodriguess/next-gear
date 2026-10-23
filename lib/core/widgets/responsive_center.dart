import 'package:flutter/material.dart';

/// Centraliza o conteúdo e limita a largura em telas grandes (Web/desktop),
/// sem afetar o celular — onde a tela já é estreita, ocupa 100% normalmente.
/// Ver seção 12 do Blueprint: "mesma função + mesmos dados + layouts
/// diferentes" entre Web e Android.
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = 720,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}