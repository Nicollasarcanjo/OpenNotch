## O que muda

<!-- Uma ou duas frases: o que o usuário passa a ver ou a poder fazer. -->

## Plataformas

- [ ] macOS (`Sources/OpenNotch`)
- [ ] Windows (`opennotch_windows`)
- [ ] Só uma delas, e o motivo está explicado abaixo e na tabela de paridade do `AGENTS.md`

## Conferência

- [ ] `swift build -c release` passa
- [ ] `dotnet build opennotch_windows/OpenNotch.Windows.csproj -c Release` passa
- [ ] Frases novas estão em `Resources/en.lproj/Localizable.strings` e rodei `python3 Scripts/sync-strings.py`
- [ ] Opções novas existem nas preferências das duas versões, com o mesmo nome e o mesmo padrão
- [ ] README atualizado (funcionalidades e, se mudou a interface, `./Scripts/make-screenshots.sh`)

## Como foi testado

<!-- Diga o que foi de fato executado e visto funcionando, e em qual sistema.
     Se uma das versões só foi compilada, escreva isso com todas as letras. -->
