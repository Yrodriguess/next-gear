import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  bool _jaCapturou = false;

  late final MobileScannerController _controller;

  static const _formatosGtin = {
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upcA,
  };

  @override
  void initState() {
    super.initState();

    _controller = MobileScannerController(
      facing: CameraFacing.back,
      detectionSpeed: DetectionSpeed.normal,
      formats: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Valida o dígito verificador de EAN-8, UPC-A e EAN-13.
  /// Também suporta GTIN-14 caso seja habilitado futuramente.
  bool _gtinValido(String codigo) {
    if (!RegExp(r'^\d+$').hasMatch(codigo)) return false;
    if (![8, 12, 13, 14].contains(codigo.length)) return false;

    var soma = 0;
    final semVerificador = codigo.substring(0, codigo.length - 1);

    for (var i = 0; i < semVerificador.length; i++) {
      final digito = int.parse(semVerificador[semVerificador.length - 1 - i]);
      soma += digito * (i.isEven ? 3 : 1);
    }

    final esperado = (10 - (soma % 10)) % 10;
    final verificador = int.parse(codigo[codigo.length - 1]);

    return esperado == verificador;
  }

  /// Normaliza UPC-A para EAN-13.
  ///
  /// Use a mesma normalização no cadastro e na busca do produto.
  String _normalizarGtin(String codigo) {
    if (codigo.length == 12) return '0$codigo';
    return codigo;
  }

  bool _codigoValido(Barcode barcode, String valor) {
    return _formatosGtin.contains(barcode.format) && _gtinValido(valor);
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_jaCapturou) return;

    String? codigo;

    for (final barcode in capture.barcodes) {
      final valor = barcode.rawValue?.trim();

      if (valor == null || valor.isEmpty) continue;
      if (!_codigoValido(barcode, valor)) continue;

      codigo = _normalizarGtin(valor);
      break;
    }

    if (codigo == null) return;

    _jaCapturou = true;

    HapticFeedback.mediumImpact();

    try {
      await _controller.stop();
    } catch (_) {
      // O dispose libera a câmera caso o stop falhe.
    }

    if (!mounted) return;

    Navigator.of(context).pop(codigo);
  }

  Widget _buildErro(BuildContext context, MobileScannerException error) {
    final semPermissao =
        error.errorCode == MobileScannerErrorCode.permissionDenied;

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                semPermissao
                    ? Icons.no_photography_outlined
                    : Icons.error_outline,
                color: Colors.white70,
                size: 56,
              ),
              const SizedBox(height: 16),
              Text(
                semPermissao
                    ? 'Permissão de câmera negada'
                    : 'Não foi possível abrir a câmera',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                semPermissao
                    ? 'Libere o acesso à câmera nas configurações do aparelho '
                    'para escanear códigos.'
                    : 'Tente novamente. Se o problema continuar, reinicie o app.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .72),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Voltar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBotaoFlash() {
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: _controller,
      builder: (context, state, _) {
        final torch = state.torchState;

        if (!state.isInitialized || torch == TorchState.unavailable) {
          return const SizedBox.shrink();
        }

        final ligado = torch == TorchState.on;

        return IconButton(
          tooltip: ligado ? 'Desligar flash' : 'Ligar flash',
          onPressed: () => _controller.toggleTorch(),
          icon: Icon(
            ligado ? Icons.flashlight_on : Icons.flashlight_off_outlined,
            color: ligado ? Colors.amber : Colors.white,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Escanear código'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [_buildBotaoFlash()],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final larguraTela = constraints.maxWidth;
          final alturaTela = constraints.maxHeight;

          final larguraScanner =
          larguraTela > 520 ? 460.0 : larguraTela * .86;

          const alturaScanner = 150.0;

          final scanWindow = Rect.fromCenter(
            center: Offset(larguraTela / 2, alturaTela / 2),
            width: larguraScanner,
            height: alturaScanner,
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _controller,

                // Apenas essa região será considerada para leitura.
                scanWindow: scanWindow,

                onDetect: _onDetect,

                // Compatível com mobile_scanner 5.2.3.
                errorBuilder: (context, error, child) {
                  return _buildErro(context, error);
                },
              ),

              // Esconde visualmente toda a câmera fora da janela central.
              IgnorePointer(
                child: CustomPaint(
                  painter: _ScannerOverlayPainter(
                    scanWindow: scanWindow,
                    borderColor: theme.colorScheme.primary,
                  ),
                ),
              ),

              Positioned(
                top: 28,
                left: 20,
                right: 20,
                child: Column(
                  children: [
                    const Text(
                      'Aponte para o código de barras',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Centralize o código na área marcada.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .68),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              Positioned(
                top: scanWindow.bottom + 24,
                left: 20,
                right: 20,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .07),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .10),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.center_focus_strong,
                          color: Colors.white70,
                          size: 17,
                        ),
                        SizedBox(width: 7),
                        Text(
                          'Aproxime até o código ficar nítido',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final Rect scanWindow;
  final Color borderColor;

  const _ScannerOverlayPainter({
    required this.scanWindow,
    required this.borderColor,
  });

  /// Raio único: borda e cantos sempre acompanham a mesma curva.
  static const _raio = 16.0;

  /// Comprimento de cada perna do canto (precisa ser maior que o raio).
  static const _tamanhoCanto = 25.0;

  @override
  void paint(Canvas canvas, Size size) {
    final janelaRRect = RRect.fromRectAndRadius(
      scanWindow,
      const Radius.circular(_raio),
    );

    final tela = Path()..addRect(Offset.zero & size);
    final janela = Path()..addRRect(janelaRRect);

    final areaExterna = Path.combine(
      PathOperation.difference,
      tela,
      janela,
    );

    // Fundo praticamente fechado.
    // O usuário só vê a câmera dentro da janela.
    canvas.drawPath(
      areaExterna,
      Paint()
        ..color = Colors.black.withValues(alpha: .94)
        ..style = PaintingStyle.fill,
    );

    // Borda fina.
    canvas.drawRRect(
      janelaRRect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Cantos grossos seguindo a curva da borda.
    canvas.drawPath(
      _pathCantos(),
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Linha discreta no centro para ajudar no alinhamento.
    canvas.drawLine(
      Offset(scanWindow.left + 24, scanWindow.center.dy),
      Offset(scanWindow.right - 24, scanWindow.center.dy),
      Paint()
        ..color = borderColor.withValues(alpha: .65)
        ..strokeWidth = 1.5,
    );
  }

  /// Cada canto: reta → arco (mesmo raio da borda) → reta.
  Path _pathCantos() {
    const r = _raio;
    const t = _tamanhoCanto;
    const curva = Radius.circular(r);

    final left = scanWindow.left;
    final top = scanWindow.top;
    final right = scanWindow.right;
    final bottom = scanWindow.bottom;

    return Path()
    // Superior esquerdo.
      ..moveTo(left, top + t)
      ..lineTo(left, top + r)
      ..arcToPoint(Offset(left + r, top), radius: curva)
      ..lineTo(left + t, top)

    // Superior direito.
      ..moveTo(right - t, top)
      ..lineTo(right - r, top)
      ..arcToPoint(Offset(right, top + r), radius: curva)
      ..lineTo(right, top + t)

    // Inferior direito.
      ..moveTo(right, bottom - t)
      ..lineTo(right, bottom - r)
      ..arcToPoint(Offset(right - r, bottom), radius: curva)
      ..lineTo(right - t, bottom)

    // Inferior esquerdo.
      ..moveTo(left + t, bottom)
      ..lineTo(left + r, bottom)
      ..arcToPoint(Offset(left, bottom - r), radius: curva)
      ..lineTo(left, bottom - t);
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return oldDelegate.scanWindow != scanWindow ||
        oldDelegate.borderColor != borderColor;
  }
}