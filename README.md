# OpenNotch

<img src="Resources/AppIcon.png" width="128" alt="Ícone do OpenNotch">

Um app gratuito que transforma o topo da tela em um painel útil: música, agentes de IA, apps abertos, captura de tela, anotações e mais. Sem anúncios e sem recursos bloqueados.

Existe para **macOS** (sobre o notch do MacBook) e para **Windows** (uma barra no centro do topo da tela).

<img src="docs/screenshots/home.png" width="820" alt="OpenNotch aberto na tela inicial, com o player de música e atalhos de apps">

Passe o mouse sobre o notch (ou clique nele) para abrir o painel. Com ele fechado, pequenos indicadores aparecem ao lado do notch: a capa da música, o tempo do timer, quantos agentes de IA estão trabalhando, o cronômetro de uma gravação, o volume e o brilho.

<img src="docs/screenshots/fechado.png" width="720" alt="Notch fechado com a capa da música à esquerda e o contador de agentes de IA à direita">

Somente macOS 14 ou mais recente. Em telas sem notch (Macs antigos e monitores externos), o painel fica no centro da barra de menus.

Disponível em português e inglês.

## Baixar

Os dois apps ficam na [versão mais recente](https://github.com/Nicollasarcanjo/OpenNotch/releases/latest):

| Sistema | Arquivo |
|---|---|
| macOS 14 ou mais recente (Apple Silicon e Intel) | `OpenNotch-macOS.zip` |
| Windows 10 ou 11 (64 bits) | `OpenNotch-Windows.zip` |

**macOS:** descompacte e arraste o app para a pasta Aplicativos. Como ele ainda não é notarizado pela Apple, o macOS bloqueia a primeira abertura. Para liberar, abra **Ajustes do Sistema › Privacidade e Segurança**, role até o aviso sobre o OpenNotch e clique em **Abrir Mesmo Assim**. Pelo Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/OpenNotch.app
```

**Windows:** extraia o `OpenNotch.exe` para uma pasta sua e dê dois cliques; não precisa instalar nada. Como ele ainda não tem assinatura digital, o Windows mostra "O Windows protegeu o computador" na primeira vez: clique em **Mais informações** e em **Executar assim mesmo**.

## macOS e Windows

As funcionalidades e as imagens abaixo descrevem a versão macOS, que é a mais completa. A versão Windows é a primeira, tem a mesma estrutura e a maior parte dos módulos:

| Recurso | macOS | Windows |
|---|---|---|
| Música (mostrar e controlar) | Sim | Sim, incluindo navegadores, sem extensão |
| Agentes de IA (Claude Code e Codex) | Sim | Sim |
| Apps abertos com CPU, GPU e memória | Sim | Sim |
| Print de tela toda e de área | Sim | Sim |
| Gravação de tela e anotação de prints | Sim | Ainda não |
| Anotações, textos copiados e busca | Sim | Sim |
| Volume por app | Sim | Sim |
| Volume por aba do navegador | Sim, com a extensão | Ainda não |
| Bandeja de arquivos | Sim | Sim |
| Downloads | Sim | Sim, sem porcentagem |
| Timers e monitor do sistema | Sim | Sim |
| Tela inicial personalizável e calendário | Sim | Ainda não |
| Vários monitores, atalhos, idiomas, exportar configurações | Sim | Sim |

No Windows não existe notch físico, então o painel fica **minimizado** quando fechado: só um risco discreto no centro do topo da tela, que abre ao passar o mouse. Quem preferir ver a capa da música, o timer e os agentes sem abrir pode ligar "Mostrar indicadores com o notch fechado" nas configurações.

A versão Windows é desenvolvida a partir de um Mac: quem escreve o código só consegue compilá-la, e os ajustes são feitos com base no retorno de quem a usa. Se algo não funcionar ou ficar feio, abra uma issue.

## Funcionalidades

### Tela inicial personalizável

A primeira aba é uma fileira de blocos que você escolhe e ordena em Configurações › Tela inicial:

| Bloco | O que mostra |
|---|---|
| Música | Faixa, artista, capa e controles |
| Calendário | Data e próximos eventos de hoje |
| Atalhos de apps | Ícones dos apps que você adicionou; arraste um app do Finder até o notch para criar o atalho |
| GIF | Um GIF animado, com cantos arredondados |
| Sequência de imagens | Imagens que trocam sozinhas, no intervalo que você definir |
| Relógio | Hora e data |
| Sistema (resumo) | Anéis de CPU, RAM e bateria |
| Timer (resumo) | Tempo atual e botão de iniciar/pausar |

### Música

<img src="docs/screenshots/home.png" width="720" alt="Tela inicial com o player de música e atalhos de apps">

- Spotify e Apple Music: título, artista, álbum, capa e botões de voltar, tocar/pausar e avançar.
- Música do navegador (YouTube, YouTube Music, Spotify Web, SoundCloud, Deezer, Tidal, Amazon Music, Apple Music web) por meio de uma extensão para Brave, Chrome e Edge. O passo a passo e o download ficam em Configurações › Extensão do navegador.
- Com o notch fechado, a capa e barrinhas animadas aparecem ao lado dele.

### Agentes de IA

<img src="docs/screenshots/agents.png" width="720" alt="Aba de agentes de IA com sessões do Claude Code e do Codex">

Mostra as sessões de ferramentas de IA abertas no Mac, com o projeto de cada uma e o estado (trabalhando ou ocioso). Quando uma tarefa termina, o notch abre por alguns segundos avisando, com som opcional.

| Ferramenta | O que mostra |
|---|---|
| Claude Code | Sessões abertas, projeto e uso da janela de contexto |
| Codex | Sessões recentes, projeto, uso de contexto e uso do limite do plano (5 h e semanal) |
| Antigravity | Se há um agente trabalhando (detecção aproximada) |
| Outras | Você cadastra pelo nome do processo; mostra a pasta em que roda e o uso de CPU |

Tudo é lido dos arquivos que essas ferramentas já gravam em disco. O OpenNotch não acessa contas, senhas nem a internet para isso.

### Apps abertos

<img src="docs/screenshots/apps.png" width="720" alt="Gerenciador de apps com CPU, GPU e memória de cada app">

Um gerenciador de tarefas no notch:

- Lista os apps abertos com CPU, GPU e memória, em porcentagem.
- Agrupa todos os processos de um app (auxiliares, abas, outras instâncias) dentro do app principal; clique para expandir.
- Fecha o app inteiro com um clique; "Forçar encerramento" fica no clique com dois dedos.
- Na lista expandida dá para encerrar um processo só.

### Volume por app e por aba

<img src="docs/screenshots/mixer.png" width="720" alt="Aba de volume com um controle para cada app e cada aba do navegador">

Um controle de volume para cada app que está tocando som, sem mexer no volume geral do sistema:

- Aparecem os apps com áudio no momento (e os que estão com o volume alterado).
- Arraste o controle para baixar ou aumentar só aquele app; o alto-falante silencia e devolve o som.
- Abas do navegador aparecem separadas, cada uma com o seu volume (precisa da extensão do OpenNotch).
- Com o volume em 100%, o OpenNotch não toca no áudio do app. Abaixo disso, ele passa a reproduzir o som do app com o volume escolhido; por isso o macOS pede a permissão de gravação de áudio do sistema. Nada é gravado.

Requer macOS 14.2 ou mais recente.

### Captura de tela

<img src="docs/screenshots/capture.png" width="720" alt="Aba de captura com os botões de print e gravação e a galeria das últimas capturas">

- Print da tela toda ou de uma área.
- Gravação da tela toda ou de uma área.
- Os prints e gravações feitos pelos atalhos do macOS (⇧⌘3, ⇧⌘4, ⇧⌘5) também aparecem aqui.
- Galeria com as últimas capturas: um clique copia, clique com dois dedos abre no app padrão.
- Anotar um print: seta, retângulo, texto e borrar. O resultado é salvo como cópia e já vai copiado.
- Por padrão o OpenNotch não aparece em prints nem gravações, mesmo aberto. Para printar ou gravar o próprio painel, ligue "Mostrar o OpenNotch em prints e gravações" em Configurações › Captura de tela.

### Textos

<img src="docs/screenshots/texts.png" width="720" alt="Aba Textos com anotações à esquerda e textos copiados à direita">

- Anotações: crie quantas quiser; são salvas automaticamente.
- Histórico de textos copiados: clique para copiar de novo, ou salve um item como anotação. Senhas copiadas de gerenciadores ficam de fora.
- Busca única nas anotações e nos textos copiados.

### Arquivos

<img src="docs/screenshots/tray.png" width="720" alt="Aba Arquivos com a bandeja e o progresso dos downloads">

- Bandeja: solte arquivos no notch para guardá-los e arraste para outro lugar depois.
- Downloads: progresso dos arquivos baixando na pasta Downloads (Safari, Chrome, Brave e outros apps que informam o progresso ao sistema). Com o notch fechado, a porcentagem aparece ao lado dele.

### Timers

<img src="docs/screenshots/timers.png" width="720" alt="Aba Timers no modo Pomodoro">

Pomodoro (foco e pausa), contagem regressiva e cronômetro. Com o notch fechado, o tempo aparece ao lado dele.

### Sistema

<img src="docs/screenshots/system.png" width="720" alt="Aba Sistema com CPU, memória, disco, bateria e rede">

CPU, memória, disco, bateria e velocidade da rede.

### Volume e brilho

Ao mudar o volume ou o brilho, um indicador aparece ao lado do notch.

### Atalhos de teclado

| Atalho | Ação |
|---|---|
| ⌃⌥N | Abrir ou fechar o notch |
| ⌃⌥V | Abrir Textos |
| ⌃⌥S | Abrir Captura de tela |
| ⌃⌥R | Gravar uma área / parar a gravação |

### Vários monitores

O painel aparece em todos os monitores conectados, cada um com o seu estado aberto ou fechado. Dá para deixar só na tela do MacBook.

### Configurações

<img src="docs/screenshots/configuracoes.png" width="560" alt="Janela de configurações no painel Módulos">

Abertas pela engrenagem dentro do notch ou pelo ícone da barra de menus. Cada módulo pode ser ligado ou desligado, e quase tudo é ajustável: como o notch abre, tempos de espera, quais ferramentas de IA acompanhar, pasta das capturas, tamanho do histórico, blocos da tela inicial e assim por diante.

Também há:

- Abrir junto com o sistema: vem ligado. Na primeira execução o app se registra para iniciar com o Mac (ou com o Windows); dá para desligar em Configurações › Geral.
- Tela de boas-vindas, que explica cada permissão e deixa liberar na hora.
- Idioma: igual ao do sistema, português ou inglês.
- Exportar e importar as configurações em um arquivo.
- Aviso de versão nova, com link para a página de download.

## Versões

| Versão | O que mudou |
|---|---|
| 0.4.1 | Windows: notch minimizado quando fechado, animações novas, controles com a aparência da versão macOS e tela de boas-vindas |
| 0.4.0 | Volume por app e por aba, opção de aparecer em capturas, e o app passa a abrir junto com o sistema por padrão |
| 0.3.0 | Primeira versão para Windows; a release passa a ter um arquivo por sistema |
| 0.2.1 | Ícone de anotar mais legível, ajuste visual nas configurações e imagens no README |
| 0.2.0 | Downloads, anotação de prints, vários monitores, boas-vindas, inglês, exportar/importar configurações e aviso de atualização |

Todas as versões ficam em [Releases](https://github.com/Nicollasarcanjo/OpenNotch/releases).

## Como compilar

### macOS

Requisitos: macOS 14 ou mais recente e Xcode (ou as Command Line Tools) com Swift 5.9+.

```bash
./build.sh && open build/OpenNotch.app
```

O script compila em modo release e monta `build/OpenNotch.app`. Se houver um certificado "Apple Development" no Keychain, o app é assinado com ele; assim o macOS mantém as permissões entre uma compilação e outra. Sem certificado, a assinatura é ad hoc e as permissões são pedidas de novo a cada compilação.

### Windows

Requisitos: [SDK do .NET 10](https://dotnet.microsoft.com/download). O código fica em `opennotch_windows/`.

```bash
dotnet run --project opennotch_windows/OpenNotch.Windows.csproj
```

Para gerar o executável único, como o da release:

```bash
dotnet publish opennotch_windows/OpenNotch.Windows.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o out
```

Dá para compilar a versão Windows a partir do macOS ou do Linux (só não para executar).

### Publicar

Para publicar uma versão, atualize o arquivo `VERSION` e envie uma tag (`git tag v0.4.1 && git push origin v0.4.1`). O GitHub Actions compila as duas versões e cria a release com `OpenNotch-macOS.zip` e `OpenNotch-Windows.zip`. O texto da release vem de `.github/release-notes.md`.

Para uma versão notarizada (que abre em qualquer Mac sem aviso), é preciso uma conta paga do Apple Developer Program; o passo a passo está em `Scripts/notarize.sh`.

As imagens deste README são geradas pelo próprio app, em modo de demonstração e com dados fictícios, sem capturar a tela:

```bash
./Scripts/make-screenshots.sh
```

Para regenerar o ícone:

```bash
./Scripts/make-icon.sh
```

## Permissões

O macOS pede cada uma na primeira vez que o recurso é usado:

| Permissão | Para quê |
|---|---|
| Automação (Spotify, Music) | Controlar a reprodução e ler a capa |
| Gravação de Tela e Áudio do Sistema | Prints, gravações e volume por app |
| Calendários | Mostrar os eventos de hoje |
| Arquivos da Mesa | Ler os prints feitos pelos atalhos do macOS |
| Pasta Downloads | Mostrar o progresso dos downloads |

## Privacidade

- Nada é enviado para servidores do OpenNotch; ele não tem servidores.
- O histórico de textos copiados e as anotações ficam só neste Mac, em `~/Library/Application Support/OpenNotch`.
- A extensão do navegador conversa apenas com o app, em `127.0.0.1`.
- Para buscar a capa de uma música quando a Automação não está liberada, o app consulta os serviços públicos do Spotify (pelo id da faixa) e do iTunes (por título e artista).

## Limitações conhecidas

- A capa é sempre estática: as capas animadas do Spotify (Canvas) e do Apple Music não são expostas aos outros apps.
- O uso do limite do plano do Claude não é mostrado, porque não fica em nenhum arquivo local.
- A detecção do Antigravity é aproximada e pode avisar "terminou" numa pausa longa do agente.
- O indicador de volume e brilho aparece junto com o aviso padrão do macOS, sem substituí-lo.
- Widgets do macOS não podem ser embutidos; os blocos da tela inicial são do próprio app.
- A extensão do navegador ainda não suporta Safari nem Firefox, e é instalada manualmente.
- A versão Windows ainda não tem gravação de tela, anotação de prints, tela inicial personalizável nem calendário, e a janela de configurações dela ainda usa a aparência padrão do Windows.
- O app ainda não é notarizado; por isso o macOS pede a liberação manual na primeira abertura.
- A atualização não é automática: o app avisa e a instalação é manual.
- A gravação de tela pega só o monitor principal.
- O volume por app, no macOS, mostra só o que está tocando naquele momento, e um app com o volume alterado volta a 100% quando o OpenNotch é fechado.
- O volume por aba só funciona nos navegadores com a extensão instalada; depois de atualizar o OpenNotch, baixe e recarregue a extensão.

## Contribuir

As regras do projeto estão em [AGENTS.md](AGENTS.md): arquitetura das duas versões, boas práticas de Swift e C#, como abrir um pull request e a tabela de paridade. A regra principal é que uma funcionalidade nova entra no macOS e no Windows no mesmo pull request.

## Estrutura do projeto

```
Sources/OpenNotch/
  main.swift, AppDelegate.swift     ponto de entrada e ícone da barra de menus
  NotchController.swift             janela sobre o notch e ligação entre os módulos
  NotchModel.swift                  estado aberto/fechado e abas
  NotchRootView.swift               interface do notch aberto e fechado
  Prefs.swift, SettingsWindow.swift preferências e janela de configurações
  HotKeys.swift                     atalhos de teclado globais
  BrowserBridge.swift               servidor local que recebe a música do navegador
  Updater.swift, Onboarding.swift   aviso de versão nova e tela de boas-vindas
  Localization.swift                função de tradução (as frases em inglês ficam em Resources/en.lproj)
  ProcScan.swift, RegionSelector.swift
  Modules/                          um arquivo por funcionalidade
opennotch_windows/                  versão Windows (C# + WPF)
  src/Core/                         preferências, tradução, atalhos e chamadas ao Windows
  src/Modules/                      lógica de cada funcionalidade
  src/Views/                        janela do notch, abas e configurações
Extension/                          extensão do navegador (usada pela versão macOS)
Scripts/                            ícone, imagens do README e notarização
docs/screenshots/                   imagens do README
```

## Licença

O OpenNotch é distribuído sob a [PolyForm Noncommercial License 1.0.0](LICENSE.md).

Em resumo: você pode usar, estudar, modificar e redistribuir o app e o código livremente, desde que **não seja para fins comerciais**. Não é permitido vender o app, cobrar pelo acesso a ele nem usá-lo para obter lucro. O texto da licença é o que vale; este resumo não o substitui.
