# Política de privacidade do OpenNotch

Última atualização: 13 de outubro de 2026.

O OpenNotch é um app gratuito para macOS e Windows. Ele não tem servidores, contas de usuário, anúncios nem telemetria. Este documento descreve quais dados o app acessa no seu computador e em quais casos alguma informação sai dele.

## O que fica só no seu computador

O app lê os dados abaixo para mostrar as funcionalidades. Eles não são enviados a ninguém.

| Dado | Para quê | Onde fica |
|---|---|---|
| Música tocando (título, artista, álbum, capa) | Mostrar e controlar a reprodução | Só na memória |
| Área de transferência (textos copiados) | Histórico de textos copiados | Arquivo local, se a opção de manter o histórico estiver ligada. Senhas marcadas como confidenciais por gerenciadores de senha não entram |
| Anotações que você escreve | Aba Textos | Arquivo local |
| Processos e apps abertos, uso de CPU, GPU e memória | Gerenciador de apps e monitor do sistema | Só na memória |
| Volume de cada app | Volume por app | Só na memória |
| Arquivos de estado do Claude Code, Codex e Antigravity | Mostrar as sessões de agentes de IA e o uso. São lidos apenas metadados (nome da sessão, pasta, estado, contagem de tokens e limites); o conteúdo das conversas, as credenciais e os tokens de acesso não são lidos | Só na memória |
| Capturas e gravações de tela que você faz | Galeria de capturas | Pasta Imagens/OpenNotch |
| Arquivos que você solta na bandeja e atalhos de apps | Bandeja e tela inicial | Só o caminho do arquivo é guardado |
| Eventos do calendário (macOS) | Bloco de calendário | Só na memória |
| Preferências do app | Configurações | Arquivo local |

Os arquivos locais ficam em `~/Library/Application Support/OpenNotch` (macOS) ou `%APPDATA%\OpenNotch` (Windows). Desinstalar o app e apagar essa pasta remove tudo.

## Quando alguma informação sai do computador

| Situação | O que é enviado | Para quem | Como desligar |
|---|---|---|---|
| Letra da música | Título, artista e álbum da faixa | LRCLIB (lrclib.net) | Desligue "Mostrar a letra com o notch fechado". Na versão da Microsoft Store essa opção vem desligada |
| Capa da música, quando o player não a fornece (macOS) | Identificador da faixa, ou título e artista | Spotify e iTunes (serviços públicos de consulta) | Desligue o módulo Música |
| Aviso de versão nova (versões baixadas do GitHub) | Uma consulta sem dados pessoais | GitHub | Desligue "Verificar atualizações automaticamente" |

Esses serviços recebem o seu endereço IP, como qualquer site que você acessa, e têm as próprias políticas de privacidade.

## Extensão do navegador

A extensão opcional lê, nas abas de sites de música e vídeo, o que está tocando (título, artista, capa, posição) e aplica o volume que você escolher. Ela conversa apenas com o OpenNotch no mesmo computador, pelo endereço local `127.0.0.1`, e não envia nada para a internet.

## Permissões

O macOS pede permissão para Automação (controlar o Spotify e o Apple Music), Gravação de Tela e Áudio do Sistema (capturas e volume por app), Calendários e acesso às pastas Mesa e Downloads. Cada uma é pedida quando o recurso é usado pela primeira vez e pode ser revogada nos Ajustes do Sistema.

No Windows o app roda como um programa de desktop comum, com acesso equivalente ao do usuário.

## Crianças

O app não é direcionado a crianças e não coleta dados de ninguém.

## Mudanças e contato

Mudanças nesta política aparecem neste arquivo, no repositório do projeto. Dúvidas: abra uma issue em https://github.com/Nicollasarcanjo/OpenNotch/issues.

---

# OpenNotch privacy policy (English summary)

OpenNotch is a free app for macOS and Windows. It has no servers, user accounts, ads or telemetry.

**Stays on your computer:** the music playing, clipboard text history (optional local file; passwords flagged as confidential are skipped), your notes, running apps and their resource usage, per-app volume, state files of AI coding tools (metadata only: never conversation content, credentials or tokens), your screenshots and recordings, tray files, app shortcuts, calendar events (macOS) and app preferences.

**Leaves your computer only in these cases:** track title, artist and album are sent to LRCLIB (lrclib.net) to fetch synced lyrics, if that option is on (off by default in the Microsoft Store version); on macOS, a track identifier or title and artist may be sent to Spotify or iTunes public lookup services to fetch artwork; versions downloaded from GitHub query GitHub for new releases. Each can be turned off in Settings.

**Browser extension:** talks only to OpenNotch on the same computer, at `127.0.0.1`.

Contact: https://github.com/Nicollasarcanjo/OpenNotch/issues
