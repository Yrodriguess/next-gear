import 'package:flutter_test/flutter_test.dart';
import 'package:next_gear/features/visitas/domain/conferencia_item.dart';

void main() {
  ConferenciaItem conferencia({
    int esperada = 5,
    int encontrada = 3,
    ClassificacaoDiferenca? classificacao,
  }) {
    return ConferenciaItem(
      produtoId: 'sku-1',
      descricaoSnapshot: 'Cabo USB-C',
      quantidadeEsperada: esperada,
      quantidadeEncontrada: encontrada,
      classificacaoDiferenca: classificacao,
    );
  }

  group('ConferenciaItem', () {
    test('falta classificada como vendido entra no acerto', () {
      final item = conferencia(classificacao: ClassificacaoDiferenca.vendido);

      expect(item.diferenca, 2);
      expect(item.temFalta, isTrue);
      expect(item.quantidadeVendida, 2);
    });

    test('avaria, extravio e devolução não contam como venda', () {
      for (final classificacao in [
        ClassificacaoDiferenca.avaria,
        ClassificacaoDiferenca.extravio,
        ClassificacaoDiferenca.devolvido,
      ]) {
        expect(
          conferencia(classificacao: classificacao).quantidadeVendida,
          0,
          reason: classificacao.name,
        );
      }
    });

    test('diferença sem classificação bloqueia a conferência', () {
      final item = conferencia();

      expect(item.precisaClassificacao, isTrue);
      expect(item.classificacaoValida, isFalse);
    });

    test('sem diferença não precisa de classificação', () {
      final item = conferencia(encontrada: 5);

      expect(item.temDiferenca, isFalse);
      expect(item.classificacaoValida, isTrue);
    });

    test('sobra nunca vira venda', () {
      final item = conferencia(
        esperada: 2,
        encontrada: 4,
        classificacao: ClassificacaoDiferenca.vendido,
      );

      expect(item.temSobra, isTrue);
      expect(item.quantidadeVendida, 0);
    });

    test('fromMap não assume vendido para classificação desconhecida', () {
      final item = ConferenciaItem.fromMap({
        'produtoId': ' sku-1 ',
        'descricaoSnapshot': 'Cabo USB-C',
        'quantidadeEsperada': 5,
        'quantidadeEncontrada': 3.0,
        'classificacaoDiferenca': 'qualquer-coisa',
      });

      expect(item.produtoId, 'sku-1');
      expect(item.quantidadeEncontrada, 3);
      expect(item.classificacaoDiferenca, isNull);
      expect(item.quantidadeVendida, 0);
    });
  });
}