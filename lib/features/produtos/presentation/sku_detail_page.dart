import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money_input_formatter.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../estoque/domain/stock_movement.dart';
import '../../estoque/presentation/estoque_providers.dart';
import '../domain/sku.dart';
import 'produto_form_page.dart';
import 'produto_permissions.dart';
import 'produto_providers.dart';

class SkuDetailPage extends ConsumerWidget {
  final String skuId;

  const SkuDetailPage({
    super.key,
    required this.skuId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skuAsync = ref.watch(skuByIdProvider(skuId));
    final appUser = ref.watch(appUserProvider).value;
    final podeEditar = podeEditarProduto(appUser);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes do produto'),
      ),
      body: skuAsync.when(
        data: (sku) {
          if (sku == null) {
            return const _EstadoCarregamento(
              icon: Icons.search_off_outlined,
              titulo: 'SKU não encontrado',
              mensagem: 'Não foi possível localizar este SKU.',
            );
          }

          final produtoAsync =
          ref.watch(produtoByIdProvider(sku.produtoId));

          final saldoAsync = ref.watch(
            saldoProvider(
              (
              localId: LocalEstoque.central,
              produtoId: skuId,
              ),
            ),
          );

          return produtoAsync.when(
            data: (produto) {
              if (produto == null) {
                return const _EstadoCarregamento(
                  icon: Icons.inventory_2_outlined,
                  titulo: 'Produto não encontrado',
                  mensagem:
                  'O produto vinculado a este SKU não foi localizado.',
                );
              }

              final fotoUrl = produto.fotoUrl?.trim();
              final temFoto =
                  fotoUrl != null && fotoUrl.isNotEmpty;

              final modelo =
              produto.modelo?.trim();

              return LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop =
                      constraints.maxWidth >= 900;

                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      isDesktop ? 24 : 16,
                      20,
                      isDesktop ? 24 : 16,
                      32,
                    ),
                    child: ResponsiveCenter(
                      maxWidth: 1120,
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.stretch,
                        children: [
                          if (isDesktop)
                            _CabecalhoDesktop(
                              nome: produto.descricao,
                              modelo: modelo,
                              variacao: sku.variacao,
                              codigoInterno:
                              sku.codigoInterno,
                              status: sku.status,
                              podeEditar: podeEditar,
                              onEditar: () {
                                _abrirEdicao(
                                  context,
                                  produto.id,
                                  sku.id,
                                );
                              },
                            ),

                          if (isDesktop)
                            const SizedBox(height: 20),

                          if (isDesktop)
                            Row(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 330,
                                  child: _CardImagemProduto(
                                    fotoUrl:
                                    temFoto ? fotoUrl : null,
                                    descricao:
                                    produto.descricao,
                                    modelo: modelo,
                                    variacao:
                                    sku.variacao,
                                    codigoInterno:
                                    sku.codigoInterno,
                                    status: sku.status,
                                    mostrarNome: false,
                                  ),
                                ),

                                const SizedBox(width: 20),

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment
                                        .stretch,
                                    children: [
                                      _MetricasPrincipais(
                                        sku: sku,
                                        saldoAsync:
                                        saldoAsync,
                                      ),

                                      _buildAvisoEstoque(
                                        saldoAsync,
                                        sku.estoqueMinimo,
                                      ),

                                      const SizedBox(
                                        height: 16,
                                      ),

                                      _CardSecao(
                                        titulo:
                                        'Informações do produto',
                                        icone: Icons
                                            .inventory_2_outlined,
                                        child: Column(
                                          children: [
                                            _LinhaInfo(
                                              label:
                                              'Categoria',
                                              valor:
                                              produto.categoria,
                                            ),
                                            if (modelo !=
                                                null &&
                                                modelo
                                                    .isNotEmpty)
                                              _LinhaInfo(
                                                label:
                                                'Modelo',
                                                valor:
                                                modelo,
                                              ),
                                            if (produto
                                                .fabricante !=
                                                null &&
                                                produto
                                                    .fabricante!
                                                    .trim()
                                                    .isNotEmpty)
                                              _LinhaInfo(
                                                label:
                                                'Fabricante',
                                                valor: produto
                                                    .fabricante!,
                                              ),
                                          ],
                                        ),
                                      ),

                                      const SizedBox(
                                        height: 16,
                                      ),

                                      _CardSecao(
                                        titulo:
                                        'Identificação do SKU',
                                        icone: Icons
                                            .qr_code_2_outlined,
                                        child: Column(
                                          children: [
                                            _LinhaInfo(
                                              label:
                                              'Código interno',
                                              valor: sku
                                                  .codigoInterno,
                                              copiavel:
                                              true,
                                            ),
                                            if (sku.codigoBarras !=
                                                null &&
                                                sku.codigoBarras!
                                                    .trim()
                                                    .isNotEmpty)
                                              _LinhaInfo(
                                                label:
                                                'GTIN/EAN',
                                                valor: sku
                                                    .codigoBarras!,
                                                copiavel:
                                                true,
                                              ),
                                            if (sku.variacao !=
                                                null &&
                                                sku.variacao!
                                                    .trim()
                                                    .isNotEmpty)
                                              _LinhaInfo(
                                                label:
                                                'Variação',
                                                valor: sku
                                                    .variacao!,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          else ...[
                            _CardImagemProduto(
                              fotoUrl:
                              temFoto ? fotoUrl : null,
                              descricao:
                              produto.descricao,
                              modelo: modelo,
                              variacao: sku.variacao,
                              codigoInterno:
                              sku.codigoInterno,
                              status: sku.status,
                              mostrarNome: true,
                            ),

                            const SizedBox(height: 16),

                            _MetricasPrincipais(
                              sku: sku,
                              saldoAsync: saldoAsync,
                            ),

                            _buildAvisoEstoque(
                              saldoAsync,
                              sku.estoqueMinimo,
                            ),

                            const SizedBox(height: 16),

                            _CardSecao(
                              titulo:
                              'Informações do produto',
                              icone:
                              Icons.inventory_2_outlined,
                              child: Column(
                                children: [
                                  _LinhaInfo(
                                    label: 'Categoria',
                                    valor:
                                    produto.categoria,
                                  ),
                                  if (modelo != null &&
                                      modelo.isNotEmpty)
                                    _LinhaInfo(
                                      label: 'Modelo',
                                      valor: modelo,
                                    ),
                                  if (produto.fabricante !=
                                      null &&
                                      produto.fabricante!
                                          .trim()
                                          .isNotEmpty)
                                    _LinhaInfo(
                                      label:
                                      'Fabricante',
                                      valor: produto
                                          .fabricante!,
                                    ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            _CardSecao(
                              titulo:
                              'Identificação do SKU',
                              icone:
                              Icons.qr_code_2_outlined,
                              child: Column(
                                children: [
                                  _LinhaInfo(
                                    label:
                                    'Código interno',
                                    valor:
                                    sku.codigoInterno,
                                    copiavel: true,
                                  ),
                                  if (sku.codigoBarras !=
                                      null &&
                                      sku.codigoBarras!
                                          .trim()
                                          .isNotEmpty)
                                    _LinhaInfo(
                                      label: 'GTIN/EAN',
                                      valor:
                                      sku.codigoBarras!,
                                      copiavel: true,
                                    ),
                                  if (sku.variacao != null &&
                                      sku.variacao!
                                          .trim()
                                          .isNotEmpty)
                                    _LinhaInfo(
                                      label: 'Variação',
                                      valor:
                                      sku.variacao!,
                                    ),
                                ],
                              ),
                            ),

                            if (podeEditar) ...[
                              const SizedBox(height: 20),
                              SizedBox(
                                height: 48,
                                child:
                                FilledButton.icon(
                                  onPressed: () {
                                    _abrirEdicao(
                                      context,
                                      produto.id,
                                      sku.id,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                  ),
                                  label: const Text(
                                    'Editar produto',
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(),
            ),
            error: (e, st) {
              debugPrint(
                'Erro ao carregar produto: $e\n$st',
              );

              return const _EstadoCarregamento(
                icon: Icons.cloud_off_outlined,
                titulo:
                'Não foi possível carregar o produto',
                mensagem:
                'Tente novamente em alguns instantes.',
              );
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (e, st) {
          debugPrint(
            'Erro ao carregar SKU: $e\n$st',
          );

          return const _EstadoCarregamento(
            icon: Icons.cloud_off_outlined,
            titulo:
            'Não foi possível carregar o SKU',
            mensagem:
            'Tente novamente em alguns instantes.',
          );
        },
      ),
    );
  }

  Widget _buildAvisoEstoque(
      AsyncValue<int> saldoAsync,
      int estoqueMinimo,
      ) {
    return saldoAsync.when(
      data: (saldo) {
        if (saldo > estoqueMinimo) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(
            top: 16,
          ),
          child: _AvisoEstoqueBaixo(
            saldo: saldo,
            estoqueMinimo: estoqueMinimo,
          ),
        );
      },
      loading: () =>
      const SizedBox.shrink(),
      error: (_, __) =>
      const SizedBox.shrink(),
    );
  }

  static void _abrirEdicao(
      BuildContext context,
      String? produtoId,
      String? skuId,
      ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProdutoFormPage(
          produtoId: produtoId,
          skuId: skuId,
        ),
      ),
    );
  }

  static String _statusLabel(
      SkuStatus status,
      ) =>
      switch (status) {
        SkuStatus.active => 'Ativo',
        SkuStatus.blockedForSale =>
        'Bloqueado para venda',
        SkuStatus.discontinued =>
        'Descontinuado',
      };
}

class _CabecalhoDesktop extends StatelessWidget {
  const _CabecalhoDesktop({
    required this.nome,
    required this.modelo,
    required this.variacao,
    required this.codigoInterno,
    required this.status,
    required this.podeEditar,
    required this.onEditar,
  });

  final String nome;
  final String? modelo;
  final String? variacao;
  final String codigoInterno;
  final SkuStatus status;
  final bool podeEditar;
  final VoidCallback onEditar;

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                nome,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(
                  fontWeight:
                  FontWeight.w800,
                ),
              ),

              if (modelo != null &&
                  modelo!.trim().isNotEmpty) ...[
                const SizedBox(height: 7),
                _LinhaResumoProduto(
                  label: 'Modelo',
                  valor: modelo!,
                ),
              ],

              if (variacao != null &&
                  variacao!
                      .trim()
                      .isNotEmpty) ...[
                const SizedBox(height: 4),
                _LinhaResumoProduto(
                  label: 'Variação',
                  valor: variacao!,
                ),
              ],

              const SizedBox(height: 4),

              Text(
                'Cód. $codigoInterno',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(
                  color: colorScheme
                      .onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 10),

              _StatusChip(
                status: status,
              ),
            ],
          ),
        ),

        if (podeEditar) ...[
          const SizedBox(width: 16),
          FilledButton.tonalIcon(
            onPressed: onEditar,
            icon: const Icon(
              Icons.edit_outlined,
            ),
            label: const Text(
              'Editar produto',
            ),
          ),
        ],
      ],
    );
  }
}

class _LinhaResumoProduto extends StatelessWidget {
  final String label;
  final String valor;

  const _LinhaResumoProduto({
    required this.label,
    required this.valor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        Theme.of(context).colorScheme;

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(
              color: colorScheme
                  .onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          TextSpan(
            text: valor,
            style: TextStyle(
              color:
              colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      style:
      Theme.of(context).textTheme.bodyMedium,
    );
  }
}

class _CardImagemProduto extends StatelessWidget {
  const _CardImagemProduto({
    required this.fotoUrl,
    required this.descricao,
    required this.modelo,
    required this.variacao,
    required this.codigoInterno,
    required this.status,
    required this.mostrarNome,
  });

  final String? fotoUrl;
  final String descricao;
  final String? modelo;
  final String? variacao;
  final String codigoInterno;
  final SkuStatus status;
  final bool mostrarNome;

  void _abrirImagem(
      BuildContext context,
      ) {
    if (fotoUrl == null) {
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final colorScheme =
            Theme.of(dialogContext)
                .colorScheme;

        return Dialog(
          insetPadding:
          const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints:
            const BoxConstraints(
              maxWidth: 760,
              maxHeight: 760,
            ),
            child: Column(
              mainAxisSize:
              MainAxisSize.min,
              children: [
                Padding(
                  padding:
                  const EdgeInsets.fromLTRB(
                    16,
                    10,
                    8,
                    8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          descricao,
                          maxLines: 1,
                          overflow:
                          TextOverflow.ellipsis,
                          style: Theme.of(
                            dialogContext,
                          )
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                            fontWeight:
                            FontWeight
                                .w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        onPressed: () {
                          Navigator.of(
                            dialogContext,
                          ).pop();
                        },
                        icon: const Icon(
                          Icons.close,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: Container(
                    color: colorScheme
                        .surfaceContainerHighest,
                    alignment: Alignment.center,
                    padding:
                    const EdgeInsets.all(
                      16,
                    ),
                    child:
                    InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 5,
                      child: Image.network(
                        fotoUrl!,
                        fit: BoxFit.contain,
                        errorBuilder:
                            (_, __, ___) {
                          return Icon(
                            Icons
                                .broken_image_outlined,
                            size: 80,
                            color: colorScheme
                                .onSurfaceVariant,
                          );
                        },
                        loadingBuilder: (
                            context,
                            child,
                            progress,
                            ) {
                          if (progress ==
                              null) {
                            return child;
                          }

                          return const Center(
                            child:
                            CircularProgressIndicator(),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color:
      colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius:
        BorderRadius.circular(18),
        side: BorderSide(
          color:
          colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding:
        const EdgeInsets.all(16),
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius:
                BorderRadius.circular(
                  14,
                ),
                onTap: fotoUrl == null
                    ? null
                    : () {
                  _abrirImagem(
                    context,
                  );
                },
                child: Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius:
                        BorderRadius.circular(
                          14,
                        ),
                        child: Container(
                          color: colorScheme
                              .surfaceContainerHighest,
                          padding:
                          const EdgeInsets.all(
                            12,
                          ),
                          child: fotoUrl !=
                              null
                              ? Image.network(
                            fotoUrl!,
                            fit: BoxFit
                                .contain,
                            errorBuilder:
                                (_, __,
                                ___) {
                              return Icon(
                                Icons
                                    .broken_image_outlined,
                                size: 64,
                                color: colorScheme
                                    .onSurfaceVariant,
                              );
                            },
                            loadingBuilder:
                                (
                                context,
                                child,
                                progress,
                                ) {
                              if (progress ==
                                  null) {
                                return child;
                              }

                              return const Center(
                                child:
                                CircularProgressIndicator(),
                              );
                            },
                          )
                              : Icon(
                            Icons
                                .inventory_2_outlined,
                            size: 72,
                            color: colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),

                    if (fotoUrl != null)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration:
                          BoxDecoration(
                            color: colorScheme
                                .surface
                                .withValues(
                              alpha: .92,
                            ),
                            borderRadius:
                            BorderRadius
                                .circular(
                              10,
                            ),
                            border: Border.all(
                              color: colorScheme
                                  .outlineVariant,
                            ),
                          ),
                          child: Icon(
                            Icons
                                .zoom_in_rounded,
                            size: 21,
                            color: colorScheme
                                .primary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            if (mostrarNome) ...[
              const SizedBox(height: 18),

              Align(
                alignment:
                Alignment.centerLeft,
                child: Text(
                  descricao,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                    fontWeight:
                    FontWeight.w800,
                  ),
                ),
              ),

              if (modelo != null &&
                  modelo!
                      .trim()
                      .isNotEmpty) ...[
                const SizedBox(height: 7),
                Align(
                  alignment:
                  Alignment.centerLeft,
                  child:
                  _LinhaResumoProduto(
                    label: 'Modelo',
                    valor: modelo!,
                  ),
                ),
              ],

              if (variacao != null &&
                  variacao!
                      .trim()
                      .isNotEmpty) ...[
                const SizedBox(height: 4),
                Align(
                  alignment:
                  Alignment.centerLeft,
                  child:
                  _LinhaResumoProduto(
                    label: 'Variação',
                    valor: variacao!,
                  ),
                ),
              ],

              const SizedBox(height: 4),

              Align(
                alignment:
                Alignment.centerLeft,
                child: Text(
                  'Cód. $codigoInterno',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                    color: colorScheme
                        .onSurfaceVariant,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Align(
                alignment:
                Alignment.centerLeft,
                child: _StatusChip(
                  status: status,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricasPrincipais
    extends StatelessWidget {
  const _MetricasPrincipais({
    required this.sku,
    required this.saldoAsync,
  });

  final Sku sku;
  final AsyncValue<int> saldoAsync;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _MetricaCard(
        icon: Icons.sell_outlined,
        label: 'Preço de venda',
        valor: formatarCentavos(
          sku.precoVendaCentavos,
        ),
      ),
      _MetricaCard(
        icon:
        Icons.inventory_2_outlined,
        label: 'Saldo central',
        valor: saldoAsync.when(
          data: (saldo) => '$saldo un.',
          loading: () => '...',
          error: (_, __) => '—',
        ),
      ),
      _MetricaCard(
        icon: Icons.payments_outlined,
        label: 'Custo inicial',
        valor: formatarCentavos(
          sku.custoInicialCentavos,
        ),
      ),
      _MetricaCard(
        icon:
        Icons.warning_amber_rounded,
        label: 'Estoque mínimo',
        valor:
        '${sku.estoqueMinimo} un.',
      ),
    ];

    return LayoutBuilder(
      builder: (
          context,
          constraints,
          ) {
        const spacing = 10.0;

        final duasColunas =
            constraints.maxWidth >= 350;

        if (!duasColunas) {
          return Column(
            children: [
              for (var i = 0;
              i < cards.length;
              i++) ...[
                cards[i],
                if (i <
                    cards.length - 1)
                  const SizedBox(
                    height: 10,
                  ),
              ],
            ],
          );
        }

        final largura =
            (constraints.maxWidth -
                spacing) /
                2;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards)
              SizedBox(
                width: largura,
                child: card,
              ),
          ],
        );
      },
    );
  }
}

class _MetricaCard extends StatelessWidget {
  const _MetricaCard({
    required this.icon,
    required this.label,
    required this.valor,
  });

  final IconData icon;
  final String label;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (
          context,
          constraints,
          ) {
        final compacto =
            constraints.maxWidth < 210;

        if (compacto) {
          return Container(
            constraints:
            const BoxConstraints(
              minHeight: 112,
            ),
            padding:
            const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: colorScheme
                  .surfaceContainerLow,
              borderRadius:
              BorderRadius.circular(
                16,
              ),
              border: Border.all(
                color: colorScheme
                    .outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              mainAxisAlignment:
              MainAxisAlignment.center,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration:
                  BoxDecoration(
                    color: colorScheme
                        .primaryContainer,
                    borderRadius:
                    BorderRadius.circular(
                      10,
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: colorScheme
                        .onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  label,
                  maxLines: 1,
                  overflow:
                  TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                    color: colorScheme
                        .onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  valor,
                  maxLines: 1,
                  overflow:
                  TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(
                    fontWeight:
                    FontWeight.w800,
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          constraints:
          const BoxConstraints(
            minHeight: 92,
          ),
          padding:
          const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colorScheme
                .surfaceContainerLow,
            borderRadius:
            BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme
                  .outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration:
                BoxDecoration(
                  color: colorScheme
                      .primaryContainer,
                  borderRadius:
                  BorderRadius.circular(
                    12,
                  ),
                ),
                child: Icon(
                  icon,
                  color: colorScheme
                      .onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment:
                  MainAxisAlignment
                      .center,
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(
                        context,
                      )
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                        color: colorScheme
                            .onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(
                      height: 4,
                    ),
                    Text(
                      valor,
                      maxLines: 1,
                      overflow:
                      TextOverflow
                          .ellipsis,
                      style: Theme.of(
                        context,
                      )
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                        fontWeight:
                        FontWeight
                            .w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CardSecao extends StatelessWidget {
  const _CardSecao({
    required this.titulo,
    required this.icone,
    required this.child,
  });

  final String titulo;
  final IconData icone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color:
      colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius:
        BorderRadius.circular(16),
        side: BorderSide(
          color:
          colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding:
        const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          8,
        ),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  icone,
                  size: 20,
                  color:
                  colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  titulo,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(
                    fontWeight:
                    FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            child,
          ],
        ),
      ),
    );
  }
}

class _LinhaInfo extends StatelessWidget {
  const _LinhaInfo({
    required this.label,
    required this.valor,
    this.copiavel = false,
    this.trailing,
  });

  final String label;
  final String valor;
  final bool copiavel;
  final Widget? trailing;

  Future<void> _copiar(
      BuildContext context,
      ) async {
    await Clipboard.setData(
      ClipboardData(
        text: valor,
      ),
    );

    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content:
          Text('$label copiado.'),
          behavior:
          SnackBarBehavior.floating,
          duration:
          const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        Theme.of(context).colorScheme;

    return Padding(
      padding:
      const EdgeInsets.symmetric(
        vertical: 11,
      ),
      child: LayoutBuilder(
        builder: (
            context,
            constraints,
            ) {
          final compacto =
              constraints.maxWidth < 520;

          if (compacto) {
            return Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                    color: colorScheme
                        .onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        valor,
                        style:
                        const TextStyle(
                          fontWeight:
                          FontWeight.w700,
                        ),
                      ),
                    ),
                    if (trailing !=
                        null) ...[
                      const SizedBox(
                        width: 10,
                      ),
                      trailing!,
                    ],
                    if (copiavel)
                      IconButton(
                        tooltip: 'Copiar',
                        onPressed: () =>
                            _copiar(context),
                        visualDensity:
                        VisualDensity
                            .compact,
                        icon: const Icon(
                          Icons
                              .content_copy_outlined,
                          size: 18,
                        ),
                      ),
                  ],
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment:
            CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 150,
                child: Text(
                  label,
                  style: TextStyle(
                    color: colorScheme
                        .onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  valor,
                  style:
                  const TextStyle(
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                trailing!,
              ],
              if (copiavel)
                IconButton(
                  tooltip: 'Copiar',
                  onPressed: () =>
                      _copiar(context),
                  visualDensity:
                  VisualDensity.compact,
                  icon: const Icon(
                    Icons
                        .content_copy_outlined,
                    size: 18,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.status,
  });

  final SkuStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        Theme.of(context).colorScheme;

    final (label, icon, color) =
    switch (status) {
      SkuStatus.active => (
      'ATIVO',
      Icons.check_circle_outline,
      colorScheme.primary,
      ),
      SkuStatus.blockedForSale => (
      'BLOQUEADO',
      Icons.block_outlined,
      colorScheme.error,
      ),
      SkuStatus.discontinued => (
      'DESCONTINUADO',
      Icons.archive_outlined,
      colorScheme.onSurfaceVariant,
      ),
    };

    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color:
        color.withValues(alpha: 0.10),
        borderRadius:
        BorderRadius.circular(100),
        border: Border.all(
          color:
          color.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize:
        MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(
              color: color,
              fontWeight:
              FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvisoEstoqueBaixo extends StatelessWidget {
  const _AvisoEstoqueBaixo({
    required this.saldo,
    required this.estoqueMinimo,
  });

  final int saldo;
  final int estoqueMinimo;

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        Theme.of(context).colorScheme;

    return Container(
      padding:
      const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme
            .errorContainer
            .withValues(alpha: 0.45),
        borderRadius:
        BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.error
              .withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              saldo <= 0
                  ? 'Sem estoque no estoque central. '
                  'O mínimo configurado é $estoqueMinimo un.'
                  : 'Estoque baixo: $saldo un. disponíveis '
                  'para um mínimo de $estoqueMinimo un.',
              style: TextStyle(
                color: colorScheme
                    .onErrorContainer,
                fontWeight:
                FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EstadoCarregamento
    extends StatelessWidget {
  const _EstadoCarregamento({
    required this.icon,
    required this.titulo,
    required this.mensagem,
  });

  final IconData icon;
  final String titulo;
  final String mensagem;

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding:
        const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints:
          const BoxConstraints(
            maxWidth: 420,
          ),
          child: Column(
            mainAxisAlignment:
            MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 58,
                color: colorScheme
                    .onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                titulo,
                textAlign:
                TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(
                  fontWeight:
                  FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                mensagem,
                textAlign:
                TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(
                  color: colorScheme
                      .onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}