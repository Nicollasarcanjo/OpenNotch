#!/usr/bin/env python3
"""Gera a tabela de tradução da versão Windows a partir da tabela da versão macOS.

A fonte única das frases em inglês é Resources/en.lproj/Localizable.strings.
Rode este script sempre que mexer nela:  python3 Scripts/sync-strings.py
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Resources/en.lproj/Localizable.strings"
TARGET = ROOT / "opennotch_windows/src/Core/Strings.en.cs"

PAIR = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$')


def to_dotnet(text: str) -> str:
    """Troca os marcadores do macOS (%@, %lld) pelos do .NET ({0}, {1}), na ordem em que aparecem."""
    counter = iter(range(100))
    return re.sub(r"%(?:@|lld|d|lf)", lambda _: "{%d}" % next(counter), text)


def main() -> None:
    pairs = {}
    for line in SOURCE.read_text(encoding="utf-8").splitlines():
        match = PAIR.match(line.strip())
        if match:
            pairs[to_dotnet(match.group(1))] = to_dotnet(match.group(2))

    lines = [
        "// Arquivo gerado por Scripts/sync-strings.py a partir de Resources/en.lproj/Localizable.strings.",
        "// Não edite à mão: altere o .strings e rode o script.",
        "namespace OpenNotch;",
        "",
        "internal static class Strings",
        "{",
        "    public static readonly Dictionary<string, string> English = new()",
        "    {",
    ]
    for key in sorted(pairs):
        lines.append(f'        ["{key}"] = "{pairs[key]}",')
    lines += ["    };", "}", ""]
    TARGET.write_text("\n".join(lines), encoding="utf-8")
    print(f"OK: {len(pairs)} frases em {TARGET.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
