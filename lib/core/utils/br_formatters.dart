import 'package:flutter/services.dart';

/// Formata CPF (11 dígitos) ou CNPJ (14 dígitos) enquanto o usuário
/// digita, detectando automaticamente qual dos dois pelo tamanho.
class CpfCnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitos = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final limitados = digitos.length > 14 ? digitos.substring(0, 14) : digitos;
    final texto = formatarCpfCnpj(limitados);
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

/// Formata um CPF/CNPJ (só números) pro padrão brasileiro de exibição.
/// Detecta automaticamente pelo tamanho: até 11 dígitos vira CPF, mais
/// que isso vira CNPJ. Tamanhos incompletos ficam parcialmente
/// formatados — útil tanto durante a digitação quanto pra exibir um
/// documento salvo.
String formatarCpfCnpj(String valor) {
  final limpo = valor.replaceAll(RegExp(r'[^0-9]'), '');
  if (limpo.length <= 11) {
    final buffer = StringBuffer();
    for (var i = 0; i < limpo.length; i++) {
      if (i == 3 || i == 6) buffer.write('.');
      if (i == 9) buffer.write('-');
      buffer.write(limpo[i]);
    }
    return buffer.toString();
  }
  final buffer = StringBuffer();
  for (var i = 0; i < limpo.length; i++) {
    if (i == 2 || i == 5) buffer.write('.');
    if (i == 8) buffer.write('/');
    if (i == 12) buffer.write('-');
    buffer.write(limpo[i]);
  }
  return buffer.toString();
}

/// Formata telefone (10 ou 11 dígitos) enquanto o usuário digita.
class TelefoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitos = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final limitados = digitos.length > 11 ? digitos.substring(0, 11) : digitos;
    final texto = formatarTelefone(limitados);
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

/// Formata um telefone (só números) pro padrão brasileiro:
/// (00) 0000-0000 pra fixo (10 dígitos) ou (00) 00000-0000 pra
/// celular (11 dígitos).
String formatarTelefone(String valor) {
  final limpo = valor.replaceAll(RegExp(r'[^0-9]'), '');
  final buffer = StringBuffer();
  for (var i = 0; i < limpo.length; i++) {
    if (i == 0) buffer.write('(');
    if (i == 2) buffer.write(') ');
    if (limpo.length <= 10) {
      if (i == 6) buffer.write('-');
    } else {
      if (i == 7) buffer.write('-');
    }
    buffer.write(limpo[i]);
  }
  return buffer.toString();
}

/// Formata CEP (8 dígitos) como 00000-000 enquanto o usuário digita.
class CepInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitos = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final limitados = digitos.length > 8 ? digitos.substring(0, 8) : digitos;
    final buffer = StringBuffer();
    for (var i = 0; i < limitados.length; i++) {
      if (i == 5) buffer.write('-');
      buffer.write(limitados[i]);
    }
    final texto = buffer.toString();
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}
