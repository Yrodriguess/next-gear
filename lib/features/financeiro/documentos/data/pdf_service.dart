import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/utils/br_formatters.dart';
import '../../../visitas/domain/visita_resultado.dart';
import '../presentation/assinatura_page.dart';

final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _formatoDataHora = DateFormat("dd/MM/yyyy 'às' HH:mm");
final _formatoDataCurta = DateFormat('dd/MM/yyyy');
final _formatoHora = DateFormat('HH:mm');

final PdfColor _corInstalacao = PdfColor(0.92, 0.97, 1.00);
final PdfColor _corReposicao = PdfColor(0.92, 0.98, 0.94);
final PdfColor _corRetirada = PdfColor(1.00, 0.95, 0.90);

String _reais(int centavos) => _formatoMoeda.format(centavos / 100);

/// ================================================================
/// DADOS DA NEXT GEAR
/// ================================================================
/// Preencha somente os dados reais da empresa.
/// Campos vazios não aparecem no PDF.
const _empresaNome = 'NEXT GEAR';
const _empresaSlogan = 'ACESSÓRIOS QUE MOVEM O SEU NEGÓCIO';
const _empresaInstagram = '@NEXTGEARACESSORIOS';
const _empresaContato = '';
const _empresaTelefone = '(61) 9 8668-6853';
const _empresaDocumento = '033.185.511-98';
const _empresaRazaoSocial = '';
const _empresaEndereco = 'qsf 07 casa 411 taguatinga sul -df';
const _empresaFrase = 'PARCERIA QUE GERA RESULTADOS';

String _tituloCase(String texto) {
  const minusculas = {'de', 'da', 'do', 'das', 'dos', 'e'};
  final palavras = texto.trim().toLowerCase().split(RegExp(r'\s+'));

  return palavras.asMap().entries.map((entry) {
    final palavra = entry.value;
    if (palavra.isEmpty) return palavra;
    if (entry.key != 0 && minusculas.contains(palavra)) return palavra;
    return palavra[0].toUpperCase() + palavra.substring(1);
  }).join(' ');
}

bool _temTexto(String? texto) => texto != null && texto.trim().isNotEmpty;

String _somenteDigitos(String texto) => texto.replaceAll(RegExp(r'\D'), '');

String _rotuloDocumentoEmpresa(String documento) {
  final digitos = _somenteDigitos(documento);
  if (digitos.length == 14) return 'CNPJ';
  if (digitos.length == 11) return 'CPF';
  return 'CPF/CNPJ';
}

String _textoPdfSeguro(String texto) {
  return texto
      .replaceAll(RegExp('[\u2010-\u2015]'), '-')
      .replaceAll(RegExp('[^\u0020-\u007E\u00A0-\u00FF]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

int? _valorReposicaoExpositorCentavos(String? modelo) {
  final nome = modelo?.trim().toLowerCase() ?? '';

  if (nome.contains('grande')) {
    return 100000;
  }

  if (nome.contains('pequeno')) {
    return 70000;
  }

  return null;
}

class _ResumoLinha {
  final String label;
  final String valor;
  final bool destaque;

  const _ResumoLinha(
      this.label,
      this.valor, {
        this.destaque = false,
      });
}

/// Geração dos documentos oficiais da visita:
///
/// INS = Instalação / consignação inicial.
/// REP = Conferência + acerto + nova posição consignada.
/// RET = Conferência final + acerto + retirada do expositor.
class PdfService {
  /// ================================================================
  /// INSTALAÇÃO — INS-000000
  /// ================================================================
  Future<Uint8List> gerarTermoInstalacao({
    required String numeroDocumento,
    required String nomeCliente,
    required String cpfCnpjCliente,
    required String vendedorNome,
    required VisitaResultado resultado,
    required AssinaturaColetada assinatura,
    String enderecoCliente = '',
    String bairroCliente = '',
    String cidadeCliente = '',
    String ufCliente = '',
    String cepCliente = '',
  }) async {
    final geradoEm = DateTime.now();
    final dataOperacao = assinatura.assinadaEm.toLocal();
    final doc = pw.Document();
    final assinaturaImage = pw.MemoryImage(assinatura.assinaturaPng);

    final itens = resultado.itensNovaPosicao;
    final quantidadeTotal =
    itens.fold<int>(0, (soma, i) => soma + i.quantidade);
    final vendaPotencialTotal =
    itens.fold<int>(0, (soma, i) => soma + i.vendaPotencialCentavos);
    final repassePotencialTotal =
    itens.fold<int>(0, (soma, i) => soma + i.repassePotencialCentavos);
    final ganhoPotencialTotal =
    itens.fold<int>(0, (soma, i) => soma + i.ganhoPotencialCentavos);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(22, 20, 22, 18),
        header: (_) => _cabecalhoComercial(
          titulo: 'INSTALAÇÃO E CONSIGNAÇÃO INICIAL',
          numeroDocumento: numeroDocumento,
          corTitulo: _corInstalacao,
          situacao: 'Consignação inicial',
          dataOperacao: dataOperacao,
          geradoEm: geradoEm,
          nomeCliente: nomeCliente,
          cpfCnpjCliente: cpfCnpjCliente,
          vendedorNome: vendedorNome,
          visitaNumero: resultado.visitaNumero,
          expositorNumero: resultado.expositorNumero,
          expositorModeloNome: resultado.expositorModeloNome,
          enderecoCliente: enderecoCliente,
          bairroCliente: bairroCliente,
          cidadeCliente: cidadeCliente,
          ufCliente: ufCliente,
          cepCliente: cepCliente,
        ),
        footer: (context) => _rodape(
          context,
          geradoEm,
          numeroDocumento,
        ),
        build: (_) => [
          _tituloSecao('POSIÇÃO INICIAL CONSIGNADA'),
          pw.SizedBox(height: 5),
          _tabelaComercial(
            cabecalhos: const [
              'Referência',
              'Descrição do item',
              'Qtd.',
              'Venda un.',
              'Repasse un.',
              'Ganho cliente un.',
              'Total venda',
            ],
            linhas: itens
                .map(
                  (item) => [
                item.codigoInterno,
                _textoPdfSeguro(item.descricao),
                '${item.quantidade}',
                _reais(item.precoVendaCentavosUnit),
                _reais(item.repasseCentavosUnit),
                _reais(item.comissaoCentavosUnit),
                _reais(item.vendaPotencialCentavos),
              ],
            )
                .toList(),
            larguras: const {
              0: pw.FlexColumnWidth(1.20),
              1: pw.FlexColumnWidth(3.55),
              2: pw.FlexColumnWidth(0.58),
              3: pw.FlexColumnWidth(0.95),
              4: pw.FlexColumnWidth(1.02),
              5: pw.FlexColumnWidth(1.15),
              6: pw.FlexColumnWidth(1.05),
            },
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _blocoExpositorConsignado(
                  expositorNumero: resultado.expositorNumero,
                  expositorModeloNome: resultado.expositorModeloNome,
                  cor: _corInstalacao,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.SizedBox(
                width: 270,
                child: _blocoResumo(
                  titulo: 'RESUMO DA CONSIGNAÇÃO',
                  linhas: [
                    _ResumoLinha(
                      'Quantidade total no expositor',
                      '$quantidadeTotal un.',
                    ),
                    _ResumoLinha(
                      'Valor dos produtos',
                      _reais(vendaPotencialTotal),
                    ),
                    _ResumoLinha(
                      'Repasse Next Gear',
                      _reais(repassePotencialTotal),
                    ),
                    _ResumoLinha(
                      'Ganho potencial do cliente',
                      _reais(ganhoPotencialTotal),
                      destaque: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 9),
          _declaracao(
            'Declaro que conferi o expositor, os produtos, as quantidades e os '
                'valores apresentados neste documento, confirmando o recebimento '
                'da consignação inicial.',
          ),
          pw.SizedBox(height: 8),
          _areaAssinaturas(
            assinatura: assinatura,
            assinaturaImage: assinaturaImage,
            vendedorNome: vendedorNome,
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// ================================================================
  /// REPOSIÇÃO / ACERTO — REP-000000
  /// ================================================================
  Future<Uint8List> gerarTermoReposicao({
    required String numeroDocumento,
    required String nomeCliente,
    required String cpfCnpjCliente,
    required String vendedorNome,
    required VisitaResultado resultado,
    required AssinaturaColetada assinatura,
    String enderecoCliente = '',
    String bairroCliente = '',
    String cidadeCliente = '',
    String ufCliente = '',
    String cepCliente = '',
  }) async {
    final geradoEm = DateTime.now();
    final dataOperacao = assinatura.assinadaEm.toLocal();
    final doc = pw.Document();
    final assinaturaImage = pw.MemoryImage(assinatura.assinaturaPng);

    final acerto = resultado.itensCicloEncerrado;
    final novaPosicao = resultado.itensNovaPosicao;

    final unidadesVendidas =
    acerto.fold<int>(0, (soma, i) => soma + i.quantidadeVendida);
    final unidadesRepostas = novaPosicao.fold<int>(
      0,
          (soma, i) => soma + (i.quantidadeReposta ?? 0),
    );
    final novaPosicaoTotal =
    novaPosicao.fold<int>(0, (soma, i) => soma + i.quantidade);
    final vendaPotencialTotal = novaPosicao.fold<int>(
      0,
          (soma, i) => soma + i.vendaPotencialCentavos,
    );
    final repassePotencialTotal = novaPosicao.fold<int>(
      0,
          (soma, i) => soma + i.repassePotencialCentavos,
    );
    final ganhoPotencialTotal = novaPosicao.fold<int>(
      0,
          (soma, i) => soma + i.ganhoPotencialCentavos,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(22, 20, 22, 18),
        header: (_) => _cabecalhoComercial(
          titulo: 'REPOSIÇÃO E ACERTO',
          numeroDocumento: numeroDocumento,
          corTitulo: _corReposicao,
          situacao: 'Reposição e acerto',
          dataOperacao: dataOperacao,
          geradoEm: geradoEm,
          nomeCliente: nomeCliente,
          cpfCnpjCliente: cpfCnpjCliente,
          vendedorNome: vendedorNome,
          visitaNumero: resultado.visitaNumero,
          expositorNumero: resultado.expositorNumero,
          expositorModeloNome: resultado.expositorModeloNome,
          enderecoCliente: enderecoCliente,
          bairroCliente: bairroCliente,
          cidadeCliente: cidadeCliente,
          ufCliente: ufCliente,
          cepCliente: cepCliente,
        ),
        footer: (context) => _rodape(
          context,
          geradoEm,
          numeroDocumento,
        ),
        build: (_) => [
          _tituloSecao('1. CONFERÊNCIA E ACERTO DO CICLO'),
          pw.SizedBox(height: 5),
          _tabelaComercial(
            cabecalhos: const [
              'Referência',
              'Descrição do item',
              'Ant.',
              'Conf.',
              'Vend.',
              'Venda un.',
              'Repasse',
              'Ganho cliente',
            ],
            linhas: acerto
                .map(
                  (item) => [
                item.codigoInterno,
                _textoPdfSeguro(item.descricao),
                '${item.saldoAnteriorQuantidade ?? 0}',
                '${item.quantidadeConferida ?? 0}',
                '${item.quantidadeVendida}',
                _reais(item.precoVendaCentavosUnit),
                _reais(item.repasseDevidoCentavos),
                _reais(item.ganhoRealizadoCentavos),
              ],
            )
                .toList(),
            larguras: const {
              0: pw.FlexColumnWidth(1.05),
              1: pw.FlexColumnWidth(3.10),
              2: pw.FlexColumnWidth(0.52),
              3: pw.FlexColumnWidth(0.52),
              4: pw.FlexColumnWidth(0.52),
              5: pw.FlexColumnWidth(0.88),
              6: pw.FlexColumnWidth(0.95),
              7: pw.FlexColumnWidth(1.02),
            },
            fonte: 6.15,
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _blocoExpositorConsignado(
                  expositorNumero: resultado.expositorNumero,
                  expositorModeloNome: resultado.expositorModeloNome,
                  cor: _corReposicao,
                  textoInicial:
                  'permanece em consignação com o cliente para continuidade da operação.',
                ),
              ),
              pw.SizedBox(width: 10),
              pw.SizedBox(
                width: 270,
                child: _blocoResumo(
                  titulo: 'RESUMO DO ACERTO',
                  linhas: [
                    _ResumoLinha(
                      'Unidades vendidas',
                      '$unidadesVendidas un.',
                    ),
                    _ResumoLinha(
                      'Valor total vendido',
                      _reais(resultado.totalVendidoCentavos),
                    ),
                    _ResumoLinha(
                      'Repasse Next Gear',
                      _reais(resultado.valorAPagarNextGearCentavos),
                    ),
                    _ResumoLinha(
                      'Ganho do cliente',
                      _reais(resultado.comissaoRetidaCentavos),
                      destaque: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 9),
          _declaracao(
            'Declaro que conferi os produtos, as quantidades encontradas, as '
                'unidades vendidas e os valores apurados neste acerto.',
          ),
          pw.SizedBox(height: 8),
          _areaAssinaturas(
            assinatura: assinatura,
            assinaturaImage: assinaturaImage,
            vendedorNome: vendedorNome,
          ),
          pw.NewPage(),
          _tituloSecao('2. REPOSIÇÃO / NOVA POSIÇÃO CONSIGNADA'),
          pw.SizedBox(height: 5),
          _tabelaComercial(
            cabecalhos: const [
              'Referência',
              'Descrição do item',
              'Qtd.',
              'Venda un.',
              'Repasse un.',
              'Ganho cliente un.',
              'Total venda',
            ],
            linhas: novaPosicao
                .map(
                  (item) => [
                item.codigoInterno,
                _textoPdfSeguro(item.descricao),
                '${item.quantidade}',
                _reais(item.precoVendaCentavosUnit),
                _reais(item.repasseCentavosUnit),
                _reais(item.comissaoCentavosUnit),
                _reais(item.vendaPotencialCentavos),
              ],
            )
                .toList(),
            larguras: const {
              0: pw.FlexColumnWidth(1.20),
              1: pw.FlexColumnWidth(3.55),
              2: pw.FlexColumnWidth(0.58),
              3: pw.FlexColumnWidth(0.95),
              4: pw.FlexColumnWidth(1.02),
              5: pw.FlexColumnWidth(1.15),
              6: pw.FlexColumnWidth(1.05),
            },
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _blocoExpositorConsignado(
                  expositorNumero: resultado.expositorNumero,
                  expositorModeloNome: resultado.expositorModeloNome,
                  cor: _corReposicao,
                  textoInicial:
                  'continua consignado ao estabelecimento após esta reposição.',
                ),
              ),
              pw.SizedBox(width: 10),
              pw.SizedBox(
                width: 270,
                child: _blocoResumo(
                  titulo: 'RESUMO DA NOVA POSIÇÃO',
                  linhas: [
                    _ResumoLinha(
                      'Unidades repostas',
                      '$unidadesRepostas un.',
                    ),
                    _ResumoLinha(
                      'Quantidade no expositor',
                      '$novaPosicaoTotal un.',
                    ),
                    _ResumoLinha(
                      'Valor dos produtos',
                      _reais(vendaPotencialTotal),
                    ),
                    _ResumoLinha(
                      'Repasse Next Gear',
                      _reais(repassePotencialTotal),
                    ),
                    _ResumoLinha(
                      'Ganho potencial do cliente',
                      _reais(ganhoPotencialTotal),
                      destaque: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 9),
          _declaracao(
            'Declaro que conferi os produtos e as quantidades desta reposição '
                'e estou de acordo com a nova posição consignada do expositor e '
                'com os valores apresentados neste documento.',
          ),
          pw.SizedBox(height: 8),
          _areaAssinaturas(
            assinatura: assinatura,
            assinaturaImage: assinaturaImage,
            vendedorNome: vendedorNome,
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// ================================================================
  /// RETIRADA / ENCERRAMENTO — RET-000000
  /// ================================================================
  Future<Uint8List> gerarTermoRetirada({
    required String numeroDocumento,
    required String nomeCliente,
    required String cpfCnpjCliente,
    required String vendedorNome,
    required RetiradaResultado resultado,
    required AssinaturaColetada assinatura,
    String enderecoCliente = '',
    String bairroCliente = '',
    String cidadeCliente = '',
    String ufCliente = '',
    String cepCliente = '',
  }) async {
    final geradoEm = DateTime.now();
    final dataOperacao = assinatura.assinadaEm.toLocal();
    final doc = pw.Document();
    final assinaturaImage = pw.MemoryImage(assinatura.assinaturaPng);

    final totalEsperado =
    resultado.itens.fold<int>(0, (soma, i) => soma + i.saldoEsperado);
    final totalDevolvido = resultado.itens.fold<int>(
      0,
          (soma, i) => soma + i.quantidadeDevolvida,
    );
    final totalNaoDevolvido = resultado.itens.fold<int>(
      0,
          (soma, i) => soma + i.quantidadeNaoDevolvida,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(22, 20, 22, 18),
        header: (_) => _cabecalhoComercial(
          titulo: 'RETIRADA E ENCERRAMENTO',
          numeroDocumento: numeroDocumento,
          corTitulo: _corRetirada,
          situacao: 'Retirada e encerramento',
          dataOperacao: dataOperacao,
          geradoEm: geradoEm,
          nomeCliente: nomeCliente,
          cpfCnpjCliente: cpfCnpjCliente,
          vendedorNome: vendedorNome,
          visitaNumero: resultado.visitaNumero,
          expositorNumero: resultado.expositorNumero,
          expositorModeloNome: resultado.expositorModeloNome,
          enderecoCliente: enderecoCliente,
          bairroCliente: bairroCliente,
          cidadeCliente: cidadeCliente,
          ufCliente: ufCliente,
          cepCliente: cepCliente,
        ),
        footer: (context) => _rodape(
          context,
          geradoEm,
          numeroDocumento,
        ),
        build: (_) => [
          _tituloSecao('CONFERÊNCIA E ACERTO FINAL'),
          pw.SizedBox(height: 3),
          pw.Text(
            'Consignação encerrada: ${resultado.consignmentEncerradaNumero}   |   '
                'Motivo: ${motivoRetiradaLabel(resultado.motivo)}',
            style: const pw.TextStyle(
              fontSize: 7.1,
              color: PdfColors.grey700,
            ),
          ),
          pw.SizedBox(height: 5),
          _tabelaComercial(
            cabecalhos: const [
              'Referência',
              'Descrição do item',
              'Esperado',
              'Devolvido',
              'Não dev.',
              'Situação',
              'Repasse un.',
              'Repasse',
            ],
            linhas: resultado.itens
                .map(
                  (item) => [
                item.codigoInterno,
                _textoPdfSeguro(item.descricao),
                '${item.saldoEsperado}',
                '${item.quantidadeDevolvida}',
                '${item.quantidadeNaoDevolvida}',
                _textoPdfSeguro(item.classificacaoLabel ?? '—'),
                _reais(item.repasseCentavosUnit),
                _reais(item.valorARepassarCentavos),
              ],
            )
                .toList(),
            larguras: const {
              0: pw.FlexColumnWidth(1.00),
              1: pw.FlexColumnWidth(2.95),
              2: pw.FlexColumnWidth(0.68),
              3: pw.FlexColumnWidth(0.72),
              4: pw.FlexColumnWidth(0.68),
              5: pw.FlexColumnWidth(1.10),
              6: pw.FlexColumnWidth(0.92),
              7: pw.FlexColumnWidth(0.92),
            },
            fonte: 6.10,
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _blocoDevolucaoExpositor(
                  expositorNumero: resultado.expositorNumero,
                  expositorModeloNome: resultado.expositorModeloNome,
                  destinoExpositor: resultado.destinoExpositorLabel,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.SizedBox(
                width: 270,
                child: _blocoResumo(
                  titulo: 'RESUMO FINAL',
                  linhas: [
                    _ResumoLinha(
                      'Unidades esperadas',
                      '$totalEsperado un.',
                    ),
                    _ResumoLinha(
                      'Unidades devolvidas',
                      '$totalDevolvido un.',
                    ),
                    _ResumoLinha(
                      'Unidades não devolvidas',
                      '$totalNaoDevolvido un.',
                    ),
                    _ResumoLinha(
                      'Valor do acerto final',
                      _reais(resultado.valorARepassarTotalCentavos),
                      destaque: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 9),
          _declaracao(
            'Declaro que conferi as quantidades devolvidas e os valores '
                'apresentados neste documento, reconheço o eventual acerto final '
                'e confirmo a retirada do expositor e o encerramento da consignação.',
          ),
          pw.SizedBox(height: 8),
          _areaAssinaturas(
            assinatura: assinatura,
            assinaturaImage: assinaturaImage,
            vendedorNome: vendedorNome,
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// ================================================================
  /// CABEÇALHO
  /// ================================================================
  pw.Widget _cabecalhoComercial({
    required String titulo,
    required String numeroDocumento,
    required PdfColor corTitulo,
    required String situacao,
    required DateTime dataOperacao,
    required DateTime geradoEm,
    required String nomeCliente,
    required String cpfCnpjCliente,
    required String vendedorNome,
    required String visitaNumero,
    required String enderecoCliente,
    required String bairroCliente,
    required String cidadeCliente,
    required String ufCliente,
    required String cepCliente,
    String? expositorNumero,
    String? expositorModeloNome,
  }) {
    final contatosEmpresa = [
      if (_temTexto(_empresaInstagram)) _empresaInstagram,
      if (_temTexto(_empresaContato)) _empresaContato,
      if (_temTexto(_empresaTelefone)) _empresaTelefone,
    ].join('   ');

    final documentoEmpresaFormatado = formatarCpfCnpj(_empresaDocumento);
    final documentoEmpresaRotulo = _rotuloDocumentoEmpresa(_empresaDocumento);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 34,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _empresaNome,
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    _empresaSlogan,
                    style: pw.TextStyle(
                      fontSize: 6.2,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            pw.Expanded(
              flex: 35,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (contatosEmpresa.isNotEmpty)
                    pw.Text(
                      contatosEmpresa,
                      style: const pw.TextStyle(fontSize: 6.7),
                    ),
                  if (_temTexto(_empresaEndereco)) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      _tituloCase(_empresaEndereco),
                      style: const pw.TextStyle(fontSize: 6.4),
                    ),
                  ],
                ],
              ),
            ),
            pw.Container(
              width: 0.5,
              height: 35,
              color: PdfColors.grey500,
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              flex: 23,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (_temTexto(_empresaDocumento))
                    pw.Text(
                      '$documentoEmpresaRotulo $documentoEmpresaFormatado',
                      style: const pw.TextStyle(fontSize: 6.9),
                    ),
                  if (_temTexto(_empresaRazaoSocial)) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      _empresaRazaoSocial,
                      style: const pw.TextStyle(fontSize: 6.4),
                    ),
                  ],
                ],
              ),
            ),
            pw.Container(
              width: 0.5,
              height: 35,
              color: PdfColors.grey500,
            ),
            pw.SizedBox(width: 10),
            pw.SizedBox(
              width: 72,
              child: pw.Text(
                _empresaFrase,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 7.2,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 7),
        pw.Container(height: 0.8, color: PdfColors.grey800),
        pw.SizedBox(height: 6),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          decoration: pw.BoxDecoration(
            color: corTitulo,
            borderRadius: pw.BorderRadius.circular(5),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      titulo,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 1),
                    pw.Text(
                      numeroDocumento,
                      style: pw.TextStyle(
                        fontSize: 9.2,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(
                width: 155,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Data da operação: ${_formatoDataHora.format(dataOperacao)}',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 6.6,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 1),
                    pw.Text(
                      'Documento gerado em: ${_formatoDataHora.format(geradoEm)}',
                      textAlign: pw.TextAlign.right,
                      style: const pw.TextStyle(
                        fontSize: 6.2,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 7),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _cardDados(
                titulo: 'DADOS DO CLIENTE',
                linhas: [
                  ['Nome', _textoPdfSeguro(nomeCliente).toUpperCase()],
                  ['CPF/CNPJ', formatarCpfCnpj(cpfCnpjCliente)],
                  if (_temTexto(enderecoCliente))
                    ['Endereço', _textoPdfSeguro(enderecoCliente)],
                  if (_temTexto(bairroCliente))
                    ['Bairro', _tituloCase(_textoPdfSeguro(bairroCliente))],
                  if (_temTexto(cidadeCliente) || _temTexto(ufCliente))
                    [
                      'Cidade/UF',
                      [
                        if (_temTexto(cidadeCliente))
                          _tituloCase(_textoPdfSeguro(cidadeCliente)),
                        if (_temTexto(ufCliente)) ufCliente.toUpperCase(),
                      ].join(' / '),
                    ],
                  if (_temTexto(cepCliente)) ['CEP', cepCliente],
                ],
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _cardDados(
                titulo: 'DADOS DA OPERAÇÃO',
                linhas: [
                  ['Vendedor', _tituloCase(_textoPdfSeguro(vendedorNome))],
                  if (_temTexto(expositorNumero))
                    ['Expositor', expositorNumero!],
                  if (_temTexto(expositorModeloNome))
                    ['Modelo', _tituloCase(expositorModeloNome!)],
                  ['Visita', visitaNumero],
                  ['Situação', situacao],
                  ['Data da visita', _formatoDataCurta.format(dataOperacao)],
                  ['Hora', _formatoHora.format(dataOperacao)],
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
      ],
    );
  }

  pw.Widget _cardDados({
    required String titulo,
    required List<List<String>> linhas,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColors.grey400,
          width: 0.45,
        ),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            decoration: const pw.BoxDecoration(
              color: PdfColors.grey200,
              borderRadius: pw.BorderRadius.only(
                topLeft: pw.Radius.circular(4),
                topRight: pw.Radius.circular(4),
              ),
            ),
            child: pw.Text(
              titulo,
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(8, 5, 8, 5),
            child: pw.Column(
              children: linhas
                  .map(
                    (linha) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 1.7),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.SizedBox(
                        width: 58,
                        child: pw.Text(
                          '${linha[0]}:',
                          style: pw.TextStyle(
                            fontSize: 6.6,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Text(
                          linha[1],
                          style: const pw.TextStyle(fontSize: 6.6),
                        ),
                      ),
                    ],
                  ),
                ),
              )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// ================================================================
  /// TÍTULO DE SEÇÃO
  /// ================================================================
  pw.Widget _tituloSecao(String titulo) {
    return pw.Row(
      children: [
        pw.Container(
          width: 8,
          height: 8,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(
              color: PdfColors.grey800,
              width: 0.8,
            ),
          ),
        ),
        pw.SizedBox(width: 6),
        pw.Text(
          titulo,
          style: pw.TextStyle(
            fontSize: 9.2,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// ================================================================
  /// TABELA COMERCIAL
  /// ================================================================
  pw.Widget _tabelaComercial({
    required List<String> cabecalhos,
    required List<List<String>> linhas,
    required Map<int, pw.TableColumnWidth> larguras,
    double fonte = 6.35,
  }) {
    return pw.TableHelper.fromTextArray(
      headers: cabecalhos,
      data: linhas,
      headerStyle: pw.TextStyle(
        fontSize: fonte,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.black,
      ),
      headerDecoration: const pw.BoxDecoration(
        color: PdfColors.grey300,
      ),
      rowDecoration: const pw.BoxDecoration(
        color: PdfColors.white,
      ),
      oddRowDecoration: const pw.BoxDecoration(
        color: PdfColors.grey100,
      ),
      cellStyle: pw.TextStyle(fontSize: fonte),
      cellAlignment: pw.Alignment.centerRight,
      cellAlignments: const {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
      },
      cellPadding: const pw.EdgeInsets.symmetric(
        horizontal: 3.0,
        vertical: 2.0,
      ),
      border: const pw.TableBorder(
        top: pw.BorderSide(
          color: PdfColors.grey500,
          width: 0.45,
        ),
        bottom: pw.BorderSide(
          color: PdfColors.grey500,
          width: 0.45,
        ),
        horizontalInside: pw.BorderSide(
          color: PdfColors.grey300,
          width: 0.25,
        ),
        verticalInside: pw.BorderSide(
          color: PdfColors.grey300,
          width: 0.20,
        ),
      ),
      columnWidths: larguras,
    );
  }

  /// ================================================================
  /// EXPOSITOR
  /// ================================================================
  pw.Widget _blocoExpositorConsignado({
    required String? expositorNumero,
    required String? expositorModeloNome,
    required PdfColor cor,
    String? textoInicial,
  }) {
    final valorReposicao =
    _valorReposicaoExpositorCentavos(expositorModeloNome);

    final identificacao = [
      if (_temTexto(expositorNumero)) expositorNumero!,
      if (_temTexto(expositorModeloNome))
        'Modelo ${_tituloCase(expositorModeloNome!)}',
    ].join(' — ');

    final sujeito = identificacao.isEmpty
        ? 'O expositor'
        : 'O expositor $identificacao';

    final textoBase = textoInicial ??
        'permanece de propriedade da NEXT GEAR e é disponibilizado ao '
            'estabelecimento exclusivamente para exposição dos produtos consignados.';

    final textoCompleto = '$sujeito $textoBase';

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: cor,
        borderRadius: pw.BorderRadius.circular(5),
        border: pw.Border.all(
          color: PdfColors.grey400,
          width: 0.45,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'EXPOSITOR EM CONSIGNAÇÃO',
            style: pw.TextStyle(
              fontSize: 8.2,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            textoCompleto,
            style: const pw.TextStyle(fontSize: 6.7),
          ),
          if (valorReposicao != null) ...[
            pw.SizedBox(height: 5),
            pw.RichText(
              text: pw.TextSpan(
                style: const pw.TextStyle(fontSize: 6.7),
                children: [
                  const pw.TextSpan(
                    text:
                    'Em caso de perda, extravio, dano irreparável ou não devolução, fica estabelecido o ',
                  ),
                  pw.TextSpan(
                    text:
                    'valor de reposição de ${_reais(valorReposicao)}.',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _blocoDevolucaoExpositor({
    required String expositorNumero,
    required String expositorModeloNome,
    required String destinoExpositor,
  }) {
    final valorReposicao =
    _valorReposicaoExpositorCentavos(expositorModeloNome);

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _corRetirada,
        borderRadius: pw.BorderRadius.circular(5),
        border: pw.Border.all(
          color: PdfColors.grey400,
          width: 0.45,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'RETIRADA DO EXPOSITOR',
            style: pw.TextStyle(
              fontSize: 8.2,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            'Expositor $expositorNumero — Modelo ${_tituloCase(expositorModeloNome)}.',
            style: const pw.TextStyle(fontSize: 6.7),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            'Destino registrado: ${_textoPdfSeguro(destinoExpositor)}.',
            style: const pw.TextStyle(fontSize: 6.7),
          ),
          if (valorReposicao != null) ...[
            pw.SizedBox(height: 5),
            pw.Text(
              'Valor de reposição de referência: ${_reais(valorReposicao)}.',
              style: pw.TextStyle(
                fontSize: 6.7,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// ================================================================
  /// RESUMO
  /// ================================================================
  pw.Widget _blocoResumo({
    required String titulo,
    required List<_ResumoLinha> linhas,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColors.grey400,
          width: 0.45,
        ),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 9,
              vertical: 5,
            ),
            decoration: const pw.BoxDecoration(
              color: PdfColors.grey200,
              borderRadius: pw.BorderRadius.only(
                topLeft: pw.Radius.circular(5),
                topRight: pw.Radius.circular(5),
              ),
            ),
            child: pw.Text(
              titulo,
              style: pw.TextStyle(
                fontSize: 7.8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          ...linhas.map((linha) {
            final corTexto = linha.destaque
                ? PdfColors.white
                : PdfColors.black;

            return pw.Container(
              color: linha.destaque ? PdfColors.grey700 : null,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 3.0,
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      '${linha.label}:',
                      style: pw.TextStyle(
                        fontSize: 6.8,
                        color: corTexto,
                        fontWeight: linha.destaque
                            ? pw.FontWeight.bold
                            : pw.FontWeight.normal,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Text(
                    linha.valor,
                    style: pw.TextStyle(
                      fontSize: linha.destaque ? 7.4 : 6.9,
                      color: corTexto,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// ================================================================
  /// DECLARAÇÃO E ASSINATURA
  /// ================================================================
  pw.Widget _declaracao(String texto) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(
            color: PdfColors.grey700,
            width: 0.55,
          ),
        ),
      ),
      child: pw.Text(
        texto,
        style: const pw.TextStyle(fontSize: 6.7),
      ),
    );
  }

  pw.Widget _areaAssinaturas({
    required AssinaturaColetada assinatura,
    required pw.MemoryImage assinaturaImage,
    required String vendedorNome,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          flex: 42,
          child: _blocoAssinaturaCompacto(
            assinatura,
            assinaturaImage,
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Container(
          width: 0.5,
          height: 58,
          color: PdfColors.grey500,
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          flex: 28,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Atendimento realizado por:',
                style: const pw.TextStyle(fontSize: 6.4),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                _tituloCase(_textoPdfSeguro(vendedorNome)),
                style: pw.TextStyle(
                  fontSize: 8.0,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'NEXT GEAR',
                style: const pw.TextStyle(fontSize: 6.5),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          flex: 25,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(9),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              border: pw.Border.all(
                color: PdfColors.grey400,
                width: 0.4,
              ),
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Column(
              children: [
                pw.Text(
                  '“Juntos, movemos mais negócios.”',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 7.0,
                    fontStyle: pw.FontStyle.italic,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'NEXT GEAR',
                  style: const pw.TextStyle(
                    fontSize: 6.4,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _blocoAssinaturaCompacto(
      AssinaturaColetada assinatura,
      pw.MemoryImage assinaturaImage,
      ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 230,
          height: 38,
          child: pw.Image(
            assinaturaImage,
            fit: pw.BoxFit.contain,
            alignment: pw.Alignment.bottomLeft,
          ),
        ),
        pw.Container(
          width: 230,
          height: 0.55,
          color: PdfColors.grey700,
        ),
        pw.SizedBox(height: 2.5),
        pw.Text(
          _tituloCase(_textoPdfSeguro(assinatura.nomeResponsavel)),
          style: pw.TextStyle(
            fontSize: 7.3,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Text(
          'Responsável pelo estabelecimento',
          style: const pw.TextStyle(fontSize: 6.4),
        ),
        pw.Text(
          'CPF/CNPJ: ${formatarCpfCnpj(assinatura.documentoResponsavel)}',
          style: const pw.TextStyle(fontSize: 6.4),
        ),
        pw.Text(
          'Assinado eletronicamente em: '
              '${_formatoDataHora.format(assinatura.assinadaEm.toLocal())}',
          style: const pw.TextStyle(fontSize: 6.4),
        ),
      ],
    );
  }

  /// ================================================================
  /// RODAPÉ
  /// ================================================================
  pw.Widget _rodape(
      pw.Context context,
      DateTime geradoEm,
      String numeroDocumento,
      ) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(
            color: PdfColors.grey500,
            width: 0.4,
          ),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              'Documento eletrônico gerado pelo sistema NEXT GEAR.',
              style: const pw.TextStyle(
                fontSize: 6.0,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Text(
            '$numeroDocumento   |   ${_formatoDataHora.format(geradoEm)}',
            style: const pw.TextStyle(
              fontSize: 6.0,
              color: PdfColors.grey700,
            ),
          ),
          pw.SizedBox(width: 18),
          pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(
              fontSize: 6.0,
              color: PdfColors.grey700,
            ),
          ),
        ],
      ),
    );
  }
}
