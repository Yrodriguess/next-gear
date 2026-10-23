/// Ver seção 5.3 e 7.2 do Blueprint.
class LimiteExcedidoException implements Exception {
  final int excedenteCentavos;
  LimiteExcedidoException(this.excedenteCentavos);

  @override
  String toString() =>
      'Nova consignação excede o limite em R\$ ${(excedenteCentavos / 100).toStringAsFixed(2)}. '
          'Necessário recolher produtos antes de finalizar.';
}

/// Ver seção 5.3 do Blueprint — cliente inadimplente não recebe
/// reposição, só pode ter a consignação reduzida ou encerrada.
class ReposicaoBloqueadaException implements Exception {
  @override
  String toString() =>
      'Cliente inadimplente: não é permitida entrada de novas unidades nesta visita.';
}