# AGENTS.md

Guia para agentes de IA (e pessoas) que trabalham neste repositório. Leia antes de mudar qualquer coisa.

## O projeto

O OpenNotch é um painel que fica no topo da tela: no macOS, sobre o notch; no Windows, como uma barra no centro do topo. Ele abre ao passar o mouse e reúne música, agentes de IA, apps abertos, captura de tela, textos, arquivos, timers e monitor do sistema.

É gratuito, sem anúncios, e distribuído sob a PolyForm Noncommercial 1.0.0 (uso não comercial).

Existem **duas implementações nativas do mesmo produto**, no mesmo repositório:

| | macOS | Windows |
|---|---|---|
| Pasta | raiz (`Sources/OpenNotch`) | `opennotch_windows/` |
| Linguagem | Swift 5.9+ | C# (.NET 10) |
| Interface | SwiftUI + AppKit | WPF |
| Mínimo | macOS 14 | Windows 10 (19041) |
| Compilar | `./build.sh` | `dotnet build opennotch_windows/OpenNotch.Windows.csproj -c Release` |
| Dados do usuário | `~/Library/Application Support/OpenNotch` | `%APPDATA%\OpenNotch` |

Não há código compartilhado entre as duas; o que é compartilhado são o desenho, os nomes, as regras de cada módulo e a tabela de tradução.

## Regra principal: paridade entre macOS e Windows

**Toda funcionalidade nova, correção de comportamento ou opção nova deve ser feita nas duas versões no mesmo pull request.**

Se não for possível em uma delas (API que não existe no sistema, por exemplo), o PR deve:

1. dizer isso na descrição, com o motivo;
2. atualizar a tabela de paridade abaixo;
3. atualizar a seção de limitações do `README.md`.

Não deixe uma versão "para depois" sem registrar. A tabela é a fonte da verdade sobre o que falta.

### Tabela de paridade

| Recurso | macOS | Windows | Observação |
|---|---|---|---|
| Painel no topo, abre ao passar o mouse | Sim | Sim | |
| Um painel por monitor | Sim | Sim | |
| Indicadores com o painel fechado | Sim | Opcional | No Windows o padrão é ficar minimizado (um risco no topo), porque lá não há notch físico e a barra ocuparia espaço; a opção "Mostrar indicadores com o notch fechado" liga os indicadores |
| Música: mostrar e controlar | Sim | Sim | macOS: Spotify, Apple Music e extensão de navegador. Windows: controles de mídia do sistema, que já cobrem os navegadores |
| Extensão de navegador | Sim | Não precisa | |
| Agentes de IA: Claude Code e Codex | Sim | Sim | Mesma leitura de arquivos |
| Agentes de IA: Antigravity e ferramentas personalizadas | Sim | Não | A fazer |
| Aviso quando um agente termina | Sim | Sim | |
| Apps abertos com CPU, GPU e memória | Sim | Sim | Agrupamento: macOS por app responsável; Windows por nome do executável |
| Volume por app | Sim | Sim | macOS: process taps do CoreAudio (14.2+). Windows: sessões de áudio do sistema |
| Volume por aba do navegador | Sim | Não | Depende da extensão, que o Windows ainda não usa |
| Print de tela toda e de área | Sim | Sim | |
| Gravação de tela | Sim | Não | A fazer (Windows.Graphics.Capture) |
| Anotar print | Sim | Não | A fazer |
| Opção de aparecer ou não em capturas de tela | Sim | Sim | Padrão: não aparece. Windows usa SetWindowDisplayAffinity |
| Galeria com os prints do sistema | Sim | Sim | Windows: pasta Imagens\Screenshots |
| Anotações, histórico de copiados e busca | Sim | Sim | |
| Bandeja de arquivos | Sim | Sim | |
| Downloads | Sim | Parcial | Windows mostra o tamanho baixado, sem porcentagem |
| Timers | Sim | Sim | |
| Monitor do sistema | Sim | Sim | |
| Tela inicial personalizável (blocos, GIF, imagens, atalhos) | Sim | Não | Windows tem música e relógio fixos |
| Calendário | Sim | Não | A fazer |
| Indicador de volume e brilho | Sim | Não | O Windows já tem o próprio |
| Atalhos globais | Sim | Sim | macOS ⌃⌥ + tecla; Windows Ctrl + Alt + tecla. Sem "gravar área" no Windows |
| Configurações, com liga/desliga por módulo | Sim | Sim | Windows tem menos opções |
| Português e inglês | Sim | Sim | Mesma tabela de frases |
| Exportar e importar configurações | Sim | Sim | Os arquivos não são intercambiáveis entre sistemas |
| Aviso de versão nova | Sim | Sim | |
| Boas-vindas na primeira execução | Sim | Sim | macOS pede as permissões; Windows explica que não há permissões e mostra as escolhas iniciais |
| Abrir ao iniciar o sistema | Sim | Sim | Ligado por padrão na primeira execução; o usuário pode desligar |

### Estado de verificação

A versão macOS é executada e conferida a cada mudança. A versão Windows, até agora, **só foi compilada** (inclusive a partir do macOS) e nunca foi executada por quem a escreveu. Trate qualquer comportamento dela como não confirmado até alguém rodar num Windows de verdade, e diga isso com clareza nos PRs.

## Arquitetura

As duas versões seguem o mesmo desenho, com nomes equivalentes. Ao procurar onde algo fica em uma, o arquivo de mesmo nome na outra é o ponto de partida.

| Papel | macOS | Windows |
|---|---|---|
| Ponto de entrada, ícone de bandeja | `main.swift`, `AppDelegate.swift` | `src/App.xaml.cs` |
| Um painel por tela e ligação entre módulos | `NotchController.swift` (`ScreenNotch`) | `src/App.xaml.cs` + `src/Views/NotchWindow.xaml.cs` |
| Objetos compartilhados entre os painéis | `Services` em `NotchController.swift` | `src/Core/Services.cs` |
| Estado aberto/fechado e abas | `NotchModel.swift` | `NotchWindow.xaml.cs` |
| Preferências | `Prefs.swift` | `src/Core/Settings.cs` |
| Tradução | `Localization.swift` + `Resources/en.lproj` | `src/Core/Loc.cs` + `Strings.en.cs` (gerado) |
| Atalhos globais | `HotKeys.swift` | `src/Core/HotKeys.cs` |
| Um módulo = lógica + tela | `Sources/OpenNotch/Modules/<Nome>.swift` | `src/Modules/<Nome>.cs` + `src/Views/<Nome>View.xaml` |
| Configurações | `SettingsWindow.swift` | `src/Views/SettingsWindow.xaml` |

### Princípios que valem para as duas

- **Um módulo por funcionalidade.** Cada módulo tem um objeto de lógica (o "manager" ou "monitor") e uma tela. A tela não lê disco, rede nem APIs do sistema; ela só mostra o que o objeto publica e chama os métodos dele.
- **Módulos não se conhecem.** Quem liga um ao outro é o controlador (`NotchController` / `App`), por callbacks e eventos: "captura terminou → abrir o painel", "agente terminou → mostrar aviso".
- **Todo módulo pode ser desligado.** Há uma preferência `mod...` para cada um. Desligado, ele some da interface e para de trabalhar em segundo plano (sem timers, sem leitura de arquivos).
- **Medir só quando alguém está olhando.** Trabalho caro (lista de processos, GPU) só roda com a aba visível.
- **Nada bloqueia a thread da interface.** Leitura de arquivos grandes, processos e rede vão para segundo plano; o resultado volta para a thread principal antes de tocar em estado observado.
- **Somente leitura em dados de terceiros.** Os arquivos do Claude, do Codex e de outros apps são lidos, nunca alterados. Credenciais e tokens não são lidos em hipótese alguma.
- **Privacidade por padrão.** Nada sai da máquina, exceto consultas públicas já documentadas no README (capa de música, verificação de versão). Senhas marcadas como confidenciais não entram no histórico de copiados.
- **Falhas de sistema não derrubam o app.** APIs de sistema falham (permissão negada, processo que fechou, arquivo travado). Trate o erro no ponto em que acontece e degrade o recurso; explique num comentário de uma linha o que acontece com o usuário nesse caso.
- **Detecção aproximada é sinalizada.** Quando o estado vem de heurística (atividade de arquivos, CPU), a interface diz "aprox." e o comentário explica o limite.

### Boas práticas em Swift (macOS)

- SwiftUI para as telas; AppKit só onde o SwiftUI não chega (janela sobre o notch, clique secundário, GIF animado).
- Os objetos de lógica são `final class ... : ObservableObject` com `@Published private(set)`: a tela lê, só o objeto escreve.
- Os objetos são criados uma vez em `Services` e entregues às telas por `environmentObject`. Não crie singletons novos; `Prefs.shared` é a exceção existente.
- Textos na tela: literais em `Text("…")`, `Button("…")` etc. já são traduzidos. Quando o texto é montado como `String`, use `L("…")`. Nunca concatene frases com `+` (quebra a tradução).
- Preferências novas entram em `Prefs.Key` **e** em `Prefs.defaults`, com o padrão.
- Timers: `Timer` adicionado ao `RunLoop.main` no modo `.common`, guardado em propriedade e invalidado quando o recurso é desligado.
- APIs privadas só com `dlsym` e com plano B quando o símbolo não existir. Explique no comentário o que deixa de funcionar.
- O projeto compila em modo de linguagem Swift 5 (`swift-tools-version:5.9`); não dependa de regras de concorrência estrita do Swift 6.
- Sem dependências externas. Se uma for realmente necessária, justifique no PR.

### Boas práticas em C# (Windows)

- **A aparência segue a versão macOS.** Dentro do notch, nada de controles com cara de Windows clássico: barras de rolagem, controles deslizantes, menus e dicas têm estilo próprio, definido em `NotchWindow.xaml`. Controle novo dentro do notch precisa de estilo escuro equivalente ao do macOS.
- Animações com duração e curva explícitas; abrir usa um leve efeito de mola, fechar é mais curto. Não troque de estado sem transição.

- WPF com telas em XAML e código de tela mínimo: o `.xaml.cs` só trata eventos e repassa para o objeto de lógica.
- Os objetos de lógica herdam de `Observable` e ficam em `Services.Instance`. As telas usam `DataContext` e `Binding`.
- Coleções mostradas na tela são `ObservableCollection<T>` e só são alteradas na thread da interface.
- Trabalho em segundo plano com `Task.Run` + `await`; nada de `.Result` ou `.Wait()` na thread da interface.
- `Nullable` está ligado: resolva os avisos em vez de usar `!`.
- Chamadas à API do Windows ficam em `src/Core/Native.cs`, não espalhadas pelos módulos.
- Textos: `{l:T 'frase'}` no XAML e `Loc.T("frase")` no código. Marcadores são `{0}`, `{1}`.
- Preferências novas são uma propriedade em `Settings` usando `Change(ref ...)`, com o mesmo nome (em PascalCase) e o mesmo padrão da versão macOS.
- Arquivos de outros apps são abertos com `FileShare.ReadWrite`, porque o dono pode estar escrevendo.
- Sem pacotes NuGet além do SDK. Se um for realmente necessário, justifique no PR.

## Tradução

A interface é escrita em português; a chave de tradução é a própria frase em português.

- **Fonte única:** `Resources/en.lproj/Localizable.strings`. Ela serve às duas versões.
- Depois de mexer nela, rode `python3 Scripts/sync-strings.py`, que gera `opennotch_windows/src/Core/Strings.en.cs`. Não edite o arquivo gerado.
- No `.strings` os marcadores são os do macOS (`%@`, `%lld`); o script converte para `{0}`, `{1}`. No código C# a chave já usa `{0}`.
- Frase usada só no Windows também entra no `.strings`, na seção do fim do arquivo.
- O CI falha se o arquivo gerado estiver desatualizado.

## Como compilar e conferir

```bash
# macOS
./build.sh && open build/OpenNotch.app

# Windows (funciona também a partir do macOS ou do Linux, só para conferir que compila)
dotnet build opennotch_windows/OpenNotch.Windows.csproj -c Release

# Tradução
python3 Scripts/sync-strings.py
```

No macOS dá para conferir a interface sem capturar a tela: `OPENNOTCH_DEMO=1 OPENNOTCH_TAB=<aba> OPENNOTCH_SNAPSHOT=<arquivo.png>` faz o app desenhar a aba com dados fictícios num PNG e sair. `./Scripts/make-screenshots.sh` usa isso para gerar as imagens do README.

Não existe suíte de testes automatizados. Enquanto não existir, "funciona" significa que alguém executou e viu funcionar; "compila" é outra afirmação e deve ser dita como tal.

## Pull requests

- **Um assunto por PR.** Funcionalidade nova, correção e refatoração vão em PRs separados.
- **Paridade no mesmo PR**, conforme a regra principal.
- **Título** em português, no imperativo ou descritivo curto: "Adiciona gravação de área", "Corrige capa que não carregava".
- **Descrição** pelo modelo em `.github/pull_request_template.md`: o que muda para o usuário, plataformas e como foi testado.
- **Seja exato sobre o teste.** Diga o que foi executado e em qual sistema. Se a versão Windows só foi compilada, escreva "Windows: só compilado".
- **CI verde** antes de pedir revisão: as duas versões compilam e a tabela de tradução está em dia.
- **Atualize a documentação junto:** README (funcionalidades e limitações), a tabela de paridade deste arquivo e, se a interface mudou, as imagens.
- **Commits** pequenos e com mensagem que explica o porquê quando ele não é óbvio. Sem commits de "ajustes" misturando assuntos.
- **Não inclua** pastas de build (`build/`, `.build/`, `bin/`, `obj/`), arquivos pessoais nem dados de usuário.
- **Nunca** faça push direto na `main` com mudança de comportamento sem PR, nem force-push em branch compartilhada.

## Publicar uma versão

1. Atualize `VERSION` e `.github/release-notes.md` (novidades no topo).
2. Atualize a tabela "Versões" do README.
3. Faça o commit e envie a tag: `git tag v0.3.0 && git push origin main v0.3.0`.
4. O GitHub Actions cria uma release com `OpenNotch-macOS.zip` e `OpenNotch-Windows.zip`.

Os dois apps saem sem assinatura reconhecida pelo sistema: o macOS e o Windows mostram um aviso na primeira abertura. As instruções para o usuário estão nas notas da release; mantenha-as lá.

## O que não fazer

- Copiar código, ícones, textos ou a marca de outros apps de notch. Tudo aqui é escrito do zero.
- Adicionar anúncios, telemetria, cobrança ou recursos bloqueados.
- Ler credenciais, tokens ou o conteúdo das conversas dos agentes de IA (só os metadados de estado e uso).
- Contornar permissões do sistema. Se o sistema nega, o recurso mostra o que falta e como liberar.
