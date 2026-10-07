# Pokédex Flutter

Uma Pokédex desenvolvida em **Flutter**, utilizando a **PokéAPI** como fonte de dados, com cache local em SQLite e interface inspirada em um scanner/terminal de dados.

O aplicativo permite explorar Pokémon, golpes, habilidades, tipos, estatísticas e cadeias de evolução, com carregamento progressivo e suporte a Pokémon shiny.

## ✨ Funcionalidades

* 📖 **Pokédex Nacional**

  * Lista de Pokémon com rolagem infinita
  * Número, nome e tipos
  * Arte oficial
  * Acesso à página de detalhes

* 🔍 **Detalhes dos Pokémon**

  * Arte oficial e versão shiny
  * Número da Pokédex
  * Geração
  * Tipo(s)
  * Altura e peso
  * Distribuição de gênero
  * Descrição
  * Estatísticas base
  * Fraquezas
  * Resistências
  * Imunidades
  * Golpes
  * Habilidades
  * Cadeia de evolução

* ⚔️ **Catálogo de golpes**

  * Nome
  * Tipo
  * Categoria
  * Poder
  * PP
  * Precisão
  * Descrição do efeito
  * Pokémon que podem aprender o golpe

* 🧬 **Catálogo de habilidades**

  * Nome
  * Geração
  * Descrição do efeito
  * Pokémon que possuem a habilidade

* 🏷️ **Tipos**

  * Lista de Pokémon pertencentes a um tipo
  * Navegação direta para os detalhes de cada Pokémon

* 💾 **Cache local**

  * Cache em memória
  * Cache persistente usando SQLite
  * Evita requisições repetidas
  * Requisições simultâneas para o mesmo recurso são agrupadas

A aplicação utiliza uma estratégia de cache em três níveis: **memória → SQLite → rede**. Caso o SQLite não esteja disponível, o aplicativo continua utilizando o cache em memória.

## 🛠️ Tecnologias

* [Flutter](https://flutter.dev/)
* [Dart](https://dart.dev/)
* [PokéAPI](https://pokeapi.co/)
* `http` — requisições HTTP
* `sqflite` — banco SQLite local
* `path` — manipulação do caminho do banco
* `google_fonts` — tipografia

Dependências utilizadas no projeto:

```yaml
dependencies:
  http: ^1.2.0
  sqflite: ^2.3.0
  path: ^1.9.0
  google_fonts: ^6.2.0
```

## 🚀 Como executar

### Pré-requisitos

Tenha instalado:

* Flutter SDK
* Dart SDK
* Android Studio / Android SDK, caso queira executar no Android

Confira sua instalação com:

```bash
flutter doctor
```

### Instalação

Clone o projeto:

```bash
git clone <URL_DO_REPOSITORIO>
cd <PASTA_DO_PROJETO>
```

Instale as dependências:

```bash
flutter pub get
```

Execute:

```bash
flutter run
```

## 🤖 Android

O aplicativo realiza requisições para a PokéAPI. No Android, é necessário permitir acesso à internet.

No `AndroidManifest.xml` principal:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

Essa permissão é necessária principalmente para builds de release.

## 🌐 Fonte dos dados

Os dados são obtidos através da **PokéAPI**:

```text
https://pokeapi.co/api/v2
```

As imagens dos Pokémon utilizam os sprites oficiais disponibilizados pelo repositório de sprites da PokéAPI.

## 💾 Sistema de cache

O aplicativo possui uma camada própria para acesso à API.

A ordem de consulta é:

```text
┌─────────────┐
│ Memória     │
└──────┬──────┘
       │ não encontrado
       ▼
┌─────────────┐
│ SQLite      │
└──────┬──────┘
       │ não encontrado
       ▼
┌─────────────┐
│ PokéAPI     │
└─────────────┘
```

O SQLite armazena as respostas da API em uma tabela simples:

```sql
CREATE TABLE cache (
  url TEXT PRIMARY KEY,
  body TEXT NOT NULL
);
```

Além disso, existe um controle de requisições em andamento para evitar múltiplas requisições simultâneas para a mesma URL.

## 📜 Estrutura geral

A aplicação está concentrada no `main.dart`, que contém a interface, lógica de acesso à API, cache e componentes da Pokédex.

Principais partes:

```text
main.dart
│
├── Helpers
│   ├── Formatação de nomes
│   ├── IDs
│   └── URLs de imagens
│
├── Api
│   ├── HTTP
│   ├── Cache em memória
│   └── Cache SQLite
│
├── TypeIndex
│   └── Índice de tipos
│
├── Widgets
│   ├── SpriteFrame
│   ├── PokeImage
│   ├── Pill
│   ├── InfoBox
│   └── HeroPanel
│
├── Listas
│   ├── Pokémon
│   ├── Golpes
│   └── Habilidades
│
├── Detalhes
│   ├── Pokémon
│   ├── Golpes
│   └── Habilidades
│
├── EvolutionTree
│   └── Cadeia de evolução
│
└── TypePage
    └── Pokémon por tipo
```

A lista principal utiliza paginação `limit/offset` e carrega novos resultados conforme o usuário se aproxima do final da página.

## 🎨 Interface

A interface utiliza uma estética inspirada em:

* scanners de dados;
* terminais de laboratório;
* Pokédex clássica;
* cartões com bordas e sombras;
* paleta predominantemente vermelha, creme e verde-azulada.

A fonte **DM Mono** é utilizada em elementos de identificação e dados técnicos, enquanto **Manrope** é utilizada como fonte geral da aplicação.

## 📱 Navegação

A tela inicial possui três seções principais:

```text
Pokédex
├── Pokémon
├── Golpes
└── Habilidades
```

A partir dos detalhes de um Pokémon também é possível navegar para:

```text
Pokémon
├── Tipo
├── Golpe
├── Habilidade
└── Evolução
```

## ⚠️ Observações

* O aplicativo depende da disponibilidade da PokéAPI para obter dados que ainda não estejam armazenados no cache.
* A lista principal não possui busca.
* O carregamento da Pokédex é feito progressivamente através de rolagem infinita.
* Formas alternativas com IDs acima de `10000` são ignoradas nas listagens principais.
* O cache SQLite é utilizado quando está disponível; em plataformas onde ele não funciona, o aplicativo utiliza apenas o cache em memória.

## 📄 Licença

Este projeto foi desenvolvido para fins educacionais.

Os dados e imagens utilizados pertencem aos respectivos detentores de seus direitos. A aplicação utiliza a PokéAPI como fonte de dados.
