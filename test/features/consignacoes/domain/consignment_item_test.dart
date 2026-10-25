import 'package:flutter_test/flutter_test.dart';
import 'package:next_gear/features/consignacoes/domain/consignment_item.dart';

void main() {
  group('ConsignmentItem.calcular', () {
    test('separa a comissão do cliente e o líquido da NEXT GEAR', () {
      final item = ConsignmentItem.calcular(
        produtoId: 'sku-1',
        descricaoSnapshot: 'Cabo USB-C',
        quantidade: 4,
        precoVendaCentavos: 1000,
        custoAquisicaoCentavos: 400,
        comissaoBasisPoints: 3000,
      );

      expect(item.comissaoCentavos, 300);
      expect(item.valorLiquidoCentavos, 700);
      expect(item.valorVendaTotalCentavos, 4000);
      expect(item.valorLiquidoTotalCentavos, 2800);
    });

    test('arredonda meio centavo para cima', () {
      final item = ConsignmentItem.calcular(
        produtoId: 'sku-2',
        descricaoSnapshot: 'Fone',
        quantidade: 1,
        precoVendaCentavos: 1001,
        custoAquisicaoCentavos: 500,
        comissaoBasisPoints: 5000,
      );

      expect(item.comissaoCentavos, 501);
      expect(item.valorLiquidoCentavos, 500);
    });

    test('arredonda a comissão por unidade, antes de multiplicar', () {
      // Preço de 999 centavos com 15% de comissão:
      // por unidade, 149,85 centavos vira 150 (1.500 em 10 unidades);
      // sobre o total, 9.990 x 15% = 1.498,5 viraria 1.499.
      // O app arredonda por unidade. Se a regra mudar, este teste
      // precisa mudar junto, de propósito.
      final item = ConsignmentItem.calcular(
        produtoId: 'sku-3',
        descricaoSnapshot: 'Carregador',
        quantidade: 10,
        precoVendaCentavos: 999,
        custoAquisicaoCentavos: 500,
        comissaoBasisPoints: 1500,
      );

      expect(item.comissaoCentavos, 150);
      expect(item.valorLiquidoTotalCentavos, 8490);
    });

    test('copyWith muda a quantidade e mantém preço e comissão', () {
      final original = ConsignmentItem.calcular(
        produtoId: 'sku-1',
        descricaoSnapshot: 'Cabo USB-C',
        quantidade: 2,
        precoVendaCentavos: 1000,
        custoAquisicaoCentavos: 400,
        comissaoBasisPoints: 3000,
      );

      final alterado = original.copyWith(quantidade: 5);

      expect(alterado.quantidade, 5);
      expect(alterado.comissaoCentavos, 300);
      expect(alterado.valorLiquidoTotalCentavos, 3500);
    });

    test('toMap e fromMap preservam o snapshot congelado', () {
      final original = ConsignmentItem.calcular(
        produtoId: 'sku-1',
        descricaoSnapshot: 'Cabo USB-C',
        quantidade: 3,
        precoVendaCentavos: 2990,
        custoAquisicaoCentavos: 1200,
        comissaoBasisPoints: 2500,
      );

      final lido = ConsignmentItem.fromMap(original.toMap());

      expect(lido.produtoId, original.produtoId);
      expect(lido.quantidade, original.quantidade);
      expect(lido.precoVendaCentavos, original.precoVendaCentavos);
      expect(lido.comissaoCentavos, original.comissaoCentavos);
      expect(lido.valorLiquidoCentavos, original.valorLiquidoCentavos);
    });
  });
}