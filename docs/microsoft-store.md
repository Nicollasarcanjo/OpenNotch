# Publicar na Microsoft Store

O pacote da loja é o `OpenNotch-Store.msix`, gerado junto com cada release. Este guia cobre o que é feito uma vez e o que se repete a cada versão.

## Uma vez

1. **Conta**: crie a conta de desenvolvedor individual em https://storedeveloper.microsoft.com (gratuita; pede verificação de identidade com documento e selfie).
2. **Nome**: no Partner Center, crie um produto do tipo "MSIX ou PWA" e reserve o nome **OpenNotch**.
3. **Identidade**: em *Gerenciamento do produto › Identidade do produto*, copie três valores e cadastre-os no GitHub em *Settings › Secrets and variables › Actions › Variables*:

   | Variável no GitHub | Valor no Partner Center |
   |---|---|
   | `MSIX_IDENTITY_NAME` | Package/Identity/Name |
   | `MSIX_PUBLISHER` | Package/Identity/Publisher (começa com `CN=`) |
   | `MSIX_PUBLISHER_DISPLAY` | Package/Properties/PublisherDisplayName |

   Os valores atuais do produto já estão como padrão em `.github/workflows/release.yml`; as variáveis só são necessárias se a identidade mudar. Há também `MSIX_DISPLAY_NAME`, que precisa ser exatamente um dos nomes reservados para o produto (hoje, "OpenNotch - Notch for Windows").
4. **Política de privacidade**: use o endereço público de [PRIVACY.md](../PRIVACY.md):
   `https://github.com/Nicollasarcanjo/OpenNotch/blob/main/PRIVACY.md`

## A cada versão

1. Publique a release normalmente (tag `v*`). O arquivo `OpenNotch-Store.msix` aparece entre os anexos.
2. No Partner Center, crie uma submissão e envie esse arquivo em *Pacotes*.
3. Preencha ou revise a ficha (descrição, capturas de tela, categoria, classificação etária).
4. Em *Opções de submissão*, justifique a capacidade restrita `runFullTrust`. Texto sugerido:

   > O OpenNotch é um app de desktop (WPF) que precisa de acesso completo para: listar e encerrar processos no gerenciador de apps; ajustar o volume de outros apps pela API de sessões de áudio; capturar a tela; e ler arquivos de estado de ferramentas de IA na pasta do usuário.

5. Envie para certificação.

## Diferenças da versão da loja

O mesmo código roda dos dois jeitos; `Packaged.IsPackaged` (em `src/Core/Packaged.cs`) decide o que muda:

| | Avulso (GitHub) | Loja (MSIX) |
|---|---|---|
| Abrir com o Windows | Entrada no registro do usuário | Tarefa de inicialização do manifesto |
| Atualização | O app avisa e abre a página do GitHub | A loja atualiza; o aviso fica escondido |
| Letra da música | Ligada por padrão | Desligada por padrão |
| Assinatura | Nenhuma (aviso do SmartScreen) | Assinado pela loja |

## Gerar o pacote à mão

Num Windows com o SDK do .NET e o Windows SDK:

```powershell
pwsh opennotch_windows/Package/build-msix.ps1 -Version 0.6.0
```

O pacote sai sem assinatura, porque quem assina é a loja. Para instalar localmente e testar, ele precisa ser assinado com um certificado de teste cujo assunto seja igual ao `Publisher` do manifesto.

## O que ainda não foi verificado

O pacote é montado e validado pelo `makeappx` a cada push, mas nunca foi instalado num Windows nem enviado à loja. A tarefa de inicialização e o comportamento do app empacotado só serão confirmados na primeira instalação.
