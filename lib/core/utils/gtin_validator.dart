/// Valida o formato e o dígito verificador de um GTIN/EAN.
///
/// Aceita 8, 12, 13 ou 14 dígitos — o algoritmo do dígito verificador
/// é o mesmo pra todos os tamanhos: pesos alternados 3/1, começando em
/// 3 no dígito imediatamente à esquerda do verificador.
bool gtinValido(String codigo) {
  if (!RegExp(r'^(\d{8}|\d{12}|\d{13}|\d{14})$').hasMatch(codigo)) {
    return false;
  }

  final digitos = codigo.split('').map(int.parse).toList();
  final digitoVerificador = digitos.removeLast();
  final invertido = digitos.reversed.toList();

  var soma = 0;
  for (var i = 0; i < invertido.length; i++) {
    final peso = i.isEven ? 3 : 1;
    soma += invertido[i] * peso;
  }

  final calculado = (10 - (soma % 10)) % 10;
  return calculado == digitoVerificador;
}
