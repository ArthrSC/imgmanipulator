# ImgManipulator

Aplicação interativa de Processamento de Imagens em **Flutter** (Windows, Linux, macOS, Android, iOS e Web).
Integra transformações **pontuais**, **geométricas** e **por vizinhança**, com pipelines encadeados.
Todas as operações são implementadas **manualmente** sobre matrizes de pixels; o pacote `image` é usado
apenas para decodificar/codificar JPG/PNG.

## Como executar

```bash
# 1) dentro da pasta do projeto, gere as pastas de plataforma (uma vez)
flutter create . --project-name imgmanipulator --org br.edu.imgmanipulator
flutter pub get

# 2) rode (escolha o alvo)
flutter run -d windows      # ou linux / macos / chrome / <id do celular>

# 3) testes unitários das operações
flutter test

Requisitos: Flutter 3.19+ (Dart 3.3+).
Linux: sudo apt install zenity (necessário ao file_picker).
macOS: habilite em macos/Runner/*.entitlements a chave com.apple.security.files.user-selected.read-write.
Fluxo da aplicação

    Carregar imagem JPG/PNG (botão de pasta, ou "Abrir por caminho" no desktop/mobile).

    imagemOriginal nunca é alterada; imagemAtual guarda o último resultado.

    Ao escolher uma operação (a partir da segunda), o app pergunta:
    1 - Imagem original / 2 - Última imagem processada.

    Parâmetros são pedidos em um diálogo (validados ali mesmo), a operação roda em isolate,
    o resultado é exibido, a operação é registrada (parâmetros, origem, tempo, tamanho) e o menu volta.

    "Pipeline: Original → … → …" aparece sob a imagem; "Registro de operações" mostra o log completo.

Operações (menu)
Classe	Operações
Pontuais	Escala de cinza, Brilho, Contraste, Negativo, Histograma, Alongamento de contraste, Equalização
Geométricas	Rotação, Translação, Espelhamento (H/V), Redimensionamento
Vizinhança	Filtro da média (3/5/7…), Filtro Gaussiano (kernel + σ), Adicionar ruído gaussiano
Controle	Mostrar original, Mostrar atual, Salvar (PNG), Registro, Encerrar (limpa a sessão)
Decisões e fórmulas

    Cinza: I = 0,299R + 0,587G + 0,114B.

    Brilho: g = f + Δ (saturado em 0–255). Contraste: g = fator·(f − 128) + 128 (saturado).

    Negativo: g = 255 − f.

    Alongamento: g = (f − fmin)/(fmax − fmin)·255, com fmin/fmax globais dos canais RGB (preserva cor).

    Equalização: CDF da luminância Y; a diferença Y' − Y é somada aos canais RGB (mantém Cb/Cr, evita
    distorcer cores). Em cinza equivale à equalização direta.

    Rotação: mapeamento inverso + interpolação bilinear; ângulo positivo = anti-horário; a tela cresce para
    W' = |W cosθ| + |H senθ|, H' = |W senθ| + |H cosθ|; áreas novas em preto.

    Translação: x' = x + dx, y' = y + dy (dy > 0 desce), tela do mesmo tamanho, áreas novas em preto.

    Kernels: média = pesos 1/k²; Gaussiano exp(−(i²+j²)/2σ²) normalizado. Kernel deve ser ímpar, 3 ≤ k ≤ 31; σ > 0.

    Tratamento de bordas: REFLEXÃO (reflect-101) — índice i < 0 → −i, i ≥ n → 2(n−1) − i.
    Não escurece as bordas (como zeros) nem cria faixas constantes (como replicação).

    Convolução: implementação 2D genérica (convolve2D, kernel espelhado) e separável (convolveSeparable);
    o diálogo tem a chave "Convolução separável" para comparar tempos. Os resultados são equivalentes (há teste).

    Ruído: gaussiano aditivo N(0, σ²) por canal (Box–Muller), saturado em 0–255.

    Imagens com lado > 2000 px são reduzidas ao carregar (kMaxLoadSide em lib/core/processing.dart; use 0 para desativar).

Tratamento de erros

Arquivo inexistente/ilegível, formato inválido (extensão e assinatura do arquivo), opção/valor não numérico,
brilho fora de ±255, contraste fora de 0–10, kernel par/menor que 3/maior que 31, σ ≤ 0, dimensões inválidas,
operar ou salvar sem imagem carregada — todos geram mensagem clara, sem travar o app.
Sequências de teste da avaliação

    Pontuais: Original → Escala de cinza → Contraste (1.5) → Equalização → (Histograma antes/depois).

    Geométricas: Original → Redimensionamento (400×300) → Rotação (45) → Espelhamento.

    Vizinhança: Original → Ruído (σ=25) → Filtro da média 5×5 ou Gaussiano 5×5 σ=1.5.

Use a mesma imagem em todos os testes e inclua-a na entrega (ex.: imagem_teste.jpg).
Análise de desempenho (preencher com suas medições)

Cada operação registra o tempo (ms) no "Registro de operações" (mede só o algoritmo, sem codificar PNG).
Complexidade esperada para imagem W×H e kernel k×k:
Operação	Custo	Observação
Pontuais (LUT)	O(W·H)	Tabela de 256 entradas; as mais rápidas
Equalização / Alongamento	O(W·H)	Duas passadas (histograma + aplicação)
Rotação / Redimensionamento	O(W·H)	Bilinear = 4 leituras por canal
Espelhamento / Translação	O(W·H)	Só cópia de pixels
Convolução 2D	O(W·H·k²)	7×7 ≈ 5,4× mais lento que 3×3
Convolução separável	O(W·H·k)	Ganho ≈ k/2 sobre a 2D

Sugestão de tabela para o relatório (imagem de teste, ex. 1280×720, anote sua máquina):
Operação	Parâmetros	Tempo (ms)
Média 2D	3×3 / 5×5 / 7×7	
Média separável	3×3 / 5×5 / 7×7	
Gaussiano 2D vs separável	5×5, σ=1,5	
Rotação	45°	
Equalização	—	

Análise qualitativa esperada: kernels maiores e σ maiores borram mais; o filtro da média remove ruído mas
apaga detalhes/bordas, enquanto o Gaussiano preserva melhor a estrutura; a equalização em imagem colorida,
feita na luminância, realça contraste sem deslocar tonalidades.
Estrutura do código
text

lib/
  main.dart                     # ponto de entrada
  core/
    img_data.dart               # matriz RGBA, ImgException, clamp255, luma
    processing.dart             # despacho das operações (isolate), decodificação/PNG
    app_controller.dart         # imagem_original, imagem_atual, log, pipeline
  ops/
    point_ops.dart              # transformações pontuais
    geometric_ops.dart          # rotação, translação, espelhamento, resize
    neighborhood_ops.dart       # kernels, convolução, média, gaussiano, ruído
    histogram.dart              # cálculo do histograma
  ui/
    op_specs.dart               # definição/validação de parâmetros de cada operação
    dialogs.dart                # diálogos (origem, parâmetros, histograma, log)
    home_page.dart              # menu e controle de fluxo
test/                           # testes unitários das operações

text


### 📌 Resumo em 3 passos

1. **Selecione tudo** no `README.md` no Zed (`Ctrl+A`).
2. **Apague** e **cole o conteúdo acima**.
3. **Salve** (`Ctrl+S`) e rode no terminal:
   ```bash
   git add README.md
   git commit -m "Resolve conflito no README"
   git push -u origin main

    ⚠️ Regra de ouro: o arquivo final não pode conter nenhuma dessas linhas:

        <<<<<<< HEAD

        =======

        >>>>>>> origin/main

    Se você colar o conteúdo acima (que já está limpo), não vai ter nenhuma delas. ✅
