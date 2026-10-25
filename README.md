# Next Gear

[![CI](https://github.com/Yrodriguess/next-gear/actions/workflows/ci.yml/badge.svg)](https://github.com/Yrodriguess/next-gear/actions/workflows/ci.yml)

**Sistema de gestão de consignação, expositores, estoque e operações comerciais.**

**Tecnologias:** Flutter · Dart · Firebase · Riverpod  
**Plataformas do projeto:** Android e Web  
**Status:** em desenvolvimento — não homologado para produção

## Visão geral

O **Next Gear** é uma aplicação em desenvolvimento para apoiar operações de **venda consignada**. A proposta é acompanhar produtos e expositores desde o cadastro e a instalação no ponto de venda até as visitas de conferência, reposição, emissão de documentos e acompanhamento financeiro.

O projeto foi estruturado para reunir atividades comerciais e operacionais em uma única aplicação, com módulos separados por responsabilidade e interfaces para Android e Web.

> **Nota de transparência:** os módulos relacionados abaixo possuem arquivos no repositório. A presença desses arquivos não significa que todos os fluxos estejam concluídos, testados ou prontos para uso em produção.

## Problema que o projeto busca resolver

Uma operação de consignação pode exigir controles paralelos de estoque, localização de expositores, visitas a clientes, mercadorias movimentadas e valores a receber. O Next Gear procura organizar essas informações e reduzir a dependência de registros dispersos.

O fluxo de negócio modelado pelo projeto envolve:

1. Cadastro de clientes, produtos e SKUs.
2. Cadastro e acompanhamento de modelos e unidades físicas de expositores.
3. Movimentação de estoque e instalação em pontos de venda.
4. Visitas de conferência, reposição ou retirada.
5. Registro de resultados, documentos e assinaturas.
6. Acompanhamento financeiro e relatórios operacionais.

## Módulos encontrados no código

| Módulo | Responsabilidades representadas no repositório |
| --- | --- |
| **Autenticação e usuários** | Login, perfis de usuários e controle de acesso na aplicação. |
| **Clientes** | Cadastro, consulta, edição e dados operacionais de clientes. |
| **Produtos** | Produtos, categorias, SKUs, códigos e imagens. |
| **Estoque** | Saldos, entradas, transferências e movimentações. |
| **Expositores** | Modelos, unidades físicas, status e movimentações. |
| **Consignações** | Entidades e repositórios para operações de consignação. |
| **Visitas** | Instalação, execução, conferência, retirada e resultados. |
| **Financeiro** | Contas a receber, pagamentos e acertos de caixa. |
| **Documentos** | Geração de PDFs e coleta de assinatura. |
| **Relatórios** | Visões de vendas, giro, aging, visitas e expositores. |

## Tecnologias e organização

- **Flutter e Dart:** base das interfaces e da lógica do aplicativo.
- **Riverpod:** gerenciamento de estado utilizado no projeto.
- **Firebase Authentication:** autenticação de usuários.
- **Cloud Firestore:** persistência de dados da aplicação.
- **Cloud Storage:** armazenamento de arquivos e imagens.
- **Android e Web:** plataformas presentes na estrutura do projeto.

A organização do código é **orientada a funcionalidades (feature-first)**. Os módulos podem conter camadas `data/`, `domain/` e `presentation/`, conforme suas necessidades.

```text
lib/
├── core/
│   ├── constants/
│   ├── navigation/
│   ├── providers/
│   ├── shell/
│   ├── theme/
│   ├── utils/
│   └── widgets/
├── features/
│   ├── auth/
│   ├── clientes/
│   ├── consignacoes/
│   ├── estoque/
│   ├── expositores/
│   ├── financeiro/
│   │   └── documentos/
│   ├── produtos/
│   ├── relatorios/
│   └── visitas/
├── firebase_options.dart
└── main.dart
```

Essa separação busca facilitar manutenção, evolução dos fluxos e testes. A qualidade das dependências entre camadas ainda está sujeita a revisão técnica.

## Executar em ambiente de desenvolvimento

### Pré-requisitos

- [Flutter SDK](https://docs.flutter.dev/get-started/install) instalado e configurado.
- Android Studio com plugins Flutter/Dart, ou outra IDE compatível.
- Um emulador/dispositivo Android ou navegador Chrome para executar o app.
- Acesso a um projeto Firebase **de desenvolvimento/testes**, com os serviços necessários habilitados.

### 1. Obter o projeto

> O repositório pode estar privado. Nesse caso, o comando exige uma conta com permissão de acesso.

```bash
git clone https://github.com/Yrodriguess/next-gear.git
cd next-gear
```

### 2. Validar o ambiente e instalar dependências

```bash
flutter doctor
flutter pub get
flutter devices
```

### 3. Verificar a configuração do Firebase

O repositório contém configuração gerada pelo FlutterFire (`lib/firebase_options.dart` e, no Android, `android/app/google-services.json`). Ela identifica um projeto Firebase, **mas não concede permissão de acesso aos dados**.

Para utilizar um projeto Firebase próprio e isolado, configure-o com o [FlutterFire CLI](https://firebase.google.com/docs/flutter/setup) e revise as integrações necessárias. **Não utilize dados reais de clientes nem credenciais administrativas em ambientes de teste.**

### 4. Executar

Para Web:

```bash
flutter run -d chrome
```

Para Android, consulte o ID de um dispositivo com `flutter devices` e utilize:

```bash
flutter run -d <id-do-dispositivo>
```

> A execução bem-sucedida depende das permissões, serviços e regras efetivamente configurados no Firebase do ambiente. Este guia não garante que todos os módulos estejam operacionais.

## Verificações de qualidade

As mesmas verificações rodam localmente e no CI:

```bash
flutter analyze --no-fatal-infos
flutter test
```

O workflow [`ci.yml`](.github/workflows/ci.yml) executa esses comandos no GitHub Actions a cada push na `main` e em todo Pull Request.

**Situação atual:**

- `flutter analyze`: sem erros e sem warnings. Os avisos restantes são do tipo `info` e serão tratados em PRs menores.
- `flutter test`: testes unitários para os cálculos e validações abaixo.

| Arquivo | O que é verificado |
| --- | --- |
| `test/core/formatadores_test.dart` | GTIN (EAN-13, EAN-8 e UPC-A), valores em centavos, CPF/CNPJ e telefone. |
| `test/features/consignacoes/domain/consignment_item_test.dart` | Comissão do cliente, líquido da Next Gear e arredondamento. |
| `test/features/visitas/domain/conferencia_item_test.dart` | Conferência da visita: falta, sobra e classificação das diferenças. |

Um teste está marcado como pendente de propósito: o suporte ao CNPJ alfanumérico.

## Segurança e privacidade

O Next Gear manipula informações de clientes, operações financeiras e documentos. Por isso, a segurança é parte do desenvolvimento, não apenas da publicação do código.

- Não incluir senhas, tokens privados, contas de serviço, chaves de assinatura ou dados reais em commits.
- Manter regras de acesso do Firestore e Storage revisadas e testadas para cada perfil e organização.
- Utilizar dados fictícios e projetos Firebase isolados durante testes.
- Validar permissões no backend/regras do Firebase; controles somente na interface não são suficientes.
- Não considerar o sistema pronto para produção enquanto a revisão de autorização e os testes de segurança estiverem pendentes.

**Pendência conhecida:** as regras de autorização e o isolamento entre organizações estão em revisão. A configuração presente no repositório pode não refletir todas as regras atualmente implantadas no Firebase.

## Próximas melhorias

- [ ] Revisar e testar as regras do Firestore e do Storage.
- [x] Adicionar os primeiros testes unitários (formatadores, comissão e conferência).
- [ ] Ampliar os testes para widgets e regras de segurança.
- [ ] Documentar os fluxos de negócio mais importantes.
- [ ] Adicionar capturas reais das versões Web e Android.
- [x] Automatizar análises e testes com CI.
- [ ] Revisar tratamento de erros, permissões e organização dos módulos.
- [ ] Preparar configuração e assinatura próprias para uma futura distribuição Android.

## Demonstração

Capturas de tela e um vídeo demonstrativo serão adicionados após seleção das telas e remoção de quaisquer dados reais. Enquanto isso, este README descreve o escopo técnico presente no repositório, sem simular imagens ou resultados ainda não validados.

## Autor

**Ytalo Rodrigues** — [GitHub: @Yrodriguess](https://github.com/Yrodriguess)

## Licenciamento

O projeto não possui, neste momento, uma licença de código aberto publicada. Consulte o autor antes de reutilizar ou distribuir o código.
