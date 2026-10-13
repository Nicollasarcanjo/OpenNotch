# Gera o pacote MSIX da versão Windows, para enviar à Microsoft Store.
#
# Uso (num Windows com o SDK do .NET e o Windows SDK):
#   pwsh opennotch_windows/Package/build-msix.ps1 -Version 0.6.0
#
# A identidade do pacote vem do Partner Center (Identidade do produto). Passe pelos parâmetros
# ou pelas variáveis de ambiente MSIX_IDENTITY_NAME, MSIX_PUBLISHER e MSIX_PUBLISHER_DISPLAY.
# Sem elas, sai um pacote de teste, que serve para validar o manifesto mas não para a loja.
#
# O pacote sai sem assinatura: quem assina é a loja, na submissão.
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$IdentityName = $env:MSIX_IDENTITY_NAME,
    [string]$Publisher = $env:MSIX_PUBLISHER,
    [string]$PublisherDisplay = $env:MSIX_PUBLISHER_DISPLAY,
    [string]$Output = "OpenNotch-Store.msix"
)
$ErrorActionPreference = "Stop"

if (-not $IdentityName) { $IdentityName = "OpenNotch.Teste" }
if (-not $Publisher) { $Publisher = "CN=OpenNotch Teste" }
if (-not $PublisherDisplay) { $PublisherDisplay = "OpenNotch" }

$root = Split-Path -Parent $PSScriptRoot
$stage = Join-Path $root "out\msix"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }

# Pasta com o app completo (um MSIX leva os arquivos soltos, não o .exe único da versão avulsa).
dotnet publish (Join-Path $root "OpenNotch.Windows.csproj") -c Release -r win-x64 --self-contained true `
    -p:PublishSingleFile=false -p:DebugType=none -p:Version=$Version -o $stage
if ($LASTEXITCODE -ne 0) { throw "dotnet publish falhou" }

Copy-Item (Join-Path $PSScriptRoot "Assets") (Join-Path $stage "Assets") -Recurse

# A versão do pacote tem quatro partes, e a loja exige que a última seja zero.
$packageVersion = (($Version -split '\.')[0..2] -join '.') + ".0"
$manifest = Get-Content (Join-Path $PSScriptRoot "AppxManifest.xml") -Raw
$manifest = $manifest.Replace("__IDENTITY_NAME__", $IdentityName).Replace("__PUBLISHER__", $Publisher)
$manifest = $manifest.Replace("__PUBLISHER_DISPLAY__", $PublisherDisplay).Replace("__VERSION__", $packageVersion)
Set-Content (Join-Path $stage "AppxManifest.xml") $manifest -Encoding utf8

$makeappx = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Recurse -Filter makeappx.exe |
    Where-Object { $_.FullName -like "*\x64\*" } | Sort-Object FullName | Select-Object -Last 1
if (-not $makeappx) { throw "makeappx.exe não encontrado; instale o Windows SDK" }

& $makeappx.FullName pack /d $stage /p $Output /o
if ($LASTEXITCODE -ne 0) { throw "makeappx falhou (o manifesto ou os arquivos têm algum problema)" }
Write-Host "OK: $Output ($IdentityName, $packageVersion)"
