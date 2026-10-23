s# NEXT GEAR — Setup no Android Studio

Passo a passo pra colocar o projeto rodando do zero. Faça na ordem.

## 1. Instalar o Flutter SDK

1. Baixe o Flutter em https://docs.flutter.dev/get-started/install/windows (ou macOS/Linux, conforme o seu sistema).
2. Extraia numa pasta sem espaço no caminho, ex: `C:\dev\flutter`.
3. Adicione `C:\dev\flutter\bin` na variável de ambiente `PATH`.
4. Abra um terminal novo e rode:
   ```
   flutter doctor
   ```
   Resolva qualquer item marcado com `[x]` (geralmente falta aceitar as licenças do Android SDK: `flutter doctor --android-licenses`).

## 2. Configurar o Android Studio

1. Abra o Android Studio → **Plugins** → instale **Flutter** (o plugin **Dart** vem junto automaticamente).
2. Reinicie o Android Studio.
3. Em **More Actions / Get from VCS** ou **New Flutter Project**, confirme que o SDK do Flutter aparece configurado (Settings → Languages & Frameworks → Flutter → aponte pro caminho onde você extraiu o SDK).

## 3. Criar o projeto

Se você ainda não criou o projeto:
```
flutter create --platforms=android,web next_gear
```
Isso já cria suportando Android e Web (sem precisar de Mac — iOS pode ser adicionado depois com `flutter create --platforms=ios .`, quando tiver Mac/CI disponível).

Depois, **substitua/adicione** os arquivos que já vieram prontos aqui (`pubspec.yaml`, `lib/main.dart`, `lib/core/theme/app_theme.dart` e as pastas em `lib/features/`) dentro do projeto que o `flutter create` gerou.

Abra a pasta no Android Studio: **File → Open** → selecione a pasta `next_gear`.

## 4. Conectar o Firebase

1. Crie o projeto no [console do Firebase](https://console.firebase.google.com) — comece pelo ambiente de desenvolvimento: `nextgear-dev` (ver seção 15.1 do Blueprint — dev/hml/prod separados desde o início).
2. Ative no console: **Authentication**, **Firestore Database**, **Storage**, **Functions** (exige plano Blaze), **App Check**.
3. Instale a CLI do Firebase e o FlutterFire:
   ```
   npm install -g firebase-tools
   firebase login
   dart pub global activate flutterfire_cli
   ```
4. Na pasta do projeto Flutter, rode:
   ```
   flutterfire configure --project=nextgear-dev
   ```
   Isso gera automaticamente o arquivo `lib/firebase_options.dart` e configura Android/Web. Depois, no `lib/main.dart`, descomente as duas linhas que referenciam `firebase_options.dart` e `DefaultFirebaseOptions.currentPlatform`.

## 5. Buscar as dependências e rodar

```
flutter pub get
flutter run -d chrome        # roda a versão Web
flutter run                  # roda no emulador/dispositivo Android conectado
```
Se a tela abrir mostrando **"NEXTGEAR"** com o gradiente verde-teal no centro, o setup está correto — Firebase inicializado, tema aplicado, projeto buildando nas duas plataformas.

## 6. Estrutura de pastas — organizada por módulo do Blueprint

```
lib/
  core/
    theme/          → AppColors e AppTheme (seção 17 do Blueprint)
    constants/       → constantes gerais (nomes de coleção, enums compartilhados)
  features/
    auth/            → login, permissões (seção 4)
    clientes/        → cadastro, aprovação, limite/exposição (seção 5)
    produtos/         → produto/SKU, tabela de preço (seção 6.3, 6.6)
    expositores/      → template + unidade física com QR Code (seção 7.1)
    estoque/           → stockMovements, inventoryBalances, carga do vendedor (seção 6)
    consignacoes/      → entidade `consignments`, ciclo fecha/reabre (seção 7.2, 7.3)
    visitas/           → máquina de estados da visita, conferência (seção 7.4-7.6)
    financeiro/        → ledger, contas a receber, aprovações (seção 8)
    relatorios/        → aging, giro, mapa de expositores, dashboards (seção 9)
```
Cada pasta de `features/` deve crescer com a própria subestrutura (`data/`, `domain/`, `presentation/` ou o padrão que a equipe preferir) conforme o módulo for sendo implementado — não precisa criar tudo isso agora, só ir preenchendo à medida que cada módulo é programado.

## 7. Por onde começar a programar

Sugestão de ordem, seguindo o roadmap do Blueprint (seção 14):
1. **`core/`** — já vem pronto (tema). Adicionar aqui as constantes de nome de coleção do Firestore antes de mais nada.
2. **`auth/`** — login + custom claims de perfil (admin/financeiro/vendedor/estoque).
3. **`clientes/`** — cadastro com as 3 dimensões de status (seção 5.1) + regra de exposição/limite (seção 5.3).
4. **`produtos/` e `expositores/`** — cadastro de SKU e do expositor físico com número `MODELO-SEQUENCIAL`.
5. **`consignacoes/` + `visitas/`** — o coração do sistema: ciclo de consignação que fecha e reabre (seção 7.2).

O schema completo do Firestore (campo a campo, por coleção) é o próximo documento útil pra ter em mãos antes de começar o módulo 3 — se quiser, é só pedir.
