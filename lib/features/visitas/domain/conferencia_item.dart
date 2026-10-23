/// Classificação obrigatória de toda diferença encontrada na
/// conferência — ver seção 7.6 do Blueprint.
///
/// Somente "vendido" entra no cálculo do acerto financeiro.
enum ClassificacaoDiferenca {
  vendido,
  avaria,
  extravio,
  devolvido,
  erroDeEstoque,
  outro,
}

/// Converte o valor salvo no Firestore para a classificação.
///
/// IMPORTANTE:
/// Se o valor estiver vazio, nulo ou for desconhecido,
/// retorna null.
///
/// Nunca assume "vendido" automaticamente, pois isso poderia
/// gerar uma cobrança incorreta.
ClassificacaoDiferenca? _classificacaoFromString(String? valor) {
  final texto = valor?.trim();

  if (texto == null || texto.isEmpty) {
    return null;
  }

  for (final classificacao in ClassificacaoDiferenca.values) {
    if (classificacao.name == texto) {
      return classificacao;
    }
  }

  return null;
}

String classificacaoToString(
    ClassificacaoDiferenca classificacao,
    ) {
  return classificacao.name;
}

/// Um item conferido durante a visita.
///
/// Guarda:
/// - o produto;
/// - a descrição registrada naquele momento;
/// - a quantidade esperada;
/// - a quantidade encontrada;
/// - a classificação da diferença;
/// - uma eventual observação.
///
/// Somente diferenças classificadas como "vendido"
/// entram no acerto financeiro.
class ConferenciaItem {
  final String produtoId;
  final String descricaoSnapshot;

  final int quantidadeEsperada;
  final int quantidadeEncontrada;

  final ClassificacaoDiferenca? classificacaoDiferenca;

  final String? observacao;

  const ConferenciaItem({
    required this.produtoId,
    required this.descricaoSnapshot,
    required this.quantidadeEsperada,
    required this.quantidadeEncontrada,
    this.classificacaoDiferenca,
    this.observacao,
  });

  /// Diferença entre o que deveria existir e o que foi encontrado.
  ///
  /// Exemplo:
  ///
  /// Esperado: 5
  /// Encontrado: 3
  /// Diferença: 2
  ///
  /// Se o resultado for negativo, significa que foi encontrada
  /// uma quantidade maior do que a esperada.
  int get diferenca {
    return quantidadeEsperada - quantidadeEncontrada;
  }

  /// Existe qualquer diferença entre esperado e encontrado.
  bool get temDiferenca {
    return diferenca != 0;
  }

  /// Existem unidades faltando.
  bool get temFalta {
    return diferenca > 0;
  }

  /// Existem unidades sobrando em relação ao esperado.
  bool get temSobra {
    return diferenca < 0;
  }

  /// Informa se existe diferença e o vendedor ainda precisa
  /// informar o motivo.
  bool get precisaClassificacao {
    return temDiferenca && classificacaoDiferenca == null;
  }

  /// A conferência está corretamente classificada.
  ///
  /// Se não existe diferença, não é necessário classificar.
  bool get classificacaoValida {
    if (!temDiferenca) {
      return true;
    }

    return classificacaoDiferenca != null;
  }

  /// Somente unidades classificadas como "vendido"
  /// entram no acerto financeiro.
  ///
  /// Nunca retorna quantidade negativa.
  int get quantidadeVendida {
    if (classificacaoDiferenca != ClassificacaoDiferenca.vendido) {
      return 0;
    }

    if (diferenca <= 0) {
      return 0;
    }

    return diferenca;
  }

  ConferenciaItem copyWith({
    String? produtoId,
    String? descricaoSnapshot,
    int? quantidadeEsperada,
    int? quantidadeEncontrada,
    ClassificacaoDiferenca? classificacaoDiferenca,
    String? observacao,
    bool limparClassificacao = false,
    bool limparObservacao = false,
  }) {
    return ConferenciaItem(
      produtoId:
      produtoId ?? this.produtoId,
      descricaoSnapshot:
      descricaoSnapshot ?? this.descricaoSnapshot,
      quantidadeEsperada:
      quantidadeEsperada ?? this.quantidadeEsperada,
      quantidadeEncontrada:
      quantidadeEncontrada ?? this.quantidadeEncontrada,
      classificacaoDiferenca: limparClassificacao
          ? null
          : classificacaoDiferenca ?? this.classificacaoDiferenca,
      observacao: limparObservacao
          ? null
          : observacao ?? this.observacao,
    );
  }

  factory ConferenciaItem.fromMap(
      Map<String, dynamic> data,
      ) {
    final observacao =
    (data['observacao'] as String?)?.trim();

    return ConferenciaItem(
      produtoId:
      (data['produtoId'] as String?)?.trim() ?? '',

      descricaoSnapshot:
      (data['descricaoSnapshot'] as String?)?.trim() ?? '',

      quantidadeEsperada:
      (data['quantidadeEsperada'] as num?)?.toInt() ?? 0,

      quantidadeEncontrada:
      (data['quantidadeEncontrada'] as num?)?.toInt() ?? 0,

      classificacaoDiferenca:
      _classificacaoFromString(
        data['classificacaoDiferenca'] as String?,
      ),

      observacao:
      observacao == null || observacao.isEmpty
          ? null
          : observacao,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'produtoId': produtoId,
      'descricaoSnapshot': descricaoSnapshot,
      'quantidadeEsperada': quantidadeEsperada,
      'quantidadeEncontrada': quantidadeEncontrada,
      'classificacaoDiferenca':
      classificacaoDiferenca != null
          ? classificacaoToString(
        classificacaoDiferenca!,
      )
          : null,
      'observacao': observacao,
    };
  }
}