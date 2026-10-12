## Novidades

- **Versão para Windows**: o OpenNotch agora também existe para Windows 10 e 11, como uma barra no topo da tela.
- A release passa a ter um arquivo para cada sistema.

## Qual arquivo baixar

| Sistema | Arquivo |
|---|---|
| macOS 14 ou mais recente (Apple Silicon e Intel) | **OpenNotch-macOS.zip** |
| Windows 10 ou 11 (64 bits) | **OpenNotch-Windows.zip** |

## Como instalar no macOS

1. Baixe o **OpenNotch-macOS.zip** e dê dois cliques para descompactar.
2. Arraste o **OpenNotch** para a pasta Aplicativos.
3. Na primeira vez, o macOS bloqueia a abertura porque o app ainda não é notarizado pela Apple. Para liberar: abra **Ajustes do Sistema › Privacidade e Segurança**, role até o aviso sobre o OpenNotch e clique em **Abrir Mesmo Assim**.

Pelo Terminal, o mesmo efeito:

```bash
xattr -dr com.apple.quarantine /Applications/OpenNotch.app
```

## Como instalar no Windows

1. Baixe o **OpenNotch-Windows.zip** e extraia o **OpenNotch.exe** para uma pasta sua (por exemplo, Documentos).
2. Dê dois cliques no **OpenNotch.exe**. Não precisa instalar nada.
3. Na primeira vez, o Windows mostra o aviso "O Windows protegeu o computador", porque o app ainda não tem assinatura digital. Clique em **Mais informações** e depois em **Executar assim mesmo**.

O app fica na área de notificação (perto do relógio). Para abrir com o Windows, ligue a opção em Configurações.

A versão Windows é a primeira e tem menos recursos que a do macOS; a lista do que existe em cada uma está no README.

---

## Which file to download

| System | File |
|---|---|
| macOS 14 or later (Apple Silicon and Intel) | **OpenNotch-macOS.zip** |
| Windows 10 or 11 (64-bit) | **OpenNotch-Windows.zip** |

**macOS:** unzip, drag OpenNotch to Applications, then allow it in **System Settings › Privacy & Security › Open Anyway** (the app is not notarized yet).

**Windows:** unzip and run **OpenNotch.exe**. On the SmartScreen warning, click **More info** and then **Run anyway** (the app is not code-signed yet).
