import 'package:flutter_test/flutter_test.dart';
import 'package:next_gear/core/utils/br_formatters.dart';
import 'package:next_gear/core/utils/gtin_validator.dart';
import 'package:next_gear/core/utils/money_input_formatter.dart';

void main() {
  group('gtinValido', () {
    test('aceita EAN-13, EAN-8 e UPC-A com dígito verificador correto', () {
      expect(gtinValido('4006381333931'), isTrue);
      expect(gtinValido('7891000315507'), isTrue);
      expect(gtinValido('96385074'), isTrue);
      expect(gtinValido('036000291452'), isTrue);
    });

    test('recusa dígito verificador errado', () {
      expect(gtinValido('4006381333932'), isFalse);
    });

    test('recusa tamanho inválido e caracteres não numéricos', () {
      expect(gtinValido(''), isFalse);
      expect(gtinValido('12345'), isFalse);
      expect(gtinValido('40063813339A1'), isFalse);
    });
  });

  group('dinheiro em centavos', () {
    test('formatarCentavos usa vírgula decimal e ponto de milhar', () {
      expect(formatarCentavos(0), 'R\$ 0,00');
      expect(formatarCentavos(5), 'R\$ 0,05');
      expect(formatarCentavos(100), 'R\$ 1,00');
      expect(formatarCentavos(123456), 'R\$ 1.234,56');
      expect(formatarCentavos(1234567), 'R\$ 12.345,67');
    });

    test('centavosFromFormatted lê o texto formatado de volta', () {
      expect(centavosFromFormatted('R\$ 1.234,56'), 123456);
      expect(centavosFromFormatted(''), 0);
    });

    test('MoneyInputFormatter empurra os dígitos como numa calculadora', () {
      final formatter = MoneyInputFormatter();

      final resultado = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '2990'),
      );

      expect(resultado.text, 'R\$ 29,90');
    });
  });

  group('documentos e telefone', () {
    test('formatarCpfCnpj detecta CPF e CNPJ pelo tamanho', () {
      expect(formatarCpfCnpj('12345678901'), '123.456.789-01');
      expect(formatarCpfCnpj('12345678000195'), '12.345.678/0001-95');
      expect(formatarCpfCnpj('123.456.789-01'), '123.456.789-01');
    });

    test(
      'formatarCpfCnpj mantém as letras do CNPJ alfanumérico',
          () {
        expect(formatarCpfCnpj('12ABC34501DE35'), '12.ABC.345/01DE-35');
      },
      skip: 'Pendente: item 16 da revisão (CNPJ alfanumérico)',
    );

    test('formatarTelefone formata fixo e celular com DDD', () {
      expect(formatarTelefone('6133334444'), '(61) 3333-4444');
      expect(formatarTelefone('61987654321'), '(61) 98765-4321');
    });
  });
}