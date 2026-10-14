# Pokédex (Flutter)

App de Pokédex em Flutter que consome a [PokéAPI v2](https://pokeapi.co/docs/v2). O visual segue o exemplo React (`App.tsx` / `index.css`): tema vermelho/creme, sombras duras, molduras quadriculadas "de scanner".

- **Sem busca.** A navegação é por rolagem e por toques.
- **Rolagem infinita** nas três listas (Pokémon, golpes e habilidades).
- **Textos da API em inglês** (descrições, efeitos, categorias). Os rótulos da interface estão em português.
- **Tudo em um único arquivo:** `lib/main.dart`.

> O código não foi compilado nem executado por quem o escreveu (não havia Dart no ambiente). Rode `flutter analyze` e teste no emulador antes de depender dele.

---

## 1. Como rodar

```bash
flutter pub get
flutter run
```

**Dependências** (`pubspec.yaml`):

| Pacote | Para que serve |
|---|---|
| `http` | Requisições à PokéAPI |
| `sqflite` | Cache em disco (SQLite) |
| `path` | Montar o caminho do banco |
| `google_fonts` | Manrope (textos) e DM Mono (números de registro), baixadas na primeira execução |

**Plataformas e permissões**

- **Android:** garanta `<uses-permission android:name="android.permission.INTERNET"/>` no `AndroidManifest.xml` principal (necessário em builds release).
- **SQLite:** `sqflite` funciona em Android, iOS e macOS. Em web, Windows e Linux o banco não abre; o app detecta isso e segue **só com cache em memória** (nada quebra, só perde o cache entre sessões).
- **Internet na primeira execução:** as fontes do `google_fonts` e os dados da API precisam de rede.

---

## 2. Visão geral das telas

```
HomeShell (3 abas)
├── POKÉMON      → PokemonListPage ──toque no card──► PokemonDetailPage
├── GOLPES       → CatalogPage('move') ──toque──────► ResourceDetailPage('move')
└── HABILIDADES  → CatalogPage('ability') ──toque───► ResourceDetailPage('ability')

PokemonDetailPage
├── toque num tipo ───────────► TypePage (Pokémon daquele tipo)
├── toque numa evolução ──────► PokemonDetailPage (troca a tela atual)
├── aba Golpes → toque ───────► ResourceDetailPage('move')
└── aba Habilidades → toque ──► ResourceDetailPage('ability')

ResourceDetailPage / TypePage
└── toque num Pokémon ────────► PokemonDetailPage
```

| Tela | Classe | O que mostra |
|---|---|---|
| Lista de Pokémon | `PokemonListPage` | Painel de título + grade de cards (id, arte, nome, tipos) |
| Catálogo de golpes | `CatalogPage(kind: 'move')` | Cards com tipo, categoria e poder |
| Catálogo de habilidades | `CatalogPage(kind: 'ability')` | Cards com a geração |
| Detalhe do Pokémon | `PokemonDetailPage` | Arte (com shiny), descrição, medidas, stats, evolução, extras |
| Detalhe de golpe/habilidade | `ResourceDetailPage` | Ficha, efeito em batalha e Pokémon relacionados |
| Pokémon de um tipo | `TypePage` | Grade com todos os Pokémon daquele tipo |

---

## 3. Dados da API por tela

Base: `https://pokeapi.co/api/v2`. Todos os recursos passam pelo cache (seção 4).

| Tela | Chamadas | Campos usados |
|---|---|---|
| **Lista de Pokémon** | `GET /pokemon?limit=20&offset=N` + índice de tipos (`/type/1` … `/type/18`, uma vez) | `results[].name`, `results[].url` (o id é o último número da URL), `pokemon[].slot` dos tipos |
| **Catálogo de golpes** | `GET /move?limit=30&offset=N`, depois `GET /move/{id}` de cada item | `type`, `damage_class`, `power` |
| **Catálogo de habilidades** | `GET /ability?limit=30&offset=N`, depois `GET /ability/{id}` de cada item | `generation` |
| **Detalhe do Pokémon** | `GET /pokemon/{id}` → em paralelo `species.url` e `GET /type/{nome}` de cada tipo → `evolution_chain.url` | `types`, `stats`, `height`, `weight`; `genera`, `flavor_text_entries`, `gender_rate`, `generation`; `damage_relations`; `chain` |
| Aba **Golpes** (sob demanda) | `GET /move/{nome}` dos 20 primeiros golpes do Pokémon | `power`, `pp`, `accuracy`, `type` |
| Aba **Habilidades** (sob demanda) | `GET /ability/{nome}` de cada habilidade | `effect_entries[].short_effect` |
| **Detalhe de golpe/habilidade** | `GET /move/{nome}` ou `GET /ability/{nome}` | `effect_entries`, `flavor_text_entries`, `learned_by_pokemon` / `pokemon` |
| **Página de tipo** | `GET /type/{nome}` | `pokemon[].pokemon` |

**Imagens** (repositório `PokeAPI/sprites`, sem chamar a API):

- Arte oficial: `.../sprites/pokemon/other/official-artwork/{id}.png` (e `.../official-artwork/shiny/{id}.png`)
- Sprite pequeno (fallback): `.../sprites/pokemon/{id}.png`

---

## 4. Cache e rede (`class Api`)

Toda chamada passa por `Api.get(path)`, que aceita um caminho relativo (`"pokemon/25"`) ou uma URL completa.

Ordem de consulta:

1. **Memória** (mapa com limite de 200 entradas; ao passar disso descarta a mais antiga).
2. **SQLite** (tabela `cache(url TEXT PRIMARY KEY, body TEXT)` em `pokedex.db`).
3. **Rede** (`http`). A resposta é gravada na memória e no SQLite.

Detalhes:

- **Deduplicação:** se duas telas pedem a mesma URL ao mesmo tempo, só uma requisição sai (`_inflight`).
- **Sem expiração:** os dados da PokéAPI mudam raramente; o cache só cresce. Para limpar, desinstale o app ou apague `pokedex.db`.
- **Política de uso justo da PokéAPI:** pede cache local; este desenho atende isso.
- Respostas diferentes de 200 viram `Exception`, tratadas por cada tela (com botão de tentar de novo).

### Índice de tipos (`class TypeIndex`)

Os cards da lista precisam dos tipos de cada Pokémon. Baixar o JSON completo de cada um custaria muito (ele inclui todos os golpes). Em vez disso:

- No primeiro uso, busca `/type/1` a `/type/18` (cada um lista seus Pokémon com o `slot`).
- Monta `id → [tipo1, tipo2]`, ordenado pelo `slot`.
- A lista de Pokémon espera esse índice ficar pronto antes de mostrar a primeira página; depois cada página custa **uma** requisição.

---

## 5. Rolagem infinita (`class PagedGrid`)

Widget genérico usado pelas três listas. Parâmetros:

| Parâmetro | Função |
|---|---|
| `endpoint` | `pokemon`, `move` ou `ability` |
| `limit` | Itens por página (20 para Pokémon, 30 para os catálogos) |
| `header` | Widget que rola junto com a lista (painel de título) |
| `gridDelegate` | Layout da grade |
| `loadItem` | Transforma o item bruto (`{name, url}`) nos dados do card |
| `itemBuilder` | Constrói o card |

Comportamento:

- Carrega a próxima página quando faltam **400 px** para o fim.
- **Preenche a tela:** se a primeira página não gera rolagem (tablet/desktop), carrega a seguinte automaticamente.
- **Fim da lista:** termina quando `next == null` ou quando aparecem itens com id **≥ 10000** (formas alternativas, que não são Pokémon novos). Mostra "TODOS OS RESULTADOS FORAM CARREGADOS".
- **Erro:** o rodapé mostra "Não foi possível carregar mais itens" e o botão **TENTAR DE NOVO**. Enquanto há erro, a rolagem não dispara novas tentativas sozinha.
- **Mantém o estado** ao trocar de aba (`AutomaticKeepAliveClientMixin`).

---

## 6. Detalhe do Pokémon

Ordem de carregamento (`_load`):

1. `GET /pokemon/{id}`
2. Em paralelo: espécie (pela URL `species.url`, **não** pelo id, porque formas têm id diferente da espécie) e os tipos do Pokémon.
3. Cadeia de evolução (`evolution_chain.url`).

Seções da tela:

| Seção | Como é calculada |
|---|---|
| Arte oficial | `PokeImage` com alternância normal/shiny; selo `GEN X` vem de `generation.name` |
| Categoria e descrição | `genera` e `flavor_text_entries` em inglês; para a descrição usa a **última** entrada (jogo mais recente), sem quebras de linha |
| Altura / peso | `height ÷ 10` (m) e `weight ÷ 10` (kg) |
| Gênero | `gender_rate` é a chance de fêmea em **oitavos** (0–8); `-1` = sem gênero. Fêmea = taxa × 12,5%; macho = o restante |
| Stats | Barra proporcional a `base_stat ÷ 150` (limitada a 100%) |
| Evolução | `EvolutionTree` (seção 7) |
| Extras | Três abas: Fraquezas, Golpes, Habilidades |

### Fraquezas

Para cada tipo do Pokémon, lê `damage_relations`:

- `double_damage_from` multiplica por 2, `half_damage_from` por 0,5 e `no_damage_from` zera.
- Com dois tipos os fatores se **multiplicam** (ex.: ×4, ×¼).
- Resultado em três grupos: **Fraquezas · 2×**, **Resistências · ½×**, **Imunidades · 0×**. Tipos neutros (×1) não aparecem.

### Golpes e habilidades (sob demanda)

- A aba **Golpes** busca os detalhes dos **20 primeiros** golpes (ordem da API) só na primeira vez que é aberta e mostra uma tabela: nome, tipo, poder, PP, precisão.
- A aba **Habilidades** busca cada habilidade na primeira abertura e mostra o efeito curto (`short_effect`), com selo **OCULTA** quando aplicável.

---

## 7. Árvore de evolução (`EvolutionTree`)

Renderiza a cadeia de forma recursiva, em vez de uma lista simples:

- Cada nó é um card (`_EvoCard`) com moldura quadriculada de tamanho fixo e a arte oficial. O id da imagem vem da **URL da espécie** na própria cadeia, então imagem e nome sempre coincidem.
- Os filhos ficam lado a lado (`Wrap`), cada um precedido de uma seta `↓` com a condição. Cadeias lineares viram uma coluna; ramificadas (ex.: Eevee) abrem em várias colunas.
- O Pokémon da tela atual aparece destacado em rosa.
- Tocar em outro Pokémon da cadeia **substitui** a tela atual (`pushReplacement`), para a pilha de navegação não crescer.

### Condições (`evoCondition`)

Resume `evolution_details` em texto curto, juntando as partes com " · ":

| Campo da API | Texto |
|---|---|
| `min_level` | Nível N |
| `item` | Nome do item |
| `held_item` | Segurando X |
| `min_happiness` / `min_affection` | Felicidade ≥ N / Afeto ≥ N |
| `known_move` / `known_move_type` | Golpe X / Golpe tipo X |
| `location` | Em X |
| `time_of_day` | Dia, Noite, Entardecer ou Lua cheia |
| `trigger == trade` | Troca |

Se houver mais de uma alternativa, mostra até duas, separadas por " / ". Se nenhuma regra conhecida se aplicar, mostra o nome do gatilho (`trigger`).

---

## 8. Widgets e helpers reutilizáveis

| Nome | Descrição |
|---|---|
| `SpriteFrame` | Moldura quadriculada (fundo "scanner") para qualquer imagem; opcionalmente com borda |
| `PokeImage` | Arte oficial com indicador de carregamento; se falhar, tenta o sprite pequeno; se falhar de novo, mostra um ícone |
| `Pill` | Etiqueta de tipo/estado (tamanho pequeno ou grande, tocável) |
| `InfoBox` | Caixa "rótulo + valor" (altura, peso, tipo, poder...) |
| `SectionTitle` | Título de seção em caixa alta com espaçamento |
| `HeroPanel` | Painel de abertura de cada lista |
| `PokemonCard` | Card da lista de Pokémon |
| `ResourceCard` | Card da lista de golpes/habilidades |
| `MiniPokemon` | Card compacto (arte + nome) usado em páginas de tipo, golpe e habilidade |
| `openPokemon(ctx, id)` / `openResource(ctx, kind, nome)` | Atalhos de navegação |

Funções auxiliares: `pad3` (001), `cap`, `humanize` (`mr-mime` → `Mr Mime`), `idFromUrl`, `artworkUrl`, `spriteUrl`, `fmtNum` (vírgula decimal), `effectText` (efeito em inglês, sem marcações da API e com `$effect_chance` substituído) e `latestFlavor` (descrição mais recente em inglês).

---

## 9. Design

Cores definidas no topo do arquivo:

| Constante | Uso |
|---|---|
| `kRed` `#B5162D` | App bar, destaques, barras de stats |
| `kDarkRed` `#8F1025` | Textos de destaque, sombras do detalhe |
| `kShadowRed` `#7D1022` | Sombra dura dos cards |
| `kBg` `#F6E9E7` | Fundo das telas |
| `kCream` `#FFF8EF` | Fundo de cards e painéis |
| `kDark` `#2B1014` | Bordas e textos principais |
| `kBorder` `#CDA9A4` | Bordas leves |
| `kPink` `#F8D9D5` | Etiquetas de tipo, evolução atual |
| `kTeal` `#DCEDEA` | Moldura quadriculada das imagens |
| `kYellow` `#E4C93D` | Shiny e selo "Oculta" |

Tipografia: **Manrope** (tema geral) e **DM Mono** (números de registro como `#025`). Os cantos são retos e as sombras são "duras" (sem desfoque), como no exemplo web.

---

## 10. Decisões e correções em relação à versão anterior

- **Card travando:** havia um `Expanded` dentro de uma coluna sem altura definida, o que gera erro de layout. Corrigido.
- **Lista leve:** em vez de baixar 20 JSONs completos por página, os tipos vêm do índice de tipos (seção 4).
- **Detalhe de formas:** a espécie é buscada pela URL do Pokémon, evitando 404 em ids acima de 10000.
- **Formas alternativas fora da lista:** a paginação para antes dos ids ≥ 10000.
- **Evolução com imagens corretas:** id da espécie na cadeia, moldura uniforme, fallback de imagem e árvore com ramificações.
- **Requisições duplicadas:** unificadas (`_inflight`).
- **Telas de golpe e habilidade:** viraram uma só (`ResourceDetailPage`).
- **Listas relacionadas leves:** usam só nome e id que já vêm na resposta (até 60 itens), sem baixar o detalhe de cada Pokémon.

---

## 11. Limitações conhecidas e ideias

- Os cards da lista **não mostram a categoria** ("Mouse Pokémon"): exigiria uma chamada de espécie por card.
- A aba Golpes mostra só os **20 primeiros** golpes do Pokémon, em ordem alfabética (ordem da API), sem filtrar por nível, TM ou jogo.
- Sem filtro por geração ou tipo na lista (o toque em um tipo abre a `TypePage`).
- Sem favoritos, sem modo offline explícito (o cache ajuda, mas telas nunca visitadas precisam de rede).
- O cache em disco não expira.
- O app mostra os textos da API em inglês; para português, bastaria filtrar `language.name == "pt-br"` com fallback para `en` (o `language/13` da PokéAPI).

Ideias naturais de próximos passos: favoritos salvos em SQLite, filtro de geração, ordenar golpes por nível de aprendizado e testes de widget para `PagedGrid` e `EvolutionTree`.

---

## 12. Mapa do arquivo

`lib/main.dart`, de cima para baixo:

1. Cores e helpers
2. `Api` (cache) e `TypeIndex`
3. Widgets básicos (`SpriteFrame`, `PokeImage`, `Pill`, `InfoBox`, `SectionTitle`, `HeroPanel`)
4. `PagedGrid`
5. `main()`, `PokedexApp`, `HomeShell`
6. `PokemonListPage`, `PokemonCard`
7. `CatalogPage`, `ResourceCard`
8. `PokemonDetailPage` (carga, fraquezas, abas de extras)
9. `EvolutionTree` e condições
10. `MiniPokemon`, `ResourceDetailPage`, `TypePage`
