import 'package:flutter/services.dart';

/// Formata um campo de texto como dinheiro brasileiro, mantendo o valor
/// real sempre em centavos inteiros — nunca passa por double (seção
/// 15.1 do Blueprint: "dinheiro sempre em centavos inteiros, nunca
/// float/double").
///
/// Cada dígito digitado empurra o valor da direita pra esquerda, como
/// numa calculadora: "2990" no buffer vira "R$ 29,90" na tela. Não tem
/// conversão de string-com-vírgula pra double em nenhum momento.
class MoneyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final apenasDigitos = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final centavos = apenasDigitos.isEmpty ? 0 : int.parse(apenasDigitos);
    final texto = formatarCentavos(centavos);
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

/// Extrai o valor em centavos de um texto já formatado por
/// [MoneyInputFormatter] (ou de qualquer texto só com dígitos).
int centavosFromFormatted(String texto) {
  final apenasDigitos = texto.replaceAll(RegExp(r'[^0-9]'), '');
  return apenasDigitos.isEmpty ? 0 : int.parse(apenasDigitos);
}

/// Formata um valor em centavos como "R$ 29,90".
String formatarCentavos(int centavos) {
  final reais = centavos ~/ 100;
  final cent = (centavos % 100).toString().padLeft(2, '0');
  final reaisFormatado = reais.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]}.',
      );
  return 'R\$ $reaisFormatado,$cent';
}
