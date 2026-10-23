import 'package:flutter/material.dart';

/// Tela de carregamento usada durante autenticação e leitura do usuário,
/// mantendo a marca visível em vez de só um spinner solto na tela.
class BrandedLoadingView extends StatelessWidget {
  const BrandedLoadingView({super.key});

  // Mesma logo usada na tela de login — mantém a identidade visual
  // consistente entre as duas telas.
  static const _logoAsset = 'assets/images/logo_nextgear.png';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                _logoAsset,
                width: 220,
                height: 190,
                fit: BoxFit.contain,
                semanticLabel: 'NEXT GEAR Acessórios',
                // Se o asset não carregar por algum motivo, cai num
                // ícone genérico em vez de quebrar a tela.
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.settings_suggest_outlined,
                  size: 96,
                ),
              ),

              const SizedBox(height: 32),

              // Barra de progresso indeterminada no lugar do
              // CircularProgressIndicator solto.
              SizedBox(
                width: 180,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: const LinearProgressIndicator(
                    minHeight: 6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}