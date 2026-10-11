# agent-team-kit — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un kit global (skills + CLI PowerShell) que, solo cuando el usuario lo invoca, arma y retoma en cualquier proyecto un equipo de agentes coordinado por Herdr con vault de Obsidian y memoria engram.

**Architecture:** La lógica determinista vive en un módulo PowerShell (`lib/*.ps1` → `TeamKit.psm1`) expuesto por un CLI único (`team.ps1 <comando>`). Los seis skills (`skills/team-*/SKILL.md`) son instrucciones para los agentes que llaman a ese CLI y a `herdr`. `install.ps1` copia el runtime a `~/.agents/team-kit`, los skills a `~/.agents/skills` (Kimi y Agy los leen nativo) y crea junctions en `~/.claude/skills` para Claude.

**Tech Stack:** Windows PowerShell 5.1, Pester 3.4.0 (incluido en Windows), Herdr 0.8.2 CLI, Markdown/Obsidian, engram MCP.

**Spec:** `docs/superpowers/specs/2026-10-11-agent-team-kit-design.md`

## Global Constraints

- Solo Windows PowerShell 5.1 (`powershell.exe`). No usar `pwsh`, no instalar módulos. Tests con la sintaxis de **Pester 3.4.0**: `Should Be`, `Should BeExactly`, `Should Match`, `Should Throw '<texto contenido>'`, `Should Exist`, `Mock -ModuleName TeamKit`, `Assert-MockCalled`, `$TestDrive`, `BeforeEach`/`AfterEach`.
- Todos los `.ps1`/`.psm1` (lib, CLI, install, tests) son **solo ASCII**: PowerShell 5.1 lee los scripts sin BOM como ANSI. Mensajes en español **sin tildes** dentro del código. Para probar caracteres no ASCII en tests, construirlos con `[char]0x00F1` o `[char]::ConvertFromUtf32(...)`.
- Todo archivo que el kit escribe en un proyecto: UTF-8 **sin BOM** vía `Write-TeamFile`; toda lectura vía `Read-TeamFile`.
- Plantillas (`templates/*.md`, `templates/verify.toml`) y `SKILL.md` en español (UTF-8 sin BOM, pueden llevar tildes). Nombres de skills, scripts y funciones en inglés.
- Nada se ejecuta automáticamente: sin hooks; los skills solo corren cuando el usuario los invoca.
- Nada específico de un proyecto dentro del kit. El kit solo escribe en: el proyecto donde se invoca, `~/.agents/team-kit`, `~/.agents/skills/team-*`, `~/.claude/skills/team-*` y la carpeta de índice central configurada.
- Toda llamada a `herdr` desde el módulo pasa por `Invoke-Herdr`.
- Desde Git Bash, anteponer `MSYS_NO_PATHCONV=1` cuando un argumento empiece con `/`.
- Nombres de agente: `^[a-z][a-z0-9_-]{0,31}$`. Nombre de proyecto: `^[a-z0-9][a-z0-9-]{0,62}$`. `de`/`para`/`hilo` de handoff: `^[a-z0-9][a-z0-9_-]{0,62}$`.
- Tipos de handoff: `objetivo`, `plan`, `ejecucion`, `listo-para-verificar`, `hallazgos`, `aprobado`, `bloqueo`. Estados: `pendiente`, `en-curso`, `hecho`, `no-entregado`, `cerrado`. (**Desviación del spec:** se agrega `objetivo`, orquestador→planificador, porque el spec no definía cómo entra un objetivo nuevo del usuario al ciclo.)
- Commits: Conventional Commits en inglés, siempre con `git -c user.name="jcgmU" -c user.email="jcgm1047@gmail.com" commit ...` y el trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Nunca modificar la configuración de git.
- Correr toda la suite: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run.ps1` (desde la raíz del repo). Un archivo: `powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Script tests\<Nombre>.Tests.ps1"`.

## Review Focus

1. **Rutas con espacios y OneDrive** (p.ej. `...\OneDrive\Desktop\Mi Proyecto`): todo debe funcionar igual. → test en Task 3 (`Initialize-TeamBrain` en `Mi Proyecto`) y Task 1 (`Find-TeamProjectRoot`).
2. **Cuerpos/criterios de handoff con comillas dobles, ñ, tildes y emoji**: el archivo debe conservarlos byte a byte, sin BOM, y el frontmatter seguir siendo legible. → test en Task 5.
3. **Dos handoffs del mismo emisor al mismo destinatario en el mismo minuto**: el segundo no puede pisar al primero. → test en Task 5.
4. **`CLAUDE.md`/`AGENTS.md` del usuario ya existentes, y regenerar dos veces**: el contenido del usuario se conserva y el bloque del equipo aparece una sola vez. → test en Task 3.
5. **`team.toml`/`verify.toml` editados a mano o por un LLM con TOML no soportado** (tabla inline, texto multilínea): error claro con número de línea; `team-doctor` lo reporta como `fail` sin romperse. → tests en Task 1 y Task 6.

---

## Estructura de archivos

```
agent-team-kit/
  lib/
    TeamKit.psm1     carga todos los lib/*.ps1 y exporta funciones Verb-Noun
    Common.ps1       Resolve-TeamPath, Write-TeamFile, Read-TeamFile, Find-TeamProjectRoot
    Toml.ps1         subconjunto TOML: ConvertFrom/To-TeamToml, Read/Write-TeamConfig
    State.ps1        Read-TeamState, Update-TeamState (bloque de brain/Estado/STATE.md)
    Scaffold.ps1     plantillas, Initialize-TeamBrain, Complete-TeamBootstrap, Write-TeamDocs,
                     Add-TeamPointerBlock, New-TeamCentralIndex, Set-TeamRole, Get-TeamKitSetting
    Herdr.ps1        Invoke-Herdr, Get-TeamAgents, Set-TeamAgentNames, Get-AgentVersion, Save-TeamCheckpoint
    Handoff.ps1      New-TeamHandoff, Read-HandoffFrontmatter, Set-HandoffState, Get-TeamHandoffs,
                     Get-ThreadRejectionCount, Send-TeamHandoff
    Health.ps1       Get-EngramDataDir, Test-TeamHealth, Format-TeamHealth
    Verify.ps1       Invoke-TeamVerify
  templates/         00-Inicio.md, STATE.md, Protocolo.md, Comandos.md, ficha-plantilla.md,
                     pointer-block.md, central-index.md, verify.toml
  team.ps1           CLI: team.ps1 <comando> --opcion valor
  install.ps1        instala runtime + skills + junctions
  skills/            team-bootstrap, team-resume, team-handoff, team-verify, team-checkpoint, team-doctor
  tests/             run.ps1 + <Area>.Tests.ps1
  README.md
```

---

### Task 1: Base del módulo, E/S de archivos y subconjunto TOML

**Files:**
- Create: `lib/TeamKit.psm1`, `lib/Common.ps1`, `lib/Toml.ps1`
- Create: `tests/run.ps1`, `tests/Common.Tests.ps1`, `tests/Toml.Tests.ps1`

**Interfaces:**
- Produces:
  - `Resolve-TeamPath -Path <string>` → `[string]` ruta absoluta.
  - `Write-TeamFile -Path <string> -Content <string>` → crea carpetas, escribe UTF-8 sin BOM.
  - `Read-TeamFile -Path <string>` → `[string]`; lanza `No existe el archivo: <ruta>`.
  - `Find-TeamProjectRoot [-StartPath <string>]` → `[string]` carpeta que contiene `.team\team.toml`; lanza `No se encontro ...`.
  - `ConvertFrom-TeamToml -Text <string>` → `[ordered]` (tablas anidadas = ordered dicts; `[[x]]` = ArrayList de ordered dicts; arreglos = `object[]`).
  - `ConvertTo-TeamToml -Data <IDictionary>` → `[string]`.
  - `Read-TeamConfig -Path` / `Write-TeamConfig -Path -Data`.

- [ ] **Step 1: Crear el cargador del módulo y el runner de tests**

`lib/TeamKit.psm1`:
```powershell
$ErrorActionPreference = 'Stop'
foreach ($file in (Get-ChildItem -Path $PSScriptRoot -Filter '*.ps1' | Sort-Object Name)) {
    . $file.FullName
}
Export-ModuleMember -Function '*-*'
```

`tests/run.ps1`:
```powershell
$ErrorActionPreference = 'Stop'
Import-Module Pester -RequiredVersion 3.4.0
$result = Invoke-Pester -Script $PSScriptRoot -PassThru
if ($result.FailedCount -gt 0) { exit 1 }
exit 0
```

- [ ] **Step 2: Escribir los tests que fallan**

`tests/Common.Tests.ps1`:
```powershell
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here '..\lib\TeamKit.psm1') -Force

Describe 'Write-TeamFile / Read-TeamFile' {
    It 'escribe UTF-8 sin BOM y conserva caracteres no ASCII' {
        $enye = [string][char]0x00F1
        $p = Join-Path $TestDrive 'sub dir\a.md'
        Write-TeamFile -Path $p -Content "ma${enye}ana"
        $bytes = [System.IO.File]::ReadAllBytes($p)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should Be $false
        Read-TeamFile -Path $p | Should BeExactly "ma${enye}ana"
    }
    It 'falla con mensaje claro si el archivo no existe' {
        { Read-TeamFile -Path (Join-Path $TestDrive 'nada.md') } | Should Throw 'No existe el archivo'
    }
}

Describe 'Find-TeamProjectRoot' {
    It 'sube por las carpetas hasta encontrar .team\team.toml (ruta con espacios)' {
        $root = Join-Path $TestDrive 'Mi Proyecto'
        New-Item -ItemType Directory -Force -Path (Join-Path $root '.team'), (Join-Path $root 'a\b') | Out-Null
        Write-TeamFile -Path (Join-Path $root '.team\team.toml') -Content ''
        Find-TeamProjectRoot -StartPath (Join-Path $root 'a\b') | Should Be $root
    }
    It 'falla si no hay proyecto' {
        $d = Join-Path $TestDrive 'suelto'
        New-Item -ItemType Directory -Force -Path $d | Out-Null
        { Find-TeamProjectRoot -StartPath $d } | Should Throw 'No se encontro'
    }
}
```

`tests/Toml.Tests.ps1`:
```powershell
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here '..\lib\TeamKit.psm1') -Force

Describe 'ConvertFrom-TeamToml' {
    It 'lee secciones anidadas, textos, numeros, booleanos y arreglos' {
        $t = @'
# comentario
[project]
name = "demo"
created = '2026-10-11'
count = 3
active = true
tags = ["a", 'b']

[roles.planner]
agent_name = "kimi"
'@
        $d = ConvertFrom-TeamToml -Text $t
        $d.project.name | Should Be 'demo'
        $d.project.created | Should Be '2026-10-11'
        $d.project.count | Should Be 3
        $d.project.active | Should Be $true
        $d.project.tags.Count | Should Be 2
        $d.project.tags[1] | Should Be 'b'
        $d.roles.planner.agent_name | Should Be 'kimi'
    }
    It 'lee arreglos de tablas [[check]]' {
        $t = "[[check]]`nname = `"a`"`n`n[[check]]`nname = `"b`"`nexpect_exit = 1"
        $d = ConvertFrom-TeamToml -Text $t
        $d.check.Count | Should Be 2
        $d.check[1].name | Should Be 'b'
        $d.check[1].expect_exit | Should Be 1
    }
    It 'respeta escapes en textos con comillas dobles' {
        $d = ConvertFrom-TeamToml -Text 'p = "C:\\dir \"x\""'
        $d.p | Should BeExactly 'C:\dir "x"'
    }
    It 'acepta rutas Windows en comillas simples sin escapar' {
        $d = ConvertFrom-TeamToml -Text "p = 'C:\Users\a b'"
        $d.p | Should BeExactly 'C:\Users\a b'
    }
    It 'un arreglo de un elemento sigue siendo arreglo' {
        $d = ConvertFrom-TeamToml -Text 'x = ["solo"]'
        ($d.x -is [array]) | Should Be $true
        $d.x.Count | Should Be 1
    }
    It 'acepta texto vacio' {
        (ConvertFrom-TeamToml -Text '').Count | Should Be 0
    }
    It 'falla con numero de linea ante una tabla inline' {
        { ConvertFrom-TeamToml -Text "[a]`nx = { y = 1 }" } | Should Throw 'linea 2'
    }
    It 'falla con numero de linea ante texto multilinea' {
        { ConvertFrom-TeamToml -Text 'x = """' } | Should Throw 'linea 1'
    }
    It 'falla ante una linea que no es clave, tabla ni comentario' {
        { ConvertFrom-TeamToml -Text "ok = 1`nesto no vale" } | Should Throw 'linea 2'
    }
}

Describe 'ConvertTo-TeamToml' {
    It 'ida y vuelta conserva tablas, tablas anidadas, arreglos de tablas y textos raros' {
        $data = [ordered]@{
            tags  = @('a', 'b')
            project = [ordered]@{ name = 'demo'; path = 'C:\Mi "Proyecto"' }
            roles = [ordered]@{ planner = [ordered]@{ agent_name = 'kimi'; last_session_id = '' } }
            check = @([ordered]@{ name = 'tests'; run = 'pnpm test'; expect_exit = 0 })
        }
        $back = ConvertFrom-TeamToml -Text (ConvertTo-TeamToml -Data $data)
        $back.tags[1] | Should Be 'b'
        $back.project.path | Should BeExactly 'C:\Mi "Proyecto"'
        $back.roles.planner.agent_name | Should Be 'kimi'
        $back.roles.planner.last_session_id | Should BeExactly ''
        $back.check[0].run | Should Be 'pnpm test'
        $back.check[0].expect_exit | Should Be 0
    }
}
```

- [ ] **Step 3: Correr los tests y verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Script tests\Common.Tests.ps1, tests\Toml.Tests.ps1"`
Expected: FAIL (`The term 'Write-TeamFile' is not recognized ...`).

- [ ] **Step 4: Implementar `lib/Common.ps1`**

```powershell
function Resolve-TeamPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).ProviderPath $Path))
}

function Write-TeamFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )
    $full = Resolve-TeamPath $Path
    $dir = Split-Path -Parent $full
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($full, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Read-TeamFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = Resolve-TeamPath $Path
    if (-not (Test-Path -LiteralPath $full)) { throw "No existe el archivo: $full" }
    return [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)
}

function Find-TeamProjectRoot {
    param([string]$StartPath = (Get-Location).ProviderPath)
    $dir = Resolve-TeamPath $StartPath
    while ($dir) {
        if (Test-Path -LiteralPath (Join-Path $dir '.team\team.toml')) { return $dir }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    throw "No se encontro un proyecto con .team\team.toml desde: $StartPath"
}
```

- [ ] **Step 5: Implementar `lib/Toml.ps1`**

```powershell
function ConvertFrom-TomlValue {
    param([string]$Raw, [int]$Line)
    $v = $Raw.Trim()
    $dq = '"((?:[^"\\]|\\.)*)"'
    $sq = "'([^']*)'"
    if ($v -match ('^' + $dq + '\s*(#.*)?$')) { return [regex]::Replace($matches[1], '\\(["\\])', '$1') }
    if ($v -match ('^' + $sq + '\s*(#.*)?$')) { return $matches[1] }
    if ($v -match '^(true|false)\s*(#.*)?$') { return ($matches[1] -eq 'true') }
    if ($v -match '^(-?\d+)\s*(#.*)?$') { return [int]$matches[1] }
    if ($v -match '^\[(.*)\]\s*(#.*)?$') {
        $inner = $matches[1]
        $itemPattern = $dq + '|' + $sq
        $items = New-Object System.Collections.ArrayList
        foreach ($m in [regex]::Matches($inner, $itemPattern)) {
            if ($m.Groups[1].Success) { [void]$items.Add([regex]::Replace($m.Groups[1].Value, '\\(["\\])', '$1')) }
            else { [void]$items.Add($m.Groups[2].Value) }
        }
        $leftover = ([regex]::Replace($inner, $itemPattern, '')) -replace '[,\s]', ''
        if ($leftover) { throw "TOML linea ${Line}: arreglo no soportado (solo textos entre comillas): $Raw" }
        return ,([object[]]$items.ToArray())
    }
    throw "TOML linea ${Line}: valor no soportado: $Raw"
}

function Get-TomlTable {
    param($Root, [string]$Name)
    $node = $Root
    foreach ($part in $Name.Split('.')) {
        if (-not $node.Contains($part)) { $node[$part] = [ordered]@{} }
        $node = $node[$part]
        if ($node -is [System.Collections.IList]) { $node = $node[$node.Count - 1] }
        if (-not ($node -is [System.Collections.IDictionary])) { throw "TOML: la tabla '$Name' choca con un valor existente" }
    }
    return $node
}

function ConvertFrom-TeamToml {
    param([AllowEmptyString()][AllowNull()][string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $root = [ordered]@{}
    $current = $root
    $n = 0
    foreach ($raw in ($Text -split "`r?`n")) {
        $n++
        $line = $raw.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        if ($line -match '^\[\[([A-Za-z0-9_-]+)\]\]\s*(#.*)?$') {
            $name = $matches[1]
            if (-not $root.Contains($name)) { $root[$name] = New-Object System.Collections.ArrayList }
            $table = [ordered]@{}
            [void]$root[$name].Add($table)
            $current = $table
            continue
        }
        if ($line -match '^\[([A-Za-z0-9_.-]+)\]\s*(#.*)?$') {
            $current = Get-TomlTable -Root $root -Name $matches[1]
            continue
        }
        if ($line -match '^([A-Za-z0-9_-]+)\s*=\s*(.+)$') {
            $key = $matches[1]
            $value = $matches[2]
            $current[$key] = ConvertFrom-TomlValue -Raw $value -Line $n
            continue
        }
        throw "TOML linea ${n}: formato no soportado: $raw"
    }
    return $root
}

function ConvertTo-TomlString {
    param([AllowEmptyString()][string]$Value)
    return '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"'
}

function ConvertTo-TomlValue {
    param($Value)
    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
    if ($Value -is [int] -or $Value -is [long]) { return [string]$Value }
    if ($Value -is [System.Collections.IList]) {
        $parts = @(foreach ($item in $Value) { ConvertTo-TomlString ([string]$item) })
        return '[' + ($parts -join ', ') + ']'
    }
    return ConvertTo-TomlString ([string]$Value)
}

function Test-TomlTableArray {
    param($Value)
    return (($Value -is [System.Collections.IList]) -and ($Value.Count -gt 0) -and ($Value[0] -is [System.Collections.IDictionary]))
}

function Add-TomlTableText {
    param([System.Text.StringBuilder]$Builder, [System.Collections.IDictionary]$Table, [string]$Prefix)
    foreach ($k in @($Table.Keys)) {
        $v = $Table[$k]
        if (-not ($v -is [System.Collections.IDictionary]) -and -not (Test-TomlTableArray $v)) {
            [void]$Builder.AppendLine("$k = " + (ConvertTo-TomlValue $v))
        }
    }
    foreach ($k in @($Table.Keys)) {
        $v = $Table[$k]
        if ($Prefix) { $name = "$Prefix.$k" } else { $name = [string]$k }
        if ($v -is [System.Collections.IDictionary]) {
            [void]$Builder.AppendLine('')
            [void]$Builder.AppendLine("[$name]")
            Add-TomlTableText -Builder $Builder -Table $v -Prefix $name
        } elseif (Test-TomlTableArray $v) {
            foreach ($item in $v) {
                [void]$Builder.AppendLine('')
                [void]$Builder.AppendLine("[[$name]]")
                Add-TomlTableText -Builder $Builder -Table $item -Prefix $name
            }
        }
    }
}

function ConvertTo-TeamToml {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Data)
    $sb = New-Object System.Text.StringBuilder
    Add-TomlTableText -Builder $sb -Table $Data -Prefix ''
    return $sb.ToString().TrimStart()
}

function Read-TeamConfig {
    param([Parameter(Mandatory = $true)][string]$Path)
    return ConvertFrom-TeamToml -Text (Read-TeamFile $Path)
}

function Write-TeamConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Data
    )
    Write-TeamFile -Path $Path -Content (ConvertTo-TeamToml -Data $Data)
}
```

- [ ] **Step 6: Correr los tests y verificar que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run.ps1`
Expected: PASS, `Failed: 0`.

- [ ] **Step 7: Commit**

```bash
git add lib tests
git -c user.name="jcgmU" -c user.email="jcgm1047@gmail.com" commit -m "feat: add module loader, file IO and TOML subset" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Estado del proyecto (`brain/Estado/STATE.md`)

**Files:**
- Create: `templates/STATE.md`, `lib/State.ps1`, `tests/State.Tests.ps1`

**Interfaces:**
- Consumes: `Read-TeamFile`, `Write-TeamFile`, `Resolve-TeamPath` (Task 1).
- Produces:
  - `Read-TeamState -ProjectPath <string>` → `[ordered]` con claves `fase, ronda, turno, siguiente, engram_pendiente, actualizado` (valores string). Lanza `... no tiene el bloque ...` si faltan marcadores.
  - `Update-TeamState -ProjectPath <string> [-Phase] [-Round] [-Turn] [-Next] [-EngramPending] [-EngramSaved]` → `[ordered]` estado nuevo; siempre actualiza `actualizado` (`yyyy-MM-dd HH:mm`).

- [ ] **Step 1: Crear la plantilla `templates/STATE.md`**

```markdown
# Estado del proyecto {{PROJECT}}

> El bloque entre marcadores lo mantienen `team.ps1 state` y `team.ps1 checkpoint`. No lo edites a mano; escribe tus notas debajo.

<!-- team-state:begin -->
- **fase**: inicio
- **ronda**: 0
- **turno**: orquestador
- **siguiente**: Completar team-bootstrap
- **engram_pendiente**: no
- **actualizado**: {{DATE}}
<!-- team-state:end -->

## Notas
```

- [ ] **Step 2: Escribir el test que falla** — `tests/State.Tests.ps1`

```powershell
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here '..\lib\TeamKit.psm1') -Force

function New-StateProject {
    $p = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    $tpl = Read-TeamFile (Join-Path $here '..\templates\STATE.md')
    Write-TeamFile -Path (Join-Path $p 'brain\Estado\STATE.md') -Content ($tpl.Replace('{{PROJECT}}', 'demo').Replace('{{DATE}}', '2026-10-11'))
    return $p
}

Describe 'Read-TeamState / Update-TeamState' {
    It 'lee el estado inicial' {
        $s = Read-TeamState -ProjectPath (New-StateProject)
        $s.fase | Should Be 'inicio'
        $s.ronda | Should Be '0'
        $s.turno | Should Be 'orquestador'
    }
    It 'actualiza solo los campos dados y conserva el resto del archivo' {
        $p = New-StateProject
        $f = Join-Path $p 'brain\Estado\STATE.md'
        Write-TeamFile -Path $f -Content ((Read-TeamFile $f) + "`nnota del usuario`n")
        Update-TeamState -ProjectPath $p -Phase 'plan' -Turn 'kimi' | Out-Null
        $s = Read-TeamState -ProjectPath $p
        $s.fase | Should Be 'plan'
        $s.turno | Should Be 'kimi'
        $s.ronda | Should Be '0'
        $s.actualizado | Should Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$'
        (Read-TeamFile $f) | Should Match 'nota del usuario'
    }
    It 'marca y desmarca engram pendiente' {
        $p = New-StateProject
        (Update-TeamState -ProjectPath $p -EngramPending).engram_pendiente | Should Be 'si'
        (Update-TeamState -ProjectPath $p -EngramSaved).engram_pendiente | Should Be 'no'
    }
    It 'aplana saltos de linea en siguiente' {
        $p = New-StateProject
        (Update-TeamState -ProjectPath $p -Next "uno`r`ndos").siguiente | Should Be 'uno dos'
    }
    It 'falla si STATE.md no tiene el bloque' {
        $p = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Write-TeamFile -Path (Join-Path $p 'brain\Estado\STATE.md') -Content 'sin bloque'
        { Read-TeamState -ProjectPath $p } | Should Throw 'bloque'
    }
}
```

- [ ] **Step 3: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Script tests\State.Tests.ps1"`
Expected: FAIL (`Read-TeamState` no reconocido).

- [ ] **Step 4: Implementar `lib/State.ps1`**

```powershell
$script:StateBegin = '<!-- team-state:begin -->'
$script:StateEnd = '<!-- team-state:end -->'
$script:StateKeys = @('fase', 'ronda', 'turno', 'siguiente', 'engram_pendiente', 'actualizado')

function Get-TeamStatePath {
    param([Parameter(Mandatory = $true)][string]$ProjectPath)
    return Join-Path (Resolve-TeamPath $ProjectPath) 'brain\Estado\STATE.md'
}

function Read-TeamState {
    param([Parameter(Mandatory = $true)][string]$ProjectPath)
    $text = Read-TeamFile (Get-TeamStatePath $ProjectPath)
    $i = $text.IndexOf($script:StateBegin)
    $j = $text.IndexOf($script:StateEnd)
    if ($i -lt 0 -or $j -lt $i) { throw 'STATE.md no tiene el bloque <!-- team-state:begin/end -->' }
    $state = [ordered]@{}
    foreach ($k in $script:StateKeys) { $state[$k] = '' }
    foreach ($line in ($text.Substring($i, $j - $i) -split "`r?`n")) {
        if ($line -match '^-\s*\*\*([a-z_]+)\*\*:\s*(.*)$') { $state[$matches[1]] = $matches[2].Trim() }
    }
    return $state
}

function Update-TeamState {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [string]$Phase, [string]$Round, [string]$Turn, [string]$Next,
        [switch]$EngramPending, [switch]$EngramSaved
    )
    $path = Get-TeamStatePath $ProjectPath
    $state = Read-TeamState -ProjectPath $ProjectPath
    if ($PSBoundParameters.ContainsKey('Phase')) { $state['fase'] = $Phase }
    if ($PSBoundParameters.ContainsKey('Round')) { $state['ronda'] = $Round }
    if ($PSBoundParameters.ContainsKey('Turn')) { $state['turno'] = $Turn }
    if ($PSBoundParameters.ContainsKey('Next')) { $state['siguiente'] = ($Next -replace '\r?\n', ' ') }
    if ($EngramPending) { $state['engram_pendiente'] = 'si' }
    if ($EngramSaved) { $state['engram_pendiente'] = 'no' }
    $state['actualizado'] = Get-Date -Format 'yyyy-MM-dd HH:mm'
    $lines = @(foreach ($k in $script:StateKeys) { "- **$k**: $($state[$k])" })
    $text = Read-TeamFile $path
    $i = $text.IndexOf($script:StateBegin)
    $j = $text.IndexOf($script:StateEnd)
    $new = $text.Substring(0, $i) + $script:StateBegin + "`n" + ($lines -join "`n") + "`n" + $text.Substring($j)
    Write-TeamFile -Path $path -Content $new
    return $state
}
```

- [ ] **Step 5: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run.ps1`
Expected: PASS, `Failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add lib/State.ps1 templates/STATE.md tests/State.Tests.ps1
git -c user.name="jcgmU" -c user.email="jcgm1047@gmail.com" commit -m "feat: add project state block read/update" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Plantillas y andamiaje del proyecto

**Files:**
- Create: `templates/00-Inicio.md`, `templates/Protocolo.md`, `templates/Comandos.md`, `templates/ficha-plantilla.md`, `templates/pointer-block.md`, `templates/central-index.md`, `templates/verify.toml`
- Create: `lib/Scaffold.ps1`, `tests/Scaffold.Tests.ps1`

**Interfaces:**
- Consumes: Task 1 (`Write-TeamFile`, `Read-TeamFile`, `Resolve-TeamPath`, `Read-TeamConfig`, `Write-TeamConfig`), Task 2 (`Update-TeamState`).
- Produces:
  - Objeto agente usado en todo el kit: `[pscustomobject]@{ Name; Kind; Version; SessionId }` (Task 4 agrega `PaneId, Status, Cwd, IsSelf`).
  - `Expand-TeamTemplate -Text <string> -Values <hashtable>` → `[string]`; lanza `Placeholder sin valor: {{X}}`.
  - `Initialize-TeamBrain -ProjectPath -ProjectName` → `[string]` ruta de `brain`; lanza `... usa team-resume` si `brain` existe.
  - `Write-TeamDocs -ProjectPath -Config <ordered>` → regenera `Protocolo.md`, `Comandos.md` y bloques puntero.
  - `Complete-TeamBootstrap -ProjectPath -ProjectName -Orchestrator <agente> -Planner <agente> -Executor <agente> [-CentralIndexDir]` → `[pscustomobject]@{ TeamConfig; CentralIndex }`.
  - `Add-TeamPointerBlock -Path -Block` → `'created' | 'appended' | 'updated'`.
  - `New-TeamCentralIndex -ProjectPath -ProjectName -CentralIndexDir` → `[string]` ruta de la nota.
  - `Set-TeamRole -ProjectPath -Role planner|executor -Agent <agente>` → `[ordered]` config.
  - `Get-TeamKitSetting -Key [-ConfigPath]` → `[string]` (vacío si no existe).
  - `team.toml`: `[project] name, engram_project, created` · `[orchestrator] agent_name, kind, version` · `[roles.planner]`/`[roles.executor] agent_name, kind, version, last_session_id`.

- [ ] **Step 1: Crear las plantillas**

`templates/00-Inicio.md`:
```markdown
# {{PROJECT}}

Creado el {{DATE}} con agent-team-kit.

## Mapa
- [[Equipo/Protocolo]] — cómo trabajamos y quién hace qué
- [[Equipo/Comandos]] — qué puede pedirle cada rol a quién
- [[Estado/STATE]] — dónde quedamos
- `Equipo/Fichas/` — capacidades de cada agente
- `Handoffs/` — traspasos de trabajo (fuente de verdad del ciclo)
- `Decisiones/` — ADRs
- `Verificaciones/` — resultados de verificación
```

`templates/Protocolo.md`:
````markdown
# Protocolo del equipo — {{PROJECT}}

> Generado por agent-team-kit el {{DATE}}. Es la fuente de verdad del flujo de trabajo: todo agente lo lee al empezar cada sesión.

## Roles

| Rol | Agente (nombre en Herdr) | Tipo |
|---|---|---|
| Orquestador | {{ORCHESTRATOR}} | claude |
| Planificador | {{PLANNER}} | {{PLANNER_KIND}} |
| Ejecutor | {{EXECUTOR}} | {{EXECUTOR_KIND}} |

- **Orquestador:** recibe los objetivos del usuario, coordina, verifica de verdad y reporta al usuario. **No corrige código:** devuelve hallazgos al planificador.
- **Planificador:** convierte objetivos en planes con criterios de aceptación verificables, revisa de verdad el trabajo del ejecutor antes de pasarlo a verificación y mantiene `.team/verify.toml`.
- **Ejecutor:** implementa exactamente el plan (con TDD cuando aplique) y reporta qué hizo y cómo verificarlo.

## Ciclo

```
usuario ─► orquestador ──objetivo──► planificador ──plan──► ejecutor
                ▲                        ▲    │                 │
                │                        │    └◄──ejecucion─────┘
                │      hallazgos         │
                ├────────────────────────┘
                │◄──listo-para-verificar── planificador
                └──aprobado / bloqueo──► usuario
```

1. El orquestador abre un hilo con un handoff `objetivo` al planificador.
2. El planificador envía `plan` al ejecutor.
3. El ejecutor implementa y envía `ejecucion` al planificador.
4. El planificador revisa de verdad (corre tests y build, lee el diff). Si no cumple: nuevo `plan` (ronda + 1). Si cumple: `listo-para-verificar` al orquestador.
5. El orquestador corre `team-verify` y los chequeos manuales. Si falla: `hallazgos` al planificador. Si pasa: `aprobado` al usuario y reporte.
6. **Circuit breaker:** 3 `hallazgos` en el mismo hilo generan un `bloqueo` para el usuario y el hilo se pausa.

## Reglas

- Todo traspaso de trabajo es un archivo en `brain/Handoffs/` creado con `team-handoff`. Nada se pasa solo por texto en la terminal.
- Al recibir un handoff: léelo completo, trabájalo, márcalo `hecho` y responde con tu propio handoff.
- Nadie da por bueno el reporte de otro agente sin comprobarlo.
- Antes de cerrar sesión: `team-checkpoint`.
- Memoria engram: usa siempre el proyecto `{{ENGRAM_PROJECT}}`.
- Decisiones importantes: un ADR en `brain/Decisiones/`.
- **Proyecto sin stack definido:** el primer hilo es `stack`. El planificador propone 3 opciones reales por capa (frontend, backend, base de datos, colas, despliegue, IA); el orquestador las presenta al usuario y nadie escribe código hasta que el usuario confirma. El stack elegido queda en un ADR.
- Si un agente queda esperando una aprobación o una pregunta (`blocked`), solo el usuario la responde.
- Para pedirle a otro agente que use sus subagentes o su modo multi-agente, consulta su ficha y nombra la capacidad exacta en el handoff.
````

`templates/Comandos.md`:
````markdown
# Comandos del equipo — {{PROJECT}}

## Qué puede pedirle cada rol a quién (tipos de handoff)

| De \ Para | Planificador ({{PLANNER}}) | Ejecutor ({{EXECUTOR}}) | Orquestador ({{ORCHESTRATOR}}) | Usuario |
|---|---|---|---|---|
| Planificador | — | `plan` | `listo-para-verificar` | `bloqueo` |
| Ejecutor | `ejecucion` | — | — | — |
| Orquestador | `objetivo`, `hallazgos` | — | — | `aprobado`, `bloqueo` |

## Skills compartidos

| Skill | Para qué | Quién |
|---|---|---|
| `team-handoff` | crear y entregar un handoff | todos |
| `team-verify` | correr los chequeos de `.team/verify.toml` | orquestador (el planificador mantiene el archivo) |
| `team-checkpoint` | guardar estado y resumen en engram | todos, antes de cerrar |
| `team-doctor` | revisar la salud del equipo | todos |
| `team-resume` | retomar el proyecto en una sesión nueva | orquestador |

Si tu agente no puede invocar skills por nombre, usa el CLI directamente:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.agents\team-kit\team.ps1" <comando> --project "<ruta del proyecto>" ...
```

## Capacidades de cada agente

Ver `Fichas/{{ORCHESTRATOR}}.md`, `Fichas/{{PLANNER}}.md` y `Fichas/{{EXECUTOR}}.md`. Para pedir subagentes o un modo multi-agente, cita en el handoff la capacidad exacta tal como aparece en la ficha del destinatario.
````

`templates/ficha-plantilla.md`:
```markdown
---
agente: <nombre en Herdr>
tipo: <tipo de agente en Herdr>
version: <versión del CLI>
modelo: <modelo que usas>
estado: completa
---

# Ficha de capacidades — <nombre>

## Herramientas propias
<leer y escribir archivos, terminal, navegador, búsqueda web, etc.>

## Subagentes y modo multi-agente
<qué tienes, cómo se invoca exactamente y cuándo conviene pedírtelo>

## Comandos `/`
<comandos slash disponibles y para qué sirven>

## Skills
<skills disponibles y carpeta donde viven>

## Plugins y MCP
<servidores MCP y plugins conectados; di explícitamente si tienes engram>

## Límites
<qué no puedes hacer o haces mal>

## Cómo prefiero recibir trabajo
<qué formato de handoff te funciona mejor>

## Verificación del orquestador

| Dato | Declarado | Verificado (✅ / ⚠ / ❌) |
|---|---|---|
| Versión | | |
| Detección en Herdr | | |
| Engram | | |
| Rutas de skills | | |
```

`templates/pointer-block.md`:
```markdown
<!-- team:begin -->
## Equipo de agentes (agent-team-kit)

Este proyecto lo trabaja un equipo de agentes coordinado por Herdr. Antes de hacer cualquier cosa:

1. Lee `brain/Equipo/Protocolo.md`: reglas del ciclo y tu rol.
2. Lee las fichas en `brain/Equipo/Fichas/` para saber qué puede hacer cada agente.
3. Lee `brain/Estado/STATE.md` y tus handoffs abiertos en `brain/Handoffs/`.

Memoria engram: usa siempre el proyecto `{{ENGRAM_PROJECT}}`.
<!-- team:end -->
```

`templates/central-index.md`:
```markdown
# PRJ {{PROJECT}}

- **Creado:** {{DATE}}
- **Carpeta:** `{{PROJECT_PATH}}`
- **Vault del proyecto:** [Abrir 00-Inicio]({{OBSIDIAN_URI}})
- **Memoria engram:** proyecto `{{PROJECT}}`

## Notas
```

`templates/verify.toml`:
```toml
# Chequeos que corre team-verify. Lo mantiene el planificador cuando el stack está decidido.
#
# Formato soportado (subconjunto de TOML):
#   - solo bloques [[check]]
#   - claves: name, run, expect_exit, expect_output, manual
#   - textos entre comillas dobles ("...") o simples ('...'); para rutas Windows usa comillas simples
#   - sin tablas inline { } ni textos multilínea
#
# Ejemplos:
#
# [[check]]
# name = "tests"
# run = "pnpm -r test"            # se ejecuta en PowerShell desde la raíz del proyecto
# expect_exit = 0                 # opcional (por defecto 0)
# expect_output = "passed"        # opcional: texto que debe aparecer en la salida
#
# [[check]]
# name = "UI real en el navegador"
# manual = "Abrir /login, registrar un usuario y confirmar que entra al panel"
```

- [ ] **Step 2: Escribir el test que falla** — `tests/Scaffold.Tests.ps1`

```powershell
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here '..\lib\TeamKit.psm1') -Force

function New-Agent([string]$Name, [string]$Kind) {
    return [pscustomobject]@{ Name = $Name; Kind = $Kind; Version = '1.0.0'; SessionId = "$Name-s1" }
}
function New-EmptyProject([string]$Leaf = '') {
    if (-not $Leaf) { $Leaf = [guid]::NewGuid().ToString() }
    $p = Join-Path $TestDrive $Leaf
    New-Item -ItemType Directory -Force -Path $p | Out-Null
    return $p
}
function New-BootstrappedProject {
    $p = New-EmptyProject
    Initialize-TeamBrain -ProjectPath $p -ProjectName 'demo' | Out-Null
    Complete-TeamBootstrap -ProjectPath $p -ProjectName 'demo' -Orchestrator (New-Agent 'claude' 'claude') -Planner (New-Agent 'kimi' 'kimi') -Executor (New-Agent 'agy' 'agy') | Out-Null
    return $p
}

Describe 'Expand-TeamTemplate' {
    It 'reemplaza placeholders' {
        Expand-TeamTemplate -Text 'hola {{A}}' -Values @{ A = 'mundo' } | Should Be 'hola mundo'
    }
    It 'falla si queda un placeholder sin valor' {
        { Expand-TeamTemplate -Text '{{A}} {{B}}' -Values @{ A = 'x' } } | Should Throw 'Placeholder sin valor: {{B}}'
    }
}

Describe 'Initialize-TeamBrain' {
    It 'crea el vault y .team en una ruta con espacios' {
        $p = New-EmptyProject 'Mi Proyecto'
        $brain = Initialize-TeamBrain -ProjectPath $p -ProjectName 'demo'
        foreach ($rel in @('00-Inicio.md', 'Estado\STATE.md', 'Equipo\Fichas\_plantilla-ficha.md', 'Handoffs', 'Decisiones', 'Verificaciones')) {
            Join-Path $brain $rel | Should Exist
        }
        Join-Path $p '.team\verify.toml' | Should Exist
        (Read-TeamFile (Join-Path $brain '00-Inicio.md')) | Should Not Match '\{\{'
        (Read-TeamState -ProjectPath $p).fase | Should Be 'inicio'
    }
    It 'se niega si brain ya existe' {
        $p = New-EmptyProject
        Initialize-TeamBrain -ProjectPath $p -ProjectName 'demo' | Out-Null
        { Initialize-TeamBrain -ProjectPath $p -ProjectName 'demo' } | Should Throw 'team-resume'
    }
    It 'rechaza nombres de proyecto invalidos' {
        { Initialize-TeamBrain -ProjectPath (New-EmptyProject) -ProjectName 'Mi Proyecto' } | Should Throw 'invalido'
    }
}

Describe 'Add-TeamPointerBlock' {
    $block = "<!-- team:begin -->`nlee el protocolo`n<!-- team:end -->"
    It 'crea, agrega al final conservando el contenido y actualiza sin duplicar' {
        $p = New-EmptyProject
        $f = Join-Path $p 'CLAUDE.md'
        Add-TeamPointerBlock -Path $f -Block $block | Should Be 'created'
        $g = Join-Path $p 'AGENTS.md'
        Write-TeamFile -Path $g -Content "# Mis reglas`nno borrar`n"
        Add-TeamPointerBlock -Path $g -Block $block | Should Be 'appended'
        Add-TeamPointerBlock -Path $g -Block ($block.Replace('lee el protocolo', 'version 2')) | Should Be 'updated'
        $text = Read-TeamFile $g
        $text | Should Match 'no borrar'
        $text | Should Match 'version 2'
        ([regex]::Matches($text, 'team:begin')).Count | Should Be 1
    }
    It 'rechaza un bloque sin marcadores' {
        { Add-TeamPointerBlock -Path (Join-Path (New-EmptyProject) 'X.md') -Block 'sin marcas' } | Should Throw 'marcadores'
    }
}

Describe 'Complete-TeamBootstrap' {
    It 'escribe team.toml, documentos, punteros y estado' {
        $p = New-BootstrappedProject
        $cfg = Read-TeamConfig -Path (Join-Path $p '.team\team.toml')
        $cfg.project.engram_project | Should Be 'demo'
        $cfg.orchestrator.agent_name | Should Be 'claude'
        $cfg.roles.planner.agent_name | Should Be 'kimi'
        $cfg.roles.executor.kind | Should Be 'agy'
        $cfg.roles.planner.last_session_id | Should Be 'kimi-s1'
        (Read-TeamFile (Join-Path $p 'brain\Equipo\Protocolo.md')) | Should Match '\| Planificador \| kimi \| kimi \|'
        (Read-TeamFile (Join-Path $p 'brain\Equipo\Comandos.md')) | Should Match 'Ejecutor \(agy\)'
        foreach ($f in 'CLAUDE.md', 'AGENTS.md', 'GEMINI.md') { (Read-TeamFile (Join-Path $p $f)) | Should Match 'proyecto `demo`' }
        $s = Read-TeamState -ProjectPath $p
        $s.fase | Should Be 'equipo-listo'
        $s.turno | Should Be 'claude'
    }
    It 'conserva el CLAUDE.md del usuario y no duplica el bloque al regenerar' {
        $p = New-EmptyProject
        Write-TeamFile -Path (Join-Path $p 'CLAUDE.md') -Content "# Reglas del usuario`n"
        Initialize-TeamBrain -ProjectPath $p -ProjectName 'demo' | Out-Null
        Complete-TeamBootstrap -ProjectPath $p -ProjectName 'demo' -Orchestrator (New-Agent 'claude' 'claude') -Planner (New-Agent 'kimi' 'kimi') -Executor (New-Agent 'agy' 'agy') | Out-Null
        Write-TeamDocs -ProjectPath $p -Config (Read-TeamConfig -Path (Join-Path $p '.team\team.toml'))
        $text = Read-TeamFile (Join-Path $p 'CLAUDE.md')
        $text | Should Match 'Reglas del usuario'
        ([regex]::Matches($text, 'team:begin')).Count | Should Be 1
    }
    It 'rechaza el mismo agente como planificador y ejecutor' {
        $p = New-EmptyProject
        Initialize-TeamBrain -ProjectPath $p -ProjectName 'demo' | Out-Null
        { Complete-TeamBootstrap -ProjectPath $p -ProjectName 'demo' -Orchestrator (New-Agent 'claude' 'claude') -Planner (New-Agent 'kimi' 'kimi') -Executor (New-Agent 'kimi' 'kimi') } | Should Throw 'distintos'
    }
    It 'crea el indice central una sola vez' {
        $p = New-EmptyProject
        $central = New-EmptyProject
        Initialize-TeamBrain -ProjectPath $p -ProjectName 'demo' | Out-Null
        $r = Complete-TeamBootstrap -ProjectPath $p -ProjectName 'demo' -Orchestrator (New-Agent 'claude' 'claude') -Planner (New-Agent 'kimi' 'kimi') -Executor (New-Agent 'agy' 'agy') -CentralIndexDir $central
        $r.CentralIndex | Should Be (Join-Path $central 'PRJ-demo.md')
        (Read-TeamFile $r.CentralIndex) | Should Match 'obsidian://open\?path='
        Write-TeamFile -Path $r.CentralIndex -Content 'editado por el usuario'
        New-TeamCentralIndex -ProjectPath $p -ProjectName 'demo' -CentralIndexDir $central | Out-Null
        Read-TeamFile $r.CentralIndex | Should Be 'editado por el usuario'
    }
}

Describe 'Set-TeamRole' {
    It 'reasigna el ejecutor y regenera el protocolo' {
        $p = New-BootstrappedProject
        Set-TeamRole -ProjectPath $p -Role executor -Agent (New-Agent 'codex' 'codex') | Out-Null
        $cfg = Read-TeamConfig -Path (Join-Path $p '.team\team.toml')
        $cfg.roles.executor.agent_name | Should Be 'codex'
        $cfg.roles.executor.last_session_id | Should BeExactly ''
        (Read-TeamFile (Join-Path $p 'brain\Equipo\Protocolo.md')) | Should Match '\| Ejecutor \| codex \| codex \|'
    }
    It 'conserva la sesion si el agente es el mismo (actualizacion de version)' {
        $p = New-BootstrappedProject
        $a = New-Agent 'kimi' 'kimi'
        $a.Version = '9.9.9'
        Set-TeamRole -ProjectPath $p -Role planner -Agent $a | Out-Null
        $cfg = Read-TeamConfig -Path (Join-Path $p '.team\team.toml')
        $cfg.roles.planner.version | Should Be '9.9.9'
        $cfg.roles.planner.last_session_id | Should Be 'kimi-s1'
    }
    It 'rechaza asignar al planificador como ejecutor' {
        $p = New-BootstrappedProject
        { Set-TeamRole -ProjectPath $p -Role executor -Agent (New-Agent 'kimi' 'kimi') } | Should Throw 'ya es el planner'
    }
}

Describe 'Get-TeamKitSetting' {
    It 'lee una clave del config.toml y devuelve vacio si no existe' {
        $cfg = Join-Path (New-EmptyProject) 'config.toml'
        Write-TeamFile -Path $cfg -Content "central_index_dir = 'C:\Brain\03-Proyectos'"
        Get-TeamKitSetting -Key 'central_index_dir' -ConfigPath $cfg | Should Be 'C:\Brain\03-Proyectos'
        Get-TeamKitSetting -Key 'otra' -ConfigPath $cfg | Should BeExactly ''
        Get-TeamKitSetting -Key 'x' -ConfigPath (Join-Path $TestDrive 'no-existe.toml') | Should BeExactly ''
    }
}
```

- [ ] **Step 3: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Script tests\Scaffold.Tests.ps1"`
Expected: FAIL (`Expand-TeamTemplate` no reconocido).

- [ ] **Step 4: Implementar `lib/Scaffold.ps1`**

```powershell
$script:TemplateRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'templates'
$script:KitRoot = Split-Path -Parent $PSScriptRoot

function Get-TeamTemplate {
    param([Parameter(Mandatory = $true)][string]$Name)
    return Read-TeamFile (Join-Path $script:TemplateRoot $Name)
}

function Expand-TeamTemplate {
    param([Parameter(Mandatory = $true)][string]$Text, [Parameter(Mandatory = $true)][hashtable]$Values)
    $result = $Text
    foreach ($k in $Values.Keys) { $result = $result.Replace('{{' + $k + '}}', [string]$Values[$k]) }
    if ($result -match '\{\{([A-Z_]+)\}\}') { throw "Placeholder sin valor: {{$($matches[1])}}" }
    return $result
}

function Initialize-TeamBrain {
    param([Parameter(Mandatory = $true)][string]$ProjectPath, [Parameter(Mandatory = $true)][string]$ProjectName)
    if ($ProjectName -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') { throw "Nombre de proyecto invalido '$ProjectName' (minusculas, numeros y guiones)" }
    $root = Resolve-TeamPath $ProjectPath
    $brain = Join-Path $root 'brain'
    if (Test-Path -LiteralPath $brain) { throw "Ya existe $brain. Este proyecto ya tiene equipo: usa team-resume." }
    $values = @{ PROJECT = $ProjectName; DATE = (Get-Date -Format 'yyyy-MM-dd') }
    foreach ($d in @('Equipo\Fichas', 'Estado', 'Handoffs', 'Decisiones', 'Verificaciones')) {
        New-Item -ItemType Directory -Path (Join-Path $brain $d) -Force | Out-Null
    }
    Write-TeamFile -Path (Join-Path $brain '00-Inicio.md') -Content (Expand-TeamTemplate (Get-TeamTemplate '00-Inicio.md') $values)
    Write-TeamFile -Path (Join-Path $brain 'Equipo\Fichas\_plantilla-ficha.md') -Content (Get-TeamTemplate 'ficha-plantilla.md')
    Write-TeamFile -Path (Join-Path $brain 'Estado\STATE.md') -Content (Expand-TeamTemplate (Get-TeamTemplate 'STATE.md') $values)
    $verify = Join-Path $root '.team\verify.toml'
    if (-not (Test-Path -LiteralPath $verify)) { Write-TeamFile -Path $verify -Content (Get-TeamTemplate 'verify.toml') }
    return $brain
}

function Add-TeamPointerBlock {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Block)
    $begin = '<!-- team:begin -->'
    $end = '<!-- team:end -->'
    $b = $Block.Trim()
    if (-not $b.StartsWith($begin) -or -not $b.EndsWith($end)) { throw 'El bloque debe ir entre los marcadores team:begin y team:end' }
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-TeamFile -Path $Path -Content ($b + "`n")
        return 'created'
    }
    $text = Read-TeamFile $Path
    $i = $text.IndexOf($begin)
    $j = -1
    if ($i -ge 0) { $j = $text.IndexOf($end, $i) }
    if ($i -ge 0 -and $j -gt $i) {
        Write-TeamFile -Path $Path -Content ($text.Substring(0, $i) + $b + $text.Substring($j + $end.Length))
        return 'updated'
    }
    Write-TeamFile -Path $Path -Content ($text.TrimEnd() + "`n`n" + $b + "`n")
    return 'appended'
}

function Write-TeamDocs {
    param([Parameter(Mandatory = $true)][string]$ProjectPath, [Parameter(Mandatory = $true)]$Config)
    $root = Resolve-TeamPath $ProjectPath
    $brain = Join-Path $root 'brain'
    $values = @{
        PROJECT        = [string]$Config.project.name
        ENGRAM_PROJECT = [string]$Config.project.engram_project
        DATE           = (Get-Date -Format 'yyyy-MM-dd')
        ORCHESTRATOR   = [string]$Config.orchestrator.agent_name
        PLANNER        = [string]$Config.roles.planner.agent_name
        PLANNER_KIND   = [string]$Config.roles.planner.kind
        EXECUTOR       = [string]$Config.roles.executor.agent_name
        EXECUTOR_KIND  = [string]$Config.roles.executor.kind
    }
    Write-TeamFile -Path (Join-Path $brain 'Equipo\Protocolo.md') -Content (Expand-TeamTemplate (Get-TeamTemplate 'Protocolo.md') $values)
    Write-TeamFile -Path (Join-Path $brain 'Equipo\Comandos.md') -Content (Expand-TeamTemplate (Get-TeamTemplate 'Comandos.md') $values)
    $block = Expand-TeamTemplate (Get-TeamTemplate 'pointer-block.md') $values
    foreach ($f in @('CLAUDE.md', 'AGENTS.md', 'GEMINI.md')) { Add-TeamPointerBlock -Path (Join-Path $root $f) -Block $block | Out-Null }
}

function New-TeamCentralIndex {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][string]$ProjectName,
        [Parameter(Mandatory = $true)][string]$CentralIndexDir
    )
    $dir = Resolve-TeamPath $CentralIndexDir
    if (-not (Test-Path -LiteralPath $dir)) { throw "No existe la carpeta del indice central: $dir" }
    $root = Resolve-TeamPath $ProjectPath
    $path = Join-Path $dir "PRJ-$ProjectName.md"
    if (Test-Path -LiteralPath $path) { return $path }
    $inicio = Join-Path $root 'brain\00-Inicio.md'
    $values = @{
        PROJECT      = $ProjectName
        DATE         = (Get-Date -Format 'yyyy-MM-dd')
        PROJECT_PATH = $root
        OBSIDIAN_URI = ('obsidian://open?path=' + [uri]::EscapeDataString($inicio))
    }
    Write-TeamFile -Path $path -Content (Expand-TeamTemplate (Get-TeamTemplate 'central-index.md') $values)
    return $path
}

function Complete-TeamBootstrap {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][string]$ProjectName,
        [Parameter(Mandatory = $true)]$Orchestrator,
        [Parameter(Mandatory = $true)]$Planner,
        [Parameter(Mandatory = $true)]$Executor,
        [string]$CentralIndexDir
    )
    $root = Resolve-TeamPath $ProjectPath
    if (-not (Test-Path -LiteralPath (Join-Path $root 'brain'))) { throw "Falta brain en $root. Corre primero team.ps1 init." }
    if ($Planner.Name -eq $Executor.Name) { throw 'Planificador y ejecutor deben ser agentes distintos.' }
    if ($Planner.Name -eq $Orchestrator.Name -or $Executor.Name -eq $Orchestrator.Name) { throw 'El orquestador no puede tener otro rol: deben ser agentes distintos.' }
    $config = [ordered]@{
        project      = [ordered]@{ name = $ProjectName; engram_project = $ProjectName; created = (Get-Date -Format 'yyyy-MM-dd') }
        orchestrator = [ordered]@{ agent_name = [string]$Orchestrator.Name; kind = [string]$Orchestrator.Kind; version = [string]$Orchestrator.Version }
        roles        = [ordered]@{
            planner  = [ordered]@{ agent_name = [string]$Planner.Name; kind = [string]$Planner.Kind; version = [string]$Planner.Version; last_session_id = [string]$Planner.SessionId }
            executor = [ordered]@{ agent_name = [string]$Executor.Name; kind = [string]$Executor.Kind; version = [string]$Executor.Version; last_session_id = [string]$Executor.SessionId }
        }
    }
    $teamToml = Join-Path $root '.team\team.toml'
    Write-TeamConfig -Path $teamToml -Data $config
    Write-TeamDocs -ProjectPath $root -Config $config
    Update-TeamState -ProjectPath $root -Phase 'equipo-listo' -Round '0' -Turn ([string]$Orchestrator.Name) -Next 'El orquestador abre el primer hilo con un handoff objetivo (si no hay stack: hilo stack)' | Out-Null
    $index = $null
    if ($CentralIndexDir) { $index = New-TeamCentralIndex -ProjectPath $root -ProjectName $ProjectName -CentralIndexDir $CentralIndexDir }
    return [pscustomobject]@{ TeamConfig = $teamToml; CentralIndex = $index }
}

function Set-TeamRole {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][ValidateSet('planner', 'executor')][string]$Role,
        [Parameter(Mandatory = $true)]$Agent
    )
    $root = Resolve-TeamPath $ProjectPath
    $path = Join-Path $root '.team\team.toml'
    $cfg = Read-TeamConfig -Path $path
    if ($Role -eq 'planner') { $other = 'executor' } else { $other = 'planner' }
    if ([string]$cfg.roles[$other].agent_name -eq [string]$Agent.Name) { throw "$($Agent.Name) ya es el $other" }
    if ([string]$cfg.orchestrator.agent_name -eq [string]$Agent.Name) { throw "$($Agent.Name) ya es el orquestador" }
    $session = ''
    if ([string]$cfg.roles[$Role].agent_name -eq [string]$Agent.Name) { $session = [string]$cfg.roles[$Role].last_session_id }
    $cfg.roles[$Role] = [ordered]@{ agent_name = [string]$Agent.Name; kind = [string]$Agent.Kind; version = [string]$Agent.Version; last_session_id = $session }
    Write-TeamConfig -Path $path -Data $cfg
    Write-TeamDocs -ProjectPath $root -Config $cfg
    return $cfg
}

function Get-TeamKitSetting {
    param([Parameter(Mandatory = $true)][string]$Key, [string]$ConfigPath = (Join-Path $script:KitRoot 'config.toml'))
    if (-not (Test-Path -LiteralPath $ConfigPath)) { return '' }
    $cfg = Read-TeamConfig -Path $ConfigPath
    if ($cfg.Contains($Key)) { return [string]$cfg[$Key] }
    return ''
}
```

- [ ] **Step 5: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run.ps1`
Expected: PASS, `Failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add lib/Scaffold.ps1 templates tests/Scaffold.Tests.ps1
git -c user.name="jcgmU" -c user.email="jcgm1047@gmail.com" commit -m "feat: add vault templates and project scaffolding" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Herdr — llamadas, descubrimiento de agentes, nombres, versiones y checkpoint

**Files:**
- Create: `lib/Herdr.ps1`, `tests/Herdr.Tests.ps1`

**Interfaces:**
- Consumes: Task 1 (`Read-TeamConfig`, `Write-TeamConfig`, `Resolve-TeamPath`), Task 2 (`Update-TeamState`).
- Produces:
  - `Set-TeamHerdrExe -Path <string>` (para tests).
  - `Invoke-Herdr -Arguments <string[]>` → `[pscustomobject]@{ ExitCode; Text; Json }` (`Json` = `$null` si no es JSON).
  - `Get-TeamAgents [-WorkspaceId <string>]` (por defecto `$env:HERDR_WORKSPACE_ID`; vacío = todos) → `[pscustomobject]@{ Agents = @(<agente>); UndetectedPanes = @({ PaneId; Title; Cwd }) }`. Agente: `{ Name; Kind; PaneId; Status; SessionId; Cwd; IsSelf; Version }` (`Version` vacío).
  - `Get-SuggestedAgentName -Kind <string> [-Taken <string[]>]` → `[string]`.
  - `Set-TeamAgentNames -Discovery <obj>` → mismo objeto con `Name` completo (llama `herdr agent rename <pane> <name>`).
  - `Get-AgentVersion -Kind <string>` → `[string]` `x.y.z` o vacío.
  - `Save-TeamCheckpoint -ProjectPath <string>` → `[ordered]` config (actualiza `last_session_id` y `actualizado`).

- [ ] **Step 1: Escribir el test que falla** — `tests/Herdr.Tests.ps1`

```powershell
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here '..\lib\TeamKit.psm1') -Force

Describe 'Invoke-Herdr' {
    AfterEach { Set-TeamHerdrExe -Path 'herdr' }
    It 'devuelve el JSON y el codigo 0' {
        $fake = Join-Path $TestDrive 'ok.cmd'
        Set-Content -LiteralPath $fake -Encoding ASCII -Value @('@echo off', 'echo {"id":"t","result":{"type":"ok"}}', 'exit /b 0')
        Set-TeamHerdrExe -Path $fake
        $r = Invoke-Herdr -Arguments @('agent', 'list')
        $r.ExitCode | Should Be 0
        $r.Json.result.type | Should Be 'ok'
    }
    It 'devuelve el error JSON de stderr y el codigo 1' {
        $fake = Join-Path $TestDrive 'err.cmd'
        Set-Content -LiteralPath $fake -Encoding ASCII -Value @('@echo off', 'echo {"error":{"code":"agent_not_found","message":"x"}} 1>&2', 'exit /b 1')
        Set-TeamHerdrExe -Path $fake
        $r = Invoke-Herdr -Arguments @('agent', 'get', 'nadie')
        $r.ExitCode | Should Be 1
        $r.Json.error.code | Should Be 'agent_not_found'
    }
}

Describe 'Get-TeamAgents' {
    BeforeEach { $env:HERDR_PANE_ID = 'w1:p1' }
    It 'lista los agentes del workspace, marca el propio y separa los panes sin agente' {
        Mock -ModuleName TeamKit Invoke-Herdr {
            $j = '{"result":{"agents":[{"agent":"claude","pane_id":"w1:p1","workspace_id":"w1","agent_status":"working","name":"claude","agent_session":{"value":"c-1"},"cwd":"C:\\p"},{"agent":"kimi","pane_id":"w1:p2","workspace_id":"w1","agent_status":"idle","name":"kimi","agent_session":{"value":"k-1"},"cwd":"C:\\p"},{"agent":"agy","pane_id":"w1:p3","workspace_id":"w1","agent_status":"idle","cwd":"C:\\p"},{"agent":"codex","pane_id":"w2:p1","workspace_id":"w2","agent_status":"idle","name":"codex","cwd":"C:\\q"}]}}'
            [pscustomobject]@{ ExitCode = 0; Text = $j; Json = ($j | ConvertFrom-Json) }
        } -ParameterFilter { $Arguments[0] -eq 'agent' }
        Mock -ModuleName TeamKit Invoke-Herdr {
            $j = '{"result":{"panes":[{"pane_id":"w1:p1","agent":"claude"},{"pane_id":"w1:p2","agent":"kimi"},{"pane_id":"w1:p3","agent":"agy"},{"pane_id":"w1:p4","agent_status":"unknown","terminal_title":"kimi-code","cwd":"C:\\p"}]}}'
            [pscustomobject]@{ ExitCode = 0; Text = $j; Json = ($j | ConvertFrom-Json) }
        } -ParameterFilter { $Arguments[0] -eq 'pane' }
        $d = Get-TeamAgents -WorkspaceId 'w1'
        $d.Agents.Count | Should Be 3
        @($d.Agents | Where-Object { $_.IsSelf })[0].Name | Should Be 'claude'
        @($d.Agents | Where-Object { $_.Kind -eq 'kimi' })[0].SessionId | Should Be 'k-1'
        @($d.Agents | Where-Object { $_.Kind -eq 'agy' })[0].Name | Should BeExactly ''
        $d.UndetectedPanes.Count | Should Be 1
        $d.UndetectedPanes[0].PaneId | Should Be 'w1:p4'
        $d.UndetectedPanes[0].Title | Should Be 'kimi-code'
    }
    It 'falla con el texto de herdr si la llamada falla' {
        Mock -ModuleName TeamKit Invoke-Herdr { [pscustomobject]@{ ExitCode = 1; Text = 'server down'; Json = $null } }
        { Get-TeamAgents -WorkspaceId 'w1' } | Should Throw 'server down'
    }
}

Describe 'Nombres de agentes' {
    It 'sugiere nombres validos y unicos' {
        Get-SuggestedAgentName -Kind 'kimi' -Taken @('kimi') | Should Be 'kimi-2'
        Get-SuggestedAgentName -Kind 'Foo Bar' | Should Be 'foo-bar'
        Get-SuggestedAgentName -Kind '9x' | Should Be 'a9x'
    }
    It 'solo renombra los agentes sin nombre' {
        Mock -ModuleName TeamKit Invoke-Herdr { [pscustomobject]@{ ExitCode = 0; Text = '{}'; Json = $null } }
        $disc = [pscustomobject]@{
            Agents = @(
                [pscustomobject]@{ Name = 'kimi'; Kind = 'kimi'; PaneId = 'w1:p2' },
                [pscustomobject]@{ Name = ''; Kind = 'agy'; PaneId = 'w1:p3' }
            )
            UndetectedPanes = @()
        }
        $out = Set-TeamAgentNames -Discovery $disc
        $out.Agents[1].Name | Should Be 'agy'
        Assert-MockCalled -ModuleName TeamKit Invoke-Herdr -Times 1 -Exactly -ParameterFilter { $Arguments[1] -eq 'rename' -and $Arguments[2] -eq 'w1:p3' -and $Arguments[3] -eq 'agy' }
    }
}

Describe 'Get-AgentVersion' {
    It 'devuelve vacio si el comando no existe' {
        Get-AgentVersion -Kind 'cli-que-no-existe-xyz' | Should BeExactly ''
    }
}

Describe 'Save-TeamCheckpoint' {
    It 'guarda los ids de sesion actuales y la fecha' {
        $p = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Force -Path $p | Out-Null
        Initialize-TeamBrain -ProjectPath $p -ProjectName 'demo' | Out-Null
        $mk = { param($n, $k) [pscustomobject]@{ Name = $n; Kind = $k; Version = '1'; SessionId = 'old' } }
        Complete-TeamBootstrap -ProjectPath $p -ProjectName 'demo' -Orchestrator (& $mk 'claude' 'claude') -Planner (& $mk 'kimi' 'kimi') -Executor (& $mk 'agy' 'agy') | Out-Null
        Mock -ModuleName TeamKit Get-TeamAgents {
            [pscustomobject]@{ Agents = @([pscustomobject]@{ Name = 'kimi'; Kind = 'kimi'; SessionId = 'k-new' }, [pscustomobject]@{ Name = 'agy'; Kind = 'agy'; SessionId = '' }); UndetectedPanes = @() }
        }
        Save-TeamCheckpoint -ProjectPath $p | Out-Null
        $cfg = Read-TeamConfig -Path (Join-Path $p '.team\team.toml')
        $cfg.roles.planner.last_session_id | Should Be 'k-new'
        $cfg.roles.executor.last_session_id | Should Be 'old'
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Script tests\Herdr.Tests.ps1"`
Expected: FAIL (`Set-TeamHerdrExe` no reconocido).

- [ ] **Step 3: Implementar `lib/Herdr.ps1`**

```powershell
$script:HerdrExe = 'herdr'

function Set-TeamHerdrExe {
    param([Parameter(Mandatory = $true)][string]$Path)
    $script:HerdrExe = $Path
}

function Invoke-Herdr {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $script:HerdrExe @Arguments 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prev
    }
    $text = (@($out) | ForEach-Object { "$_" }) -join "`n"
    $json = $null
    if ($text.Trim().StartsWith('{')) {
        try { $json = $text | ConvertFrom-Json } catch { $json = $null }
    }
    return [pscustomobject]@{ ExitCode = $code; Text = $text; Json = $json }
}

function ConvertTo-TeamAgent {
    param($Item)
    $sid = ''
    if ($Item.agent_session -and $Item.agent_session.value) { $sid = [string]$Item.agent_session.value }
    return [pscustomobject]@{
        Name      = [string]$Item.name
        Kind      = [string]$Item.agent
        PaneId    = [string]$Item.pane_id
        Status    = [string]$Item.agent_status
        SessionId = $sid
        Cwd       = [string]$Item.cwd
        IsSelf    = ([string]$Item.pane_id -eq [string]$env:HERDR_PANE_ID)
        Version   = ''
    }
}

function Get-TeamAgents {
    param([string]$WorkspaceId = $env:HERDR_WORKSPACE_ID)
    $a = Invoke-Herdr -Arguments @('agent', 'list')
    if ($a.ExitCode -ne 0 -or -not $a.Json) { throw "herdr agent list fallo: $($a.Text)" }
    $agents = @(@($a.Json.result.agents) | Where-Object { $_ -and (-not $WorkspaceId -or $_.workspace_id -eq $WorkspaceId) } | ForEach-Object { ConvertTo-TeamAgent $_ })
    $paneArgs = @('pane', 'list')
    if ($WorkspaceId) { $paneArgs += @('--workspace', $WorkspaceId) }
    $p = Invoke-Herdr -Arguments $paneArgs
    if ($p.ExitCode -ne 0 -or -not $p.Json) { throw "herdr pane list fallo: $($p.Text)" }
    $agentPanes = @($agents | ForEach-Object { $_.PaneId })
    $undetected = @(@($p.Json.result.panes) | Where-Object { $_ -and -not $_.agent -and ($agentPanes -notcontains $_.pane_id) } | ForEach-Object {
        [pscustomobject]@{ PaneId = [string]$_.pane_id; Title = [string]$_.terminal_title; Cwd = [string]$_.cwd }
    })
    return [pscustomobject]@{ Agents = $agents; UndetectedPanes = $undetected }
}

function Get-SuggestedAgentName {
    param([Parameter(Mandatory = $true)][string]$Kind, [string[]]$Taken = @())
    $base = ($Kind.ToLower() -replace '[^a-z0-9_-]', '-')
    if ($base -notmatch '^[a-z]') { $base = "a$base" }
    if ($base.Length -gt 28) { $base = $base.Substring(0, 28) }
    $name = $base
    $i = 2
    while ($Taken -contains $name) { $name = "$base-$i"; $i++ }
    return $name
}

function Set-TeamAgentNames {
    param([Parameter(Mandatory = $true)]$Discovery)
    $taken = @($Discovery.Agents | Where-Object { $_.Name } | ForEach-Object { $_.Name })
    foreach ($ag in $Discovery.Agents) {
        if (-not $ag.Name) {
            $name = Get-SuggestedAgentName -Kind $ag.Kind -Taken $taken
            $r = Invoke-Herdr -Arguments @('agent', 'rename', $ag.PaneId, $name)
            if ($r.ExitCode -ne 0) { throw "No se pudo nombrar el agente de $($ag.PaneId): $($r.Text)" }
            $ag.Name = $name
            $taken += $name
        }
    }
    return $Discovery
}

function Get-AgentVersion {
    param([Parameter(Mandatory = $true)][string]$Kind)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = (& $Kind --version 2>&1 | Select-Object -First 3 | ForEach-Object { "$_" }) -join ' '
    } catch {
        return ''
    } finally {
        $ErrorActionPreference = $prev
    }
    if ($out -match '(\d+\.\d+\.\d+)') { return $matches[1] }
    return ''
}

function Save-TeamCheckpoint {
    param([Parameter(Mandatory = $true)][string]$ProjectPath)
    $root = Resolve-TeamPath $ProjectPath
    $cfgPath = Join-Path $root '.team\team.toml'
    $cfg = Read-TeamConfig -Path $cfgPath
    $disc = Get-TeamAgents -WorkspaceId ''
    foreach ($role in @('planner', 'executor')) {
        $r = $cfg.roles[$role]
        $live = @($disc.Agents | Where-Object { $_.Name -eq [string]$r.agent_name }) | Select-Object -First 1
        if ($live -and $live.SessionId) { $r['last_session_id'] = [string]$live.SessionId }
    }
    Write-TeamConfig -Path $cfgPath -Data $cfg
    Update-TeamState -ProjectPath $root | Out-Null
    return $cfg
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run.ps1`
Expected: PASS, `Failed: 0`. Si las variables de prueba no se ven dentro de un `Mock` con Pester 3.4, deja el JSON escrito dentro del cuerpo del mock (como arriba) y no lo saques a variables externas.

- [ ] **Step 5: Commit**

```bash
git add lib/Herdr.ps1 tests/Herdr.Tests.ps1
git -c user.name="jcgmU" -c user.email="jcgm1047@gmail.com" commit -m "feat: add herdr wrapper, agent discovery and checkpoint" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Handoffs (traspasos de trabajo)

**Files:**
- Create: `lib/Handoff.ps1`, `tests/Handoff.Tests.ps1`

**Interfaces:**
- Consumes: Task 1 (`Write-TeamFile`, `Read-TeamFile`, `Resolve-TeamPath`), Task 4 (`Invoke-Herdr`).
- Produces:
  - `New-TeamHandoff -ProjectPath -From -To -Type -Thread [-Round <int>=1] [-Criteria <string[]>] [-References <string[]>] [-Body <string>] [-Now <datetime>]` → `[string]` ruta del archivo `brain\Handoffs\yyyy-MM-dd-HHmm-<de>-a-<para>[-N].md`.
  - `Read-HandoffFrontmatter -Path` → `[ordered]` con `path, de, para, tipo, estado, hilo, ronda, creado` (strings).
  - `Set-HandoffState -Path -State`.
  - `Get-TeamHandoffs -ProjectPath [-Open]` → arreglo de frontmatters (`-Open` = `pendiente|en-curso|no-entregado`).
  - `Get-ThreadRejectionCount -ProjectPath -Thread` → `[int]` handoffs `hallazgos` del hilo.
  - `Send-TeamHandoff -Path [-TimeoutMs <int>=15000]` → `[bool]`; marca `en-curso` o `no-entregado`.

- [ ] **Step 1: Escribir el test que falla** — `tests/Handoff.Tests.ps1`

```powershell
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here '..\lib\TeamKit.psm1') -Force

function New-HandoffProject {
    $p = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Force -Path (Join-Path $p 'brain\Handoffs') | Out-Null
    return $p
}

Describe 'New-TeamHandoff / Read-HandoffFrontmatter' {
    It 'escribe el frontmatter completo en estado pendiente' {
        $p = New-HandoffProject
        $h = New-TeamHandoff -ProjectPath $p -From 'kimi' -To 'agy' -Type 'plan' -Thread 'login' -Round 2 -Criteria @('tests verdes') -References @('docs/a.md') -Body 'hacer el login' -Now ([datetime]'2026-10-11 14:30')
        (Split-Path -Leaf $h) | Should Be '2026-10-11-1430-kimi-a-agy.md'
        $fm = Read-HandoffFrontmatter -Path $h
        $fm.de | Should Be 'kimi'
        $fm.para | Should Be 'agy'
        $fm.tipo | Should Be 'plan'
        $fm.estado | Should Be 'pendiente'
        $fm.hilo | Should Be 'login'
        $fm.ronda | Should Be '2'
        $fm.creado | Should Be '2026-10-11T14:30:00'
        (Read-TeamFile $h) | Should Match '  - "tests verdes"'
    }
    It 'no pisa un handoff del mismo minuto' {
        $p = New-HandoffProject
        $now = [datetime]'2026-10-11 14:30'
        $a = New-TeamHandoff -ProjectPath $p -From 'kimi' -To 'agy' -Type 'plan' -Thread 'x' -Now $now
        $b = New-TeamHandoff -ProjectPath $p -From 'kimi' -To 'agy' -Type 'plan' -Thread 'x' -Now $now
        $a | Should Not Be $b
        (Split-Path -Leaf $b) | Should Be '2026-10-11-1430-kimi-a-agy-2.md'
    }
    It 'conserva comillas, enye, tildes y emoji sin BOM' {
        $p = New-HandoffProject
        $raro = 'el "boton" de ' + [char]0x00F1 + 'and' + [char]0x00FA + ' ' + [char]::ConvertFromUtf32(0x1F600)
        $h = New-TeamHandoff -ProjectPath $p -From 'kimi' -To 'agy' -Type 'plan' -Thread 'x' -Criteria @($raro) -Body $raro
        $text = Read-TeamFile $h
        $text.Contains($raro) | Should Be $true
        $text.Contains('"el \"bot') | Should Be $true
        $bytes = [System.IO.File]::ReadAllBytes($h)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should Be $false
        (Read-HandoffFrontmatter -Path $h).estado | Should Be 'pendiente'
    }
    It 'rechaza tipos y nombres invalidos' {
        $p = New-HandoffProject
        { New-TeamHandoff -ProjectPath $p -From 'kimi' -To 'agy' -Type 'charla' -Thread 'x' } | Should Throw 'Tipo invalido'
        { New-TeamHandoff -ProjectPath $p -From 'Kimi Code' -To 'agy' -Type 'plan' -Thread 'x' } | Should Throw 'Valor invalido para de'
    }
}

Describe 'Set-HandoffState / Get-TeamHandoffs / Get-ThreadRejectionCount' {
    It 'cambia solo el estado del frontmatter' {
        $p = New-HandoffProject
        $h = New-TeamHandoff -ProjectPath $p -From 'kimi' -To 'agy' -Type 'plan' -Thread 'x' -Body "estado: esto es del cuerpo"
        Set-HandoffState -Path $h -State 'hecho'
        (Read-HandoffFrontmatter -Path $h).estado | Should Be 'hecho'
        (Read-TeamFile $h) | Should Match 'estado: esto es del cuerpo'
        { Set-HandoffState -Path $h -State 'perdido' } | Should Throw 'Estado invalido'
    }
    It 'filtra abiertos y cuenta hallazgos por hilo' {
        $p = New-HandoffProject
        $a = New-TeamHandoff -ProjectPath $p -From 'claude' -To 'kimi' -Type 'hallazgos' -Thread 'login'
        $b = New-TeamHandoff -ProjectPath $p -From 'claude' -To 'kimi' -Type 'hallazgos' -Thread 'login'
        $c = New-TeamHandoff -ProjectPath $p -From 'claude' -To 'kimi' -Type 'hallazgos' -Thread 'otro'
        Set-HandoffState -Path $a -State 'cerrado'
        @(Get-TeamHandoffs -ProjectPath $p).Count | Should Be 3
        @(Get-TeamHandoffs -ProjectPath $p -Open).Count | Should Be 2
        Get-ThreadRejectionCount -ProjectPath $p -Thread 'login' | Should Be 2
    }
}

Describe 'Send-TeamHandoff' {
    It 'entrega al primer intento y marca en-curso' {
        Mock -ModuleName TeamKit Invoke-Herdr { [pscustomobject]@{ ExitCode = 0; Text = '{}'; Json = $null } }
        $p = New-HandoffProject
        $h = New-TeamHandoff -ProjectPath $p -From 'kimi' -To 'agy' -Type 'plan' -Thread 'demo'
        Send-TeamHandoff -Path $h | Should Be $true
        (Read-HandoffFrontmatter -Path $h).estado | Should Be 'en-curso'
        Assert-MockCalled -ModuleName TeamKit Invoke-Herdr -Times 1 -Exactly -ParameterFilter {
            $Arguments[0] -eq 'agent' -and $Arguments[1] -eq 'prompt' -and $Arguments[2] -eq 'agy' -and ($Arguments -contains 'working') -and ($Arguments[3] -notmatch '"') -and ($Arguments[3] -match 'brain/Handoffs/')
        }
    }
    It 'reintenta una vez y marca no-entregado si falla' {
        Mock -ModuleName TeamKit Invoke-Herdr { [pscustomobject]@{ ExitCode = 1; Text = '{"error":{"code":"agent_prompt_stalled"}}'; Json = $null } }
        $p = New-HandoffProject
        $h = New-TeamHandoff -ProjectPath $p -From 'kimi' -To 'agy' -Type 'plan' -Thread 'demo'
        Send-TeamHandoff -Path $h | Should Be $false
        (Read-HandoffFrontmatter -Path $h).estado | Should Be 'no-entregado'
        Assert-MockCalled -ModuleName TeamKit Invoke-Herdr -Times 2 -Exactly
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Script tests\Handoff.Tests.ps1"`
Expected: FAIL (`New-TeamHandoff` no reconocido).

- [ ] **Step 3: Implementar `lib/Handoff.ps1`**

```powershell
$script:HandoffTypes = @('objetivo', 'plan', 'ejecucion', 'listo-para-verificar', 'hallazgos', 'aprobado', 'bloqueo')
$script:HandoffStates = @('pendiente', 'en-curso', 'hecho', 'no-entregado', 'cerrado')
$script:Invariant = [System.Globalization.CultureInfo]::InvariantCulture

function ConvertTo-YamlString {
    param([AllowEmptyString()][string]$Value)
    return '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"'
}

function New-TeamHandoff {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][string]$From,
        [Parameter(Mandatory = $true)][string]$To,
        [Parameter(Mandatory = $true)][string]$Type,
        [Parameter(Mandatory = $true)][string]$Thread,
        [int]$Round = 1,
        [string[]]$Criteria = @(),
        [string[]]$References = @(),
        [AllowEmptyString()][string]$Body = '',
        [datetime]$Now = (Get-Date)
    )
    if ($script:HandoffTypes -notcontains $Type) { throw "Tipo invalido '$Type'. Validos: $($script:HandoffTypes -join ', ')" }
    foreach ($pair in @(@('de', $From), @('para', $To), @('hilo', $Thread))) {
        if ($pair[1] -cnotmatch '^[a-z0-9][a-z0-9_-]{0,62}$') { throw "Valor invalido para $($pair[0]): '$($pair[1])' (minusculas, numeros, - y _)" }
    }
    $dir = Join-Path (Resolve-TeamPath $ProjectPath) 'brain\Handoffs'
    if (-not (Test-Path -LiteralPath $dir)) { throw "No existe $dir" }
    $base = '{0}-{1}-a-{2}' -f $Now.ToString('yyyy-MM-dd-HHmm', $script:Invariant), $From, $To
    $path = Join-Path $dir "$base.md"
    $i = 2
    while (Test-Path -LiteralPath $path) { $path = Join-Path $dir "$base-$i.md"; $i++ }
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('---')
    [void]$lines.Add("de: $From")
    [void]$lines.Add("para: $To")
    [void]$lines.Add("tipo: $Type")
    [void]$lines.Add('estado: pendiente')
    [void]$lines.Add("hilo: $Thread")
    [void]$lines.Add("ronda: $Round")
    [void]$lines.Add('creado: ' + $Now.ToString("yyyy-MM-dd'T'HH:mm:ss", $script:Invariant))
    [void]$lines.Add('criterios_de_aceptacion:')
    foreach ($c in $Criteria) { [void]$lines.Add('  - ' + (ConvertTo-YamlString $c)) }
    [void]$lines.Add('referencias:')
    foreach ($r in $References) { [void]$lines.Add('  - ' + (ConvertTo-YamlString $r)) }
    [void]$lines.Add('---')
    [void]$lines.Add('')
    [void]$lines.Add("# $Type - $Thread - ronda $Round")
    [void]$lines.Add('')
    [void]$lines.Add($Body)
    Write-TeamFile -Path $path -Content (($lines -join "`n") + "`n")
    return $path
}

function Read-HandoffFrontmatter {
    param([Parameter(Mandatory = $true)][string]$Path)
    $lines = (Read-TeamFile $Path) -split "`r?`n"
    if ($lines[0].Trim() -ne '---') { throw "Handoff sin frontmatter: $Path" }
    $fm = [ordered]@{ path = (Resolve-TeamPath $Path) }
    for ($k = 1; $k -lt $lines.Count; $k++) {
        if ($lines[$k].Trim() -eq '---') { return $fm }
        if ($lines[$k] -match '^([a-z_]+):\s*(\S.*)$') { $fm[$matches[1]] = $matches[2].Trim() }
    }
    throw "Frontmatter sin cerrar: $Path"
}

function Set-HandoffState {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$State)
    if ($script:HandoffStates -notcontains $State) { throw "Estado invalido '$State'. Validos: $($script:HandoffStates -join ', ')" }
    $text = Read-TeamFile $Path
    $re = New-Object System.Text.RegularExpressions.Regex('(?m)^estado:[^\r\n]*')
    if (-not $re.IsMatch($text)) { throw "Handoff sin campo estado: $Path" }
    Write-TeamFile -Path $Path -Content ($re.Replace($text, "estado: $State", 1))
}

function Get-TeamHandoffs {
    param([Parameter(Mandatory = $true)][string]$ProjectPath, [switch]$Open)
    $dir = Join-Path (Resolve-TeamPath $ProjectPath) 'brain\Handoffs'
    $items = @(Get-ChildItem -LiteralPath $dir -Filter '*.md' -File | Sort-Object Name | ForEach-Object { Read-HandoffFrontmatter -Path $_.FullName })
    if ($Open) { $items = @($items | Where-Object { @('pendiente', 'en-curso', 'no-entregado') -contains $_.estado }) }
    return ,$items
}

function Get-ThreadRejectionCount {
    param([Parameter(Mandatory = $true)][string]$ProjectPath, [Parameter(Mandatory = $true)][string]$Thread)
    return @((Get-TeamHandoffs -ProjectPath $ProjectPath) | Where-Object { $_.hilo -eq $Thread -and $_.tipo -eq 'hallazgos' }).Count
}

function Send-TeamHandoff {
    param([Parameter(Mandatory = $true)][string]$Path, [int]$TimeoutMs = 15000)
    $fm = Read-HandoffFrontmatter -Path $Path
    $rel = 'brain/Handoffs/' + (Split-Path -Leaf $Path)
    $text = "Nuevo handoff para ti ($($fm.tipo), hilo $($fm.hilo), ronda $($fm.ronda)): $rel - leelo completo y actua segun brain/Equipo/Protocolo.md"
    $text = $text -replace '"', "'"
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $r = Invoke-Herdr -Arguments @('agent', 'prompt', [string]$fm.para, $text, '--wait', '--until', 'working', '--until', 'done', '--until', 'blocked', '--timeout', [string]$TimeoutMs)
        if ($r.ExitCode -eq 0) {
            Set-HandoffState -Path $Path -State 'en-curso'
            return $true
        }
    }
    Set-HandoffState -Path $Path -State 'no-entregado'
    return $false
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run.ps1`
Expected: PASS, `Failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add lib/Handoff.ps1 tests/Handoff.Tests.ps1
git -c user.name="jcgmU" -c user.email="jcgm1047@gmail.com" commit -m "feat: add file-based handoffs with delivery confirmation" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Salud del equipo (`team-doctor`)

**Files:**
- Create: `lib/Health.ps1`, `tests/Health.Tests.ps1`

**Interfaces:**
- Consumes: Task 1, Task 3 (`Initialize-TeamBrain`, `Complete-TeamBootstrap` en tests), Task 4 (`Invoke-Herdr`, `Get-TeamAgents`, `Get-AgentVersion`), Task 5 (`Get-TeamHandoffs`, `New-TeamHandoff`, `Set-HandoffState`).
- Produces:
  - `Get-EngramDataDir -Kind -HomePath` → `{ Known; Configured; DataDir }`.
  - `Test-TeamHealth [-ProjectPath] [-SkipProject] [-HomePath = $HOME] [-Discovery] [-Now]` → arreglo de `{ Check; Status (ok|warn|fail); Detail; Fix }`. Nombres de `Check`: `herdr-env, deteccion, integracion, engram, vault, punteros, team-config, rol-planner, rol-executor, version-planner, version-executor, handoffs`.
  - `Format-TeamHealth -Results` → `[string]` tabla ASCII (`[OK] / [WARN] / [FAIL]`).

- [ ] **Step 1: Escribir el test que falla** — `tests/Health.Tests.ps1`

```powershell
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here '..\lib\TeamKit.psm1') -Force

function New-HealthProject {
    $p = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Force -Path $p | Out-Null
    Initialize-TeamBrain -ProjectPath $p -ProjectName 'demo' | Out-Null
    $o = [pscustomobject]@{ Name = 'claude'; Kind = 'claude'; Version = '2.1.296'; SessionId = '' }
    $pl = [pscustomobject]@{ Name = 'kimi'; Kind = 'kimi'; Version = '2.1.1'; SessionId = '' }
    $ex = [pscustomobject]@{ Name = 'agy'; Kind = 'agy'; Version = '1.3.3'; SessionId = '' }
    Complete-TeamBootstrap -ProjectPath $p -ProjectName 'demo' -Orchestrator $o -Planner $pl -Executor $ex | Out-Null
    return $p
}
function New-HealthHome([string]$ClaudeDir, [string]$KimiDir, [string]$AgyDir) {
    $h = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    $std = Join-Path $h '.engram'
    if (-not $ClaudeDir) { $ClaudeDir = $std }
    if (-not $KimiDir) { $KimiDir = $std }
    if (-not $AgyDir) { $AgyDir = $std }
    $tpl = '{{"mcpServers":{{"engram":{{"command":"engram.exe","env":{{"ENGRAM_DATA_DIR":"{0}"}}}}}}}}'
    Write-TeamFile -Path (Join-Path $h '.claude.json') -Content ($tpl -f $ClaudeDir.Replace('\', '\\'))
    Write-TeamFile -Path (Join-Path $h '.kimi-code\mcp.json') -Content ($tpl -f $KimiDir.Replace('\', '\\'))
    Write-TeamFile -Path (Join-Path $h '.gemini\config\mcp_config.json') -Content ($tpl -f $AgyDir.Replace('\', '\\'))
    return $h
}
function New-Disc([object[]]$Extra = @(), [string[]]$Without = @()) {
    $all = @(
        [pscustomobject]@{ Name = 'claude'; Kind = 'claude'; PaneId = 'w1:p1'; IsSelf = $true; SessionId = '' },
        [pscustomobject]@{ Name = 'kimi'; Kind = 'kimi'; PaneId = 'w1:p2'; IsSelf = $false; SessionId = '' },
        [pscustomobject]@{ Name = 'agy'; Kind = 'agy'; PaneId = 'w1:p3'; IsSelf = $false; SessionId = '' }
    ) | Where-Object { $Without -notcontains $_.Name }
    return [pscustomobject]@{ Agents = @(@($all) + @($Extra)); UndetectedPanes = @() }
}
function Get-Check($Results, [string]$Name) { return @($Results | Where-Object { $_.Check -eq $Name })[0] }

Describe 'Test-TeamHealth' {
    BeforeEach {
        $script:prevHerdrEnv = $env:HERDR_ENV
        $env:HERDR_ENV = '1'
        Mock -ModuleName TeamKit Invoke-Herdr {
            [pscustomobject]@{ ExitCode = 0; Text = "claude: current (v8) (x)`nkimi: current (v7) (x)`nantigravity-cli: current (v2) (x)"; Json = $null }
        } -ParameterFilter { $Arguments[0] -eq 'integration' }
        Mock -ModuleName TeamKit Get-AgentVersion { switch ($Kind) { 'kimi' { '2.1.1' } 'agy' { '1.3.3' } default { '2.1.296' } } }
    }
    AfterEach { $env:HERDR_ENV = $script:prevHerdrEnv }

    It 'un proyecto sano no tiene fallos ni avisos' {
        $r = Test-TeamHealth -ProjectPath (New-HealthProject) -HomePath (New-HealthHome) -Discovery (New-Disc)
        @($r | Where-Object { $_.Status -ne 'ok' }).Count | Should Be 0
        (Get-Check $r 'rol-planner').Status | Should Be 'ok'
    }
    It 'fuera de Herdr devuelve un solo fallo' {
        $env:HERDR_ENV = ''
        $r = Test-TeamHealth -SkipProject -HomePath (New-HealthHome) -Discovery (New-Disc)
        @($r).Count | Should Be 1
        (Get-Check $r 'herdr-env').Status | Should Be 'fail'
    }
    It 'detecta bases engram distintas' {
        $r = Test-TeamHealth -SkipProject -HomePath (New-HealthHome -KimiDir 'D:\otra') -Discovery (New-Disc)
        (Get-Check $r 'engram').Status | Should Be 'fail'
        (Get-Check $r 'engram').Detail | Should Match 'distintas'
    }
    It 'avisa si la base engram comun no esta en la ruta estandar' {
        $r = Test-TeamHealth -SkipProject -HomePath (New-HealthHome -ClaudeDir 'D:\m' -KimiDir 'D:\m' -AgyDir 'D:\m') -Discovery (New-Disc)
        (Get-Check $r 'engram').Status | Should Be 'warn'
        (Get-Check $r 'engram').Detail | Should Match 'no estandar'
    }
    It 'falla si un agente no tiene engram configurado' {
        $h = New-HealthHome
        Remove-Item -LiteralPath (Join-Path $h '.kimi-code\mcp.json')
        $r = Test-TeamHealth -SkipProject -HomePath $h -Discovery (New-Disc)
        (Get-Check $r 'engram').Status | Should Be 'fail'
        (Get-Check $r 'engram').Detail | Should Match 'kimi'
    }
    It 'avisa que un tipo de agente desconocido no es verificable' {
        $extra = [pscustomobject]@{ Name = 'codex'; Kind = 'codex'; PaneId = 'w1:p9'; IsSelf = $false; SessionId = '' }
        $r = Test-TeamHealth -SkipProject -HomePath (New-HealthHome) -Discovery (New-Disc -Extra @($extra))
        (Get-Check $r 'engram').Status | Should Be 'warn'
        (Get-Check $r 'engram').Detail | Should Match 'codex: no verificable'
    }
    It 'avisa de panes sin agente detectado' {
        $d = New-Disc
        $d.UndetectedPanes = @([pscustomobject]@{ PaneId = 'w1:p4'; Title = 'kimi-code'; Cwd = 'C:\p' })
        $r = Test-TeamHealth -SkipProject -HomePath (New-HealthHome) -Discovery $d
        (Get-Check $r 'deteccion').Status | Should Be 'warn'
        (Get-Check $r 'deteccion').Detail | Should Match 'w1:p4'
    }
    It 'avisa de integraciones desactualizadas' {
        Mock -ModuleName TeamKit Invoke-Herdr {
            [pscustomobject]@{ ExitCode = 0; Text = "claude: current (v8) (x)`nkimi: outdated (v6) (x)`nantigravity-cli: current (v2) (x)"; Json = $null }
        } -ParameterFilter { $Arguments[0] -eq 'integration' }
        $r = Test-TeamHealth -SkipProject -HomePath (New-HealthHome) -Discovery (New-Disc)
        (Get-Check $r 'integracion').Status | Should Be 'warn'
        (Get-Check $r 'integracion').Fix | Should Match 'herdr integration install kimi'
    }
    It 'falla si falta un archivo del vault y avisa si falta un puntero' {
        $p = New-HealthProject
        Remove-Item -LiteralPath (Join-Path $p 'brain\Equipo\Protocolo.md')
        Remove-Item -LiteralPath (Join-Path $p 'GEMINI.md')
        $r = Test-TeamHealth -ProjectPath $p -HomePath (New-HealthHome) -Discovery (New-Disc)
        (Get-Check $r 'vault').Status | Should Be 'fail'
        (Get-Check $r 'vault').Detail | Should Match 'Protocolo'
        (Get-Check $r 'punteros').Status | Should Be 'warn'
    }
    It 'reporta un team.toml con TOML no soportado sin romperse' {
        $p = New-HealthProject
        Write-TeamFile -Path (Join-Path $p '.team\team.toml') -Content "[project]`nname = { a = 1 }"
        $r = Test-TeamHealth -ProjectPath $p -HomePath (New-HealthHome) -Discovery (New-Disc)
        (Get-Check $r 'team-config').Status | Should Be 'fail'
        (Get-Check $r 'team-config').Detail | Should Match 'linea 2'
    }
    It 'distingue rol con otro nombre (warn) de rol ausente (fail)' {
        $p = New-HealthProject
        $renamed = [pscustomobject]@{ Name = 'agy-2'; Kind = 'agy'; PaneId = 'w1:p7'; IsSelf = $false; SessionId = '' }
        $r = Test-TeamHealth -ProjectPath $p -HomePath (New-HealthHome) -Discovery (New-Disc -Without @('agy') -Extra @($renamed))
        (Get-Check $r 'rol-executor').Status | Should Be 'warn'
        (Get-Check $r 'rol-executor').Fix | Should Match 'herdr agent rename w1:p7 agy'
        $r2 = Test-TeamHealth -ProjectPath $p -HomePath (New-HealthHome) -Discovery (New-Disc -Without @('agy'))
        (Get-Check $r2 'rol-executor').Status | Should Be 'fail'
    }
    It 'avisa si cambio la version de un agente' {
        Mock -ModuleName TeamKit Get-AgentVersion { if ($Kind -eq 'kimi') { '9.9.9' } else { '1.3.3' } }
        $r = Test-TeamHealth -ProjectPath (New-HealthProject) -HomePath (New-HealthHome) -Discovery (New-Disc)
        (Get-Check $r 'version-planner').Status | Should Be 'warn'
        (Get-Check $r 'version-planner').Detail | Should Match '2.1.1 -> 9.9.9'
    }
    It 'avisa de handoffs no entregados o abiertos hace mas de 24 h' {
        $p = New-HealthProject
        $h = New-TeamHandoff -ProjectPath $p -From 'kimi' -To 'agy' -Type 'plan' -Thread 'x' -Now ([datetime]'2026-10-01 10:00')
        $r = Test-TeamHealth -ProjectPath $p -HomePath (New-HealthHome) -Discovery (New-Disc) -Now ([datetime]'2026-10-03 10:00')
        (Get-Check $r 'handoffs').Status | Should Be 'warn'
        Set-HandoffState -Path $h -State 'no-entregado'
        $r2 = Test-TeamHealth -ProjectPath $p -HomePath (New-HealthHome) -Discovery (New-Disc) -Now ([datetime]'2026-10-01 10:05')
        (Get-Check $r2 'handoffs').Detail | Should Match 'no-entregado'
    }
    It 'con SkipProject no revisa el vault' {
        $r = Test-TeamHealth -SkipProject -HomePath (New-HealthHome) -Discovery (New-Disc)
        Get-Check $r 'vault' | Should BeNullOrEmpty
    }
}

Describe 'Format-TeamHealth' {
    It 'genera una linea por chequeo con su arreglo' {
        $txt = Format-TeamHealth -Results @([pscustomobject]@{ Check = 'engram'; Status = 'fail'; Detail = 'malo'; Fix = 'arreglar' })
        $txt | Should Match '^\[FAIL\]\s+engram\s+malo -> arreglar$'
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Script tests\Health.Tests.ps1"`
Expected: FAIL (`Test-TeamHealth` no reconocido).

- [ ] **Step 3: Implementar `lib/Health.ps1`**

```powershell
$script:EngramConfigFiles = @{ claude = '.claude.json'; kimi = '.kimi-code\mcp.json'; agy = '.gemini\config\mcp_config.json' }
$script:IntegrationNames = @{ agy = 'antigravity-cli' }

function New-HealthResult {
    param([string]$Check, [string]$Status, [string]$Detail, [string]$Fix = '')
    return [pscustomobject]@{ Check = $Check; Status = $Status; Detail = $Detail; Fix = $Fix }
}

function Merge-HealthStatus {
    param([string]$Current, [string]$New)
    if ($New -eq 'fail' -or $Current -eq 'fail') { return 'fail' }
    if ($New -eq 'warn' -or $Current -eq 'warn') { return 'warn' }
    return 'ok'
}

function Get-EngramDataDir {
    param([Parameter(Mandatory = $true)][string]$Kind, [Parameter(Mandatory = $true)][string]$HomePath)
    if (-not $script:EngramConfigFiles.ContainsKey($Kind)) { return [pscustomobject]@{ Known = $false; Configured = $false; DataDir = '' } }
    $file = Join-Path $HomePath $script:EngramConfigFiles[$Kind]
    if (-not (Test-Path -LiteralPath $file)) { return [pscustomobject]@{ Known = $true; Configured = $false; DataDir = '' } }
    $text = Read-TeamFile $file
    if ($text -notmatch '"engram"\s*:\s*\{') { return [pscustomobject]@{ Known = $true; Configured = $false; DataDir = '' } }
    $dir = Join-Path $HomePath '.engram'
    if ($text -match '"ENGRAM_DATA_DIR"\s*:\s*"((?:[^"\\]|\\.)*)"') { $dir = $matches[1].Replace('\\', '\') }
    return [pscustomobject]@{ Known = $true; Configured = $true; DataDir = [System.IO.Path]::GetFullPath($dir) }
}

function Test-TeamHealth {
    param(
        [string]$ProjectPath,
        [switch]$SkipProject,
        [string]$HomePath = $HOME,
        $Discovery,
        [datetime]$Now = (Get-Date)
    )
    $results = New-Object System.Collections.ArrayList
    if ($env:HERDR_ENV -ne '1') {
        [void]$results.Add((New-HealthResult 'herdr-env' 'fail' 'HERDR_ENV no es 1: esta sesion no corre dentro de Herdr' 'Abre esta sesion dentro de un pane de Herdr'))
        return ,$results.ToArray()
    }
    [void]$results.Add((New-HealthResult 'herdr-env' 'ok' 'Corriendo dentro de Herdr'))
    if (-not $Discovery) { $Discovery = Get-TeamAgents }

    $und = @($Discovery.UndetectedPanes)
    if ($und.Count -eq 0) {
        [void]$results.Add((New-HealthResult 'deteccion' 'ok' 'Todos los panes con agente estan detectados'))
    } else {
        $list = ($und | ForEach-Object { "$($_.PaneId) ($($_.Title))" }) -join ', '
        [void]$results.Add((New-HealthResult 'deteccion' 'warn' "Panes sin agente detectado: $list" 'Lee el pane; si hay un agente, en Windows Herdr no ve node.exe: lanzalo desde un ejecutable nativo con el alias del manifiesto de deteccion (ver skill team-doctor)'))
    }

    $kinds = @($Discovery.Agents | ForEach-Object { [string]$_.Kind } | Where-Object { $_ } | Sort-Object -Unique)
    $integration = Invoke-Herdr -Arguments @('integration', 'status')
    $intStatus = 'ok'
    $intDetail = @()
    $intFix = @()
    foreach ($k in $kinds) {
        $name = $script:IntegrationNames[$k]
        if (-not $name) { $name = $k }
        $line = @(($integration.Text -split "`r?`n") | Where-Object { $_ -match ('^' + [regex]::Escape($name) + ':\s*(.+)$') })[0]
        if (-not $line) {
            $intStatus = Merge-HealthStatus $intStatus 'warn'
            $intDetail += "${k}: sin integracion de hooks (deteccion solo por pantalla)"
        } elseif ($line -match ':\s*current') {
            $intDetail += "${k}: al dia"
        } else {
            $intStatus = Merge-HealthStatus $intStatus 'warn'
            $intDetail += "${k}: $(($line -split ':\s*', 2)[1])"
            $intFix += "herdr integration install $name"
        }
    }
    [void]$results.Add((New-HealthResult 'integracion' $intStatus ($intDetail -join '; ') ($intFix -join '; ')))

    $engStatus = 'ok'
    $engDetail = @()
    $dirs = [ordered]@{}
    foreach ($k in @(@('claude') + $kinds | Sort-Object -Unique)) {
        $e = Get-EngramDataDir -Kind $k -HomePath $HomePath
        if (-not $e.Known) { $engStatus = Merge-HealthStatus $engStatus 'warn'; $engDetail += "${k}: no verificable"; continue }
        if (-not $e.Configured) { $engStatus = Merge-HealthStatus $engStatus 'fail'; $engDetail += "${k}: engram no configurado"; continue }
        $dirs[$k] = $e.DataDir
    }
    $unique = @($dirs.Values | Sort-Object -Unique)
    if ($unique.Count -gt 1) {
        $engStatus = Merge-HealthStatus $engStatus 'fail'
        $engDetail += 'bases distintas: ' + (($dirs.Keys | ForEach-Object { "$_=$($dirs[$_])" }) -join '; ')
    } elseif ($unique.Count -eq 1) {
        $std = [System.IO.Path]::GetFullPath((Join-Path $HomePath '.engram'))
        if ($unique[0] -ne $std) { $engStatus = Merge-HealthStatus $engStatus 'warn'; $engDetail += "base compartida en ruta no estandar: $($unique[0])" }
        else { $engDetail += "base compartida: $($unique[0])" }
    }
    $engFix = ''
    if ($engStatus -ne 'ok') { $engFix = 'Configura el MCP engram de todos los agentes con el mismo ENGRAM_DATA_DIR (recomendado ~/.engram, fuera de cualquier proyecto)' }
    [void]$results.Add((New-HealthResult 'engram' $engStatus ($engDetail -join '; ') $engFix))

    if ($SkipProject) { return ,$results.ToArray() }

    $root = Resolve-TeamPath $ProjectPath
    $required = @('brain\00-Inicio.md', 'brain\Equipo\Protocolo.md', 'brain\Equipo\Comandos.md', 'brain\Estado\STATE.md', 'brain\Equipo\Fichas', 'brain\Handoffs', 'brain\Decisiones', 'brain\Verificaciones', '.team\team.toml', '.team\verify.toml')
    $missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $root $_)) })
    if ($missing.Count -eq 0) { [void]$results.Add((New-HealthResult 'vault' 'ok' 'Vault y .team completos')) }
    else { [void]$results.Add((New-HealthResult 'vault' 'fail' ('Faltan: ' + ($missing -join ', ')) 'Restaura desde git; Protocolo y Comandos se regeneran con team.ps1 docs')) }

    $noPointer = @(@('CLAUDE.md', 'AGENTS.md', 'GEMINI.md') | Where-Object {
        $f = Join-Path $root $_
        -not (Test-Path -LiteralPath $f) -or -not ((Read-TeamFile $f).Contains('<!-- team:begin -->'))
    })
    if ($noPointer.Count -eq 0) { [void]$results.Add((New-HealthResult 'punteros' 'ok' 'CLAUDE.md, AGENTS.md y GEMINI.md apuntan al vault')) }
    else { [void]$results.Add((New-HealthResult 'punteros' 'warn' ('Sin bloque del equipo: ' + ($noPointer -join ', ')) 'team.ps1 docs')) }

    $cfg = $null
    try {
        $cfg = Read-TeamConfig -Path (Join-Path $root '.team\team.toml')
        if (-not $cfg.Contains('roles') -or -not $cfg.roles.Contains('planner') -or -not $cfg.roles.Contains('executor')) { throw 'faltan [roles.planner] o [roles.executor]' }
        [void]$results.Add((New-HealthResult 'team-config' 'ok' 'team.toml valido'))
    } catch {
        [void]$results.Add((New-HealthResult 'team-config' 'fail' $_.Exception.Message 'Corrige .team\team.toml (formato en el encabezado de .team\verify.toml) o restauralo desde git'))
        $cfg = $null
    }

    if ($cfg) {
        $assigned = @([string]$cfg.roles.planner.agent_name, [string]$cfg.roles.executor.agent_name, [string]$cfg.orchestrator.agent_name)
        foreach ($role in @('planner', 'executor')) {
            $want = [string]$cfg.roles[$role].agent_name
            $kind = [string]$cfg.roles[$role].kind
            $byName = @($Discovery.Agents | Where-Object { $_.Name -eq $want })
            if ($byName.Count -gt 0) {
                [void]$results.Add((New-HealthResult "rol-$role" 'ok' "$want ($kind) presente en $($byName[0].PaneId)"))
            } else {
                $cand = @($Discovery.Agents | Where-Object { $_.Kind -eq $kind -and ($assigned -notcontains $_.Name) -and -not $_.IsSelf })
                if ($cand.Count -gt 0) {
                    [void]$results.Add((New-HealthResult "rol-$role" 'warn' "$want no esta, pero hay un agente $kind en $($cand[0].PaneId) llamado $($cand[0].Name)" "herdr agent rename $($cand[0].PaneId) $want"))
                } else {
                    [void]$results.Add((New-HealthResult "rol-$role" 'fail' "$want ($kind) no esta en Herdr" 'Lanza el agente (team-resume) o asigna otro con team.ps1 set-role'))
                }
            }
            $old = [string]$cfg.roles[$role].version
            $live = Get-AgentVersion -Kind $kind
            if ($live -and $old -and $live -ne $old) {
                [void]$results.Add((New-HealthResult "version-$role" 'warn' "$want cambio de version: $old -> $live" "Regenera la ficha de $want y corre team.ps1 set-role --role $role --agent $want"))
            } else {
                [void]$results.Add((New-HealthResult "version-$role" 'ok' "$want version $old"))
            }
        }
    }

    $handoffDir = Join-Path $root 'brain\Handoffs'
    if (Test-Path -LiteralPath $handoffDir) {
        $open = @(Get-TeamHandoffs -ProjectPath $root -Open)
        $problems = @()
        foreach ($h in $open) {
            $leaf = Split-Path -Leaf $h.path
            if ($h.estado -eq 'no-entregado') { $problems += "$leaf no-entregado"; continue }
            $created = [datetime]::MinValue
            if ([datetime]::TryParseExact([string]$h.creado, "yyyy-MM-dd'T'HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$created)) {
                if (($Now - $created).TotalHours -gt 24) { $problems += "$leaf $($h.estado) hace mas de 24 h" }
            }
        }
        if ($problems.Count -eq 0) { [void]$results.Add((New-HealthResult 'handoffs' 'ok' "$($open.Count) handoffs abiertos al dia")) }
        else { [void]$results.Add((New-HealthResult 'handoffs' 'warn' ($problems -join '; ') 'Reenvia con team.ps1 send-handoff --file <ruta> o cierralos con team.ps1 handoff-state')) }
    }
    return ,$results.ToArray()
}

function Format-TeamHealth {
    param([Parameter(Mandatory = $true)]$Results)
    $icon = @{ ok = '[OK]'; warn = '[WARN]'; fail = '[FAIL]' }
    $lines = foreach ($r in $Results) {
        $fix = ''
        if ($r.Fix) { $fix = " -> $($r.Fix)" }
        '{0,-7} {1,-17} {2}{3}' -f $icon[$r.Status], $r.Check, $r.Detail, $fix
    }
    return ($lines -join "`n")
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run.ps1`
Expected: PASS, `Failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add lib/Health.ps1 tests/Health.Tests.ps1
git -c user.name="jcgmU" -c user.email="jcgm1047@gmail.com" commit -m "feat: add team health checks for team-doctor" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Verificación (`team-verify`)

**Files:**
- Create: `lib/Verify.ps1`, `tests/Verify.Tests.ps1`

**Interfaces:**
- Consumes: Task 1 (`Read-TeamConfig`, `Write-TeamFile`, `Resolve-TeamPath`).
- Produces: `Invoke-TeamVerify -ProjectPath [-Now]` → `[pscustomobject]@{ Passed; Failed; Manual; NotePath; Results = @({ Name; Status (pass|fail|manual); Detail }) }`. Escribe `brain\Verificaciones\yyyy-MM-dd-HHmm-verificacion[-N].md`.

- [ ] **Step 1: Escribir el test que falla** — `tests/Verify.Tests.ps1`

```powershell
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here '..\lib\TeamKit.psm1') -Force

function New-VerifyProject([string]$Toml) {
    $p = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Force -Path (Join-Path $p 'brain\Verificaciones') | Out-Null
    Write-TeamFile -Path (Join-Path $p '.team\verify.toml') -Content $Toml
    return $p
}

Describe 'Invoke-TeamVerify' {
    It 'corre chequeos automaticos y lista los manuales' {
        $toml = @'
[[check]]
name = "pasa"
run = "cmd /c exit 0"

[[check]]
name = "falla"
run = "cmd /c exit 1"

[[check]]
name = "salida"
run = "Write-Output hola-mundo"
expect_output = "hola-mundo"

[[check]]
name = "en la raiz del proyecto"
run = 'if (-not (Test-Path .team\verify.toml)) { exit 5 }'

[[check]]
name = "exit esperado distinto de cero"
run = "cmd /c exit 3"
expect_exit = 3

[[check]]
name = "comillas dobles dentro del comando"
run = "if (\"a b\" -ne 'a b') { exit 1 }"

[[check]]
name = "UI"
manual = "Abrir la app y entrar"
'@
        $v = Invoke-TeamVerify -ProjectPath (New-VerifyProject $toml) -Now ([datetime]'2026-10-11 15:00')
        $v.Passed | Should Be 5
        $v.Failed | Should Be 1
        $v.Manual | Should Be 1
        @($v.Results | Where-Object { $_.Name -eq 'falla' })[0].Detail | Should Match 'exit 1 \(esperado 0\)'
        (Split-Path -Leaf $v.NotePath) | Should Be '2026-10-11-1500-verificacion.md'
        $note = Read-TeamFile $v.NotePath
        $note | Should Match '\| falla \| FALLA \|'
        $note | Should Match '\| UI \| MANUAL \|'
    }
    It 'marca fallo si no aparece la salida esperada' {
        $v = Invoke-TeamVerify -ProjectPath (New-VerifyProject "[[check]]`nname = `"x`"`nrun = `"Write-Output otra`"`nexpect_output = `"buscada`"")
        $v.Failed | Should Be 1
        $v.Results[0].Detail | Should Match "no aparece 'buscada'"
    }
    It 'sin chequeos devuelve cero en todo' {
        $tpl = Read-TeamFile (Join-Path $here '..\templates\verify.toml')
        $v = Invoke-TeamVerify -ProjectPath (New-VerifyProject $tpl)
        ($v.Passed + $v.Failed + $v.Manual) | Should Be 0
    }
    It 'un chequeo sin run ni manual es un fallo' {
        $v = Invoke-TeamVerify -ProjectPath (New-VerifyProject "[[check]]`nname = `"vacio`"")
        $v.Failed | Should Be 1
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Script tests\Verify.Tests.ps1"`
Expected: FAIL (`Invoke-TeamVerify` no reconocido).

- [ ] **Step 3: Implementar `lib/Verify.ps1`**

```powershell
function Invoke-TeamVerify {
    param([Parameter(Mandatory = $true)][string]$ProjectPath, [datetime]$Now = (Get-Date))
    $root = Resolve-TeamPath $ProjectPath
    $cfg = Read-TeamConfig -Path (Join-Path $root '.team\verify.toml')
    $checks = @()
    if ($cfg.Contains('check')) { $checks = @($cfg['check']) }
    $results = @()
    foreach ($c in $checks) {
        $name = [string]$c['name']
        if (-not $name) { $name = '(sin nombre)' }
        if ($c.Contains('manual')) {
            $results += [pscustomobject]@{ Name = $name; Status = 'manual'; Detail = [string]$c['manual'] }
            continue
        }
        if (-not $c.Contains('run')) {
            $results += [pscustomobject]@{ Name = $name; Status = 'fail'; Detail = 'Chequeo sin run ni manual' }
            continue
        }
        $expectExit = 0
        if ($c.Contains('expect_exit')) { $expectExit = [int]$c['expect_exit'] }
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        Push-Location -LiteralPath $root
        try {
            # EncodedCommand: PS 5.1 breaks embedded double quotes when passing -Command to a native process
            $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes([string]$c['run'] + '; exit $LASTEXITCODE'))
            $out = & powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded 2>&1 | Out-String
            $code = $LASTEXITCODE
        } finally {
            Pop-Location
            $ErrorActionPreference = $prev
        }
        $ok = ($code -eq $expectExit)
        $why = "exit $code (esperado $expectExit)"
        if ($ok -and $c.Contains('expect_output') -and -not $out.Contains([string]$c['expect_output'])) {
            $ok = $false
            $why = "no aparece '$($c['expect_output'])' en la salida"
        }
        $tail = (($out -split "`r?`n") | Where-Object { $_ -ne '' } | Select-Object -Last 15) -join "`n"
        $status = 'fail'
        if ($ok) { $status = 'pass' }
        $results += [pscustomobject]@{ Name = $name; Status = $status; Detail = "$why`n$tail" }
    }
    $label = @{ pass = 'PASA'; fail = 'FALLA'; manual = 'MANUAL' }
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('# Verificacion ' + $Now.ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture))
    [void]$lines.Add('')
    if ($results.Count -eq 0) { [void]$lines.Add('Sin chequeos definidos en .team/verify.toml.') }
    [void]$lines.Add('| Chequeo | Resultado |')
    [void]$lines.Add('|---|---|')
    foreach ($r in $results) { [void]$lines.Add("| $($r.Name) | $($label[$r.Status]) |") }
    [void]$lines.Add('')
    [void]$lines.Add('## Detalle')
    foreach ($r in $results) {
        [void]$lines.Add('')
        [void]$lines.Add("### $($r.Name)")
        [void]$lines.Add('')
        [void]$lines.Add('```')
        [void]$lines.Add($r.Detail)
        [void]$lines.Add('```')
    }
    $dir = Join-Path $root 'brain\Verificaciones'
    $base = $Now.ToString('yyyy-MM-dd-HHmm', [System.Globalization.CultureInfo]::InvariantCulture) + '-verificacion'
    $note = Join-Path $dir "$base.md"
    $i = 2
    while (Test-Path -LiteralPath $note) { $note = Join-Path $dir "$base-$i.md"; $i++ }
    Write-TeamFile -Path $note -Content (($lines -join "`n") + "`n")
    return [pscustomobject]@{
        Passed   = @($results | Where-Object { $_.Status -eq 'pass' }).Count
        Failed   = @($results | Where-Object { $_.Status -eq 'fail' }).Count
        Manual   = @($results | Where-Object { $_.Status -eq 'manual' }).Count
        NotePath = $note
        Results  = $results
    }
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run.ps1`
Expected: PASS, `Failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add lib/Verify.ps1 tests/Verify.Tests.ps1
git -c user.name="jcgmU" -c user.email="jcgm1047@gmail.com" commit -m "feat: add verify runner that records results in the vault" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: CLI `team.ps1`

**Files:**
- Create: `team.ps1`, `tests/Cli.Tests.ps1`

**Interfaces:**
- Consumes: todas las funciones de las Tasks 1–7.
- Produces (contrato que usan los skills). Todos aceptan `--project "<ruta>"`; si falta, se usa `Find-TeamProjectRoot` desde la carpeta actual (excepto `init`, que usa la carpeta actual). Error → `ERROR: <mensaje>` en stderr y código 1.

| Comando | Opciones | Salida / código |
|---|---|---|
| `init` | `--name` | `OK brain: <ruta>` · 1 si ya existe |
| `agents` | `[--name]` | JSON `{Agents, UndetectedPanes}` con `Version`; `--name` asigna nombres faltantes |
| `finalize` | `--name --planner --executor [--central]` | JSON `{TeamConfig, CentralIndex}` |
| `set-role` | `--role planner\|executor --agent <nombre>` | `OK` |
| `docs` | — | regenera Protocolo, Comandos y punteros |
| `handoff` | `--from --to --type --thread [--round] [--criteria "a\|b"] [--refs "a\|b"] [--body \| --body-file] [--no-send]` | `ENTREGADO/CREADO/PARA_USUARIO: <ruta>` 0 · `NO_ENTREGADO` 4 · `BLOQUEO` 3 |
| `send-handoff` | `--file` | 0 entregado · 4 no entregado |
| `handoff-state` | `--file --state` | `OK` |
| `handoffs` | `[--open]` | JSON arreglo |
| `state` | `[--phase] [--round] [--turn] [--next] [--engram-pending] [--engram-saved]` | JSON estado |
| `checkpoint` | — | JSON estado |
| `doctor` | `[--skip-project]` | tabla; 1 si hay `[FAIL]` |
| `verify` | — | resumen; 0 todo pasa · 1 algún fallo · 2 sin chequeos |
| `version` | `--kind` | versión o vacío |

- [ ] **Step 1: Escribir el test que falla** — `tests/Cli.Tests.ps1`

```powershell
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here '..\lib\TeamKit.psm1') -Force
$cli = Join-Path $here '..\team.ps1'

function Invoke-Cli([string[]]$CliArgs) {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $cli @CliArgs 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}
function New-CliProject {
    $p = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Force -Path $p | Out-Null
    return $p
}

Describe 'team.ps1' {
    It 'init crea el vault y se niega la segunda vez' {
        $p = New-CliProject
        (Invoke-Cli @('init', '--project', $p, '--name', 'demo')).Code | Should Be 0
        Join-Path $p 'brain\Estado\STATE.md' | Should Exist
        $r = Invoke-Cli @('init', '--project', $p, '--name', 'demo')
        $r.Code | Should Be 1
        $r.Out | Should Match 'team-resume'
    }
    It 'state actualiza campos con valores con espacios' {
        $p = New-CliProject
        Invoke-Cli @('init', '--project', $p, '--name', 'demo') | Out-Null
        (Invoke-Cli @('state', '--project', $p, '--phase', 'probando', '--next', 'paso dos')).Code | Should Be 0
        $s = Read-TeamState -ProjectPath $p
        $s.fase | Should Be 'probando'
        $s.siguiente | Should Be 'paso dos'
    }
    It 'handoff --no-send crea el archivo y handoffs --open lo lista' {
        $p = New-CliProject
        Invoke-Cli @('init', '--project', $p, '--name', 'demo') | Out-Null
        $r = Invoke-Cli @('handoff', '--project', $p, '--from', 'kimi', '--to', 'agy', '--type', 'plan', '--thread', 'demo', '--criteria', 'a|b', '--body', 'hola equipo', '--no-send')
        $r.Code | Should Be 0
        $r.Out | Should Match 'CREADO:'
        $files = @(Get-ChildItem -LiteralPath (Join-Path $p 'brain\Handoffs') -Filter '*.md')
        $files.Count | Should Be 1
        (Read-HandoffFrontmatter -Path $files[0].FullName).para | Should Be 'agy'
        (Read-TeamFile $files[0].FullName) | Should Match '  - "b"'
        $list = (Invoke-Cli @('handoffs', '--project', $p, '--open')).Out | ConvertFrom-Json
        @($list).Count | Should Be 1
    }
    It 'el tercer hallazgo del mismo hilo genera un bloqueo para el usuario' {
        $p = New-CliProject
        Invoke-Cli @('init', '--project', $p, '--name', 'demo') | Out-Null
        foreach ($i in 1, 2) { (Invoke-Cli @('handoff', '--project', $p, '--from', 'claude', '--to', 'kimi', '--type', 'hallazgos', '--thread', 'login', '--no-send')).Code | Should Be 0 }
        $r = Invoke-Cli @('handoff', '--project', $p, '--from', 'claude', '--to', 'kimi', '--type', 'hallazgos', '--thread', 'login', '--no-send')
        $r.Code | Should Be 3
        $r.Out | Should Match 'BLOQUEO:'
        @(Get-TeamHandoffs -ProjectPath $p | Where-Object { $_.tipo -eq 'bloqueo' -and $_.para -eq 'usuario' }).Count | Should Be 1
        (Read-TeamState -ProjectPath $p).turno | Should Be 'usuario'
    }
    It 'verify sin chequeos sale con 2' {
        $p = New-CliProject
        Invoke-Cli @('init', '--project', $p, '--name', 'demo') | Out-Null
        (Invoke-Cli @('verify', '--project', $p)).Code | Should Be 2
    }
    It 'doctor fuera de Herdr sale con 1' {
        $prev = $env:HERDR_ENV
        $env:HERDR_ENV = ''
        try {
            $r = Invoke-Cli @('doctor', '--skip-project')
            $r.Code | Should Be 1
            $r.Out | Should Match 'herdr-env'
        } finally { $env:HERDR_ENV = $prev }
    }
    It 'un comando desconocido sale con 1' {
        $r = Invoke-Cli @('volar')
        $r.Code | Should Be 1
        $r.Out | Should Match 'Comando desconocido'
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Script tests\Cli.Tests.ps1"`
Expected: FAIL (no existe `team.ps1`).

- [ ] **Step 3: Implementar `team.ps1`** (sin bloque `param`: así PowerShell 5.1 entrega los `--opcion` como texto en `$args`)

```powershell
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\TeamKit.psm1') -Force

$Command = 'help'
if ($args.Count -gt 0) { $Command = [string]$args[0] }
$Rest = @()
if ($args.Count -gt 1) { $Rest = @($args[1..($args.Count - 1)] | ForEach-Object { [string]$_ }) }

function Get-CliOptions {
    param([string[]]$Tokens)
    $o = @{}
    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        $t = $Tokens[$i]
        if (-not $t.StartsWith('--')) { throw "Argumento inesperado: $t" }
        $key = $t.Substring(2)
        if ($i + 1 -lt $Tokens.Count -and -not $Tokens[$i + 1].StartsWith('--')) { $o[$key] = $Tokens[$i + 1]; $i++ }
        else { $o[$key] = $true }
    }
    return $o
}

function Split-CliList {
    param($Value)
    if (-not $Value -or $Value -eq $true) { return @() }
    return @(([string]$Value).Split('|') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-CliProject {
    param($Options)
    if ($Options['project']) { return Resolve-TeamPath ([string]$Options['project']) }
    return Find-TeamProjectRoot
}

function Get-RequiredOption {
    param($Options, [string]$Key)
    if (-not $Options[$Key] -or $Options[$Key] -eq $true) { throw "Falta --$Key" }
    return [string]$Options[$Key]
}

function Find-LiveAgent {
    param($Discovery, [string]$Name)
    $a = @($Discovery.Agents | Where-Object { $_.Name -eq $Name }) | Select-Object -First 1
    if (-not $a) { throw "No hay un agente llamado '$Name' en Herdr" }
    $a.Version = Get-AgentVersion -Kind $a.Kind
    return $a
}

$exitCode = 0
try {
    $o = Get-CliOptions $Rest
    switch ($Command) {
        'init' {
            $proj = (Get-Location).ProviderPath
            if ($o['project']) { $proj = Resolve-TeamPath ([string]$o['project']) }
            $brain = Initialize-TeamBrain -ProjectPath $proj -ProjectName (Get-RequiredOption $o 'name')
            Write-Output "OK brain: $brain"
        }
        'agents' {
            $d = Get-TeamAgents
            if ($o['name']) { $d = Set-TeamAgentNames -Discovery $d }
            foreach ($a in $d.Agents) { $a.Version = Get-AgentVersion -Kind $a.Kind }
            Write-Output ($d | ConvertTo-Json -Depth 5)
        }
        'finalize' {
            $proj = Get-CliProject $o
            $d = Get-TeamAgents
            $self = @($d.Agents | Where-Object { $_.IsSelf }) | Select-Object -First 1
            if (-not $self) { throw 'No se encontro el pane del orquestador (HERDR_PANE_ID)' }
            if (-not $self.Name) { throw 'El orquestador no tiene nombre en Herdr: corre primero team.ps1 agents --name' }
            $self.Version = Get-AgentVersion -Kind $self.Kind
            $central = [string]$o['central']
            if (-not $central) { $central = Get-TeamKitSetting -Key 'central_index_dir' }
            $res = Complete-TeamBootstrap -ProjectPath $proj -ProjectName (Get-RequiredOption $o 'name') -Orchestrator $self -Planner (Find-LiveAgent $d (Get-RequiredOption $o 'planner')) -Executor (Find-LiveAgent $d (Get-RequiredOption $o 'executor')) -CentralIndexDir $central
            Write-Output ($res | ConvertTo-Json)
        }
        'set-role' {
            $proj = Get-CliProject $o
            $agent = Find-LiveAgent (Get-TeamAgents -WorkspaceId '') (Get-RequiredOption $o 'agent')
            Set-TeamRole -ProjectPath $proj -Role (Get-RequiredOption $o 'role') -Agent $agent | Out-Null
            Write-Output 'OK'
        }
        'docs' {
            $proj = Get-CliProject $o
            Write-TeamDocs -ProjectPath $proj -Config (Read-TeamConfig -Path (Join-Path $proj '.team\team.toml'))
            Write-Output 'OK'
        }
        'handoff' {
            $proj = Get-CliProject $o
            $from = Get-RequiredOption $o 'from'
            $to = Get-RequiredOption $o 'to'
            $type = Get-RequiredOption $o 'type'
            $thread = Get-RequiredOption $o 'thread'
            $round = 1
            if ($o['round'] -and $o['round'] -ne $true) { $round = [int]$o['round'] }
            $body = ''
            if ($o['body-file'] -and $o['body-file'] -ne $true) { $body = Read-TeamFile ([string]$o['body-file']) }
            elseif ($o['body'] -and $o['body'] -ne $true) { $body = [string]$o['body'] }
            $path = New-TeamHandoff -ProjectPath $proj -From $from -To $to -Type $type -Thread $thread -Round $round -Criteria (Split-CliList $o['criteria']) -References (Split-CliList $o['refs']) -Body $body
            if ($type -eq 'hallazgos' -and (Get-ThreadRejectionCount -ProjectPath $proj -Thread $thread) -ge 3) {
                $b = New-TeamHandoff -ProjectPath $proj -From $from -To 'usuario' -Type 'bloqueo' -Thread $thread -Round $round -References @($path) -Body "El hilo $thread acumula 3 rechazos. Ultimos hallazgos en $path. El ciclo de este hilo queda en pausa hasta que el usuario decida."
                Update-TeamState -ProjectPath $proj -Turn 'usuario' -Next "Decidir como seguir con el hilo $thread (bloqueo)" | Out-Null
                Write-Output "BLOQUEO: $b"
                $exitCode = 3
            } elseif ($to -eq 'usuario') {
                Update-TeamState -ProjectPath $proj -Turn 'usuario' | Out-Null
                Write-Output "PARA_USUARIO: $path"
            } elseif ($o['no-send']) {
                Write-Output "CREADO: $path"
            } elseif (Send-TeamHandoff -Path $path) {
                Update-TeamState -ProjectPath $proj -Turn $to | Out-Null
                Write-Output "ENTREGADO: $path"
            } else {
                Write-Output "NO_ENTREGADO: $path"
                $exitCode = 4
            }
        }
        'send-handoff' {
            $proj = Get-CliProject $o
            $file = Resolve-TeamPath (Get-RequiredOption $o 'file')
            if (Send-TeamHandoff -Path $file) {
                Update-TeamState -ProjectPath $proj -Turn ([string](Read-HandoffFrontmatter -Path $file).para) | Out-Null
                Write-Output "ENTREGADO: $file"
            } else {
                Write-Output "NO_ENTREGADO: $file"
                $exitCode = 4
            }
        }
        'handoff-state' {
            Set-HandoffState -Path (Resolve-TeamPath (Get-RequiredOption $o 'file')) -State (Get-RequiredOption $o 'state')
            Write-Output 'OK'
        }
        'handoffs' {
            $proj = Get-CliProject $o
            $list = Get-TeamHandoffs -ProjectPath $proj -Open:([bool]$o['open'])
            Write-Output (ConvertTo-Json -InputObject @($list) -Depth 4)
        }
        'state' {
            $proj = Get-CliProject $o
            $p = @{ ProjectPath = $proj }
            if ($o['phase']) { $p['Phase'] = [string]$o['phase'] }
            if ($o['round']) { $p['Round'] = [string]$o['round'] }
            if ($o['turn']) { $p['Turn'] = [string]$o['turn'] }
            if ($o['next']) { $p['Next'] = [string]$o['next'] }
            if ($o['engram-pending']) { $p['EngramPending'] = $true }
            if ($o['engram-saved']) { $p['EngramSaved'] = $true }
            $s = Update-TeamState @p
            Write-Output ($s | ConvertTo-Json)
        }
        'checkpoint' {
            $proj = Get-CliProject $o
            Save-TeamCheckpoint -ProjectPath $proj | Out-Null
            Write-Output ((Read-TeamState -ProjectPath $proj) | ConvertTo-Json)
        }
        'doctor' {
            $skip = [bool]$o['skip-project']
            $proj = ''
            if (-not $skip) {
                try { $proj = Get-CliProject $o } catch { $skip = $true }
            }
            $r = Test-TeamHealth -ProjectPath $proj -SkipProject:$skip
            Write-Output (Format-TeamHealth -Results $r)
            if (@($r | Where-Object { $_.Status -eq 'fail' }).Count -gt 0) { $exitCode = 1 }
        }
        'verify' {
            $proj = Get-CliProject $o
            $v = Invoke-TeamVerify -ProjectPath $proj
            Write-Output "PASA: $($v.Passed)  FALLA: $($v.Failed)  MANUAL: $($v.Manual)"
            Write-Output "NOTA: $($v.NotePath)"
            if ($v.Failed -gt 0) { $exitCode = 1 }
            elseif (($v.Passed + $v.Manual) -eq 0) { $exitCode = 2 }
        }
        'version' {
            Write-Output (Get-AgentVersion -Kind (Get-RequiredOption $o 'kind'))
        }
        'help' {
            Write-Output 'Uso: team.ps1 <init|agents|finalize|set-role|docs|handoff|send-handoff|handoff-state|handoffs|state|checkpoint|doctor|verify|version> [--opcion valor ...]'
        }
        default { throw "Comando desconocido: $Command (usa team.ps1 help)" }
    }
} catch {
    [Console]::Error.WriteLine("ERROR: $($_.Exception.Message)")
    $exitCode = 1
}
exit $exitCode
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run.ps1`
Expected: PASS, `Failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add team.ps1 tests/Cli.Tests.ps1
git -c user.name="jcgmU" -c user.email="jcgm1047@gmail.com" commit -m "feat: add team.ps1 CLI" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Instalador y README

**Files:**
- Create: `install.ps1`, `tests/Install.Tests.ps1`, `README.md`
- Create (vacíos por ahora, para que el instalador tenga qué copiar): `skills/team-bootstrap/SKILL.md` con solo el frontmatter de la Task 10 — se completa en la Task 10.

**Interfaces:**
- Consumes: Task 1 (`Read-TeamConfig`, `Write-TeamConfig`).
- Produces: `install.ps1 [-AgentsHome <ruta>] [-ClaudeSkills <ruta>] [-CentralIndexDir <ruta>]`. Copia `lib`, `templates`, `team.ps1` a `<AgentsHome>\team-kit\`, escribe `<AgentsHome>\team-kit\config.toml` (`central_index_dir`), copia cada `skills\<x>` a `<AgentsHome>\skills\<x>` y crea la junction `<ClaudeSkills>\<x>` → `<AgentsHome>\skills\<x>`. Se niega a tocar `<ClaudeSkills>\<x>` si existe y no es junction.

- [ ] **Step 1: Crear el esqueleto de un skill para que el instalador tenga contenido**

`skills/team-bootstrap/SKILL.md` (temporal, la Task 10 lo reemplaza entero):
```markdown
---
name: team-bootstrap
description: Arma la base de un equipo de agentes coordinado por Herdr en la carpeta de un proyecto. Usar solo cuando el usuario invoca team-bootstrap.
---
```

- [ ] **Step 2: Escribir el test que falla** — `tests/Install.Tests.ps1`

```powershell
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here '..\lib\TeamKit.psm1') -Force
$install = Join-Path $here '..\install.ps1'

function Test-IsJunction([string]$Path) {
    return ((Get-Item -LiteralPath $Path -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
}

Describe 'install.ps1' {
    It 'instala runtime, skills y junctions, y es idempotente' {
        $agents = Join-Path $TestDrive 'home1\.agents'
        $claude = Join-Path $TestDrive 'home1\.claude\skills'
        & powershell -NoProfile -ExecutionPolicy Bypass -File $install -AgentsHome $agents -ClaudeSkills $claude -CentralIndexDir 'C:\Brain\03-Proyectos' | Out-Null
        $LASTEXITCODE | Should Be 0
        Join-Path $agents 'team-kit\team.ps1' | Should Exist
        Join-Path $agents 'team-kit\lib\TeamKit.psm1' | Should Exist
        Join-Path $agents 'team-kit\templates\Protocolo.md' | Should Exist
        Join-Path $agents 'skills\team-bootstrap\SKILL.md' | Should Exist
        $link = Join-Path $claude 'team-bootstrap'
        Test-IsJunction $link | Should Be $true
        Join-Path $link 'SKILL.md' | Should Exist
        Get-TeamKitSetting -Key 'central_index_dir' -ConfigPath (Join-Path $agents 'team-kit\config.toml') | Should Be 'C:\Brain\03-Proyectos'
        & powershell -NoProfile -ExecutionPolicy Bypass -File $install -AgentsHome $agents -ClaudeSkills $claude | Out-Null
        $LASTEXITCODE | Should Be 0
        Test-IsJunction $link | Should Be $true
        Get-TeamKitSetting -Key 'central_index_dir' -ConfigPath (Join-Path $agents 'team-kit\config.toml') | Should Be 'C:\Brain\03-Proyectos'
    }
    It 'no toca una carpeta real del usuario con el mismo nombre en .claude\skills' {
        $agents = Join-Path $TestDrive 'home2\.agents'
        $claude = Join-Path $TestDrive 'home2\.claude\skills'
        New-Item -ItemType Directory -Force -Path (Join-Path $claude 'team-bootstrap') | Out-Null
        Write-TeamFile -Path (Join-Path $claude 'team-bootstrap\mio.md') -Content 'no borrar'
        & powershell -NoProfile -ExecutionPolicy Bypass -File $install -AgentsHome $agents -ClaudeSkills $claude 2>&1 | Out-Null
        $LASTEXITCODE | Should Be 1
        Read-TeamFile (Join-Path $claude 'team-bootstrap\mio.md') | Should Be 'no borrar'
    }
}
```

- [ ] **Step 3: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Script tests\Install.Tests.ps1"`
Expected: FAIL (no existe `install.ps1`).

- [ ] **Step 4: Implementar `install.ps1`**

```powershell
param(
    [string]$AgentsHome = (Join-Path $HOME '.agents'),
    [string]$ClaudeSkills = (Join-Path $HOME '.claude\skills'),
    [string]$CentralIndexDir = ''
)
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
Import-Module (Join-Path $src 'lib\TeamKit.psm1') -Force

function Test-IsJunction([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return ((Get-Item -LiteralPath $Path -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
}
function Remove-Junction([string]$Path) {
    cmd /c rmdir "$Path" | Out-Null
    if (Test-Path -LiteralPath $Path) { throw "No se pudo quitar el enlace $Path" }
}

try {
    $kit = Join-Path $AgentsHome 'team-kit'
    $skillsDst = Join-Path $AgentsHome 'skills'
    New-Item -ItemType Directory -Force -Path $kit, $skillsDst, $ClaudeSkills | Out-Null

    foreach ($skill in (Get-ChildItem -LiteralPath (Join-Path $src 'skills') -Directory)) {
        $link = Join-Path $ClaudeSkills $skill.Name
        if ((Test-Path -LiteralPath $link) -and -not (Test-IsJunction $link)) {
            throw "$link existe y no es un enlace del kit: no lo toco. Muevelo y vuelve a instalar."
        }
    }

    foreach ($d in @('lib', 'templates')) {
        $dst = Join-Path $kit $d
        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
        Copy-Item -LiteralPath (Join-Path $src $d) -Destination $dst -Recurse
    }
    Copy-Item -LiteralPath (Join-Path $src 'team.ps1') -Destination (Join-Path $kit 'team.ps1') -Force

    $cfgPath = Join-Path $kit 'config.toml'
    $cfg = [ordered]@{}
    if (Test-Path -LiteralPath $cfgPath) { $cfg = Read-TeamConfig -Path $cfgPath }
    if ($CentralIndexDir) { $cfg['central_index_dir'] = $CentralIndexDir }
    Write-TeamConfig -Path $cfgPath -Data $cfg

    foreach ($skill in (Get-ChildItem -LiteralPath (Join-Path $src 'skills') -Directory)) {
        $dst = Join-Path $skillsDst $skill.Name
        $link = Join-Path $ClaudeSkills $skill.Name
        if (Test-IsJunction $link) { Remove-Junction $link }
        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
        Copy-Item -LiteralPath $skill.FullName -Destination $dst -Recurse
        New-Item -ItemType Junction -Path $link -Target $dst | Out-Null
    }
    Write-Output "agent-team-kit instalado en $kit"
    exit 0
} catch {
    [Console]::Error.WriteLine("ERROR: $($_.Exception.Message)")
    exit 1
}
```

- [ ] **Step 5: Escribir `README.md`**

````markdown
# agent-team-kit

Kit global para armar y retomar, en cualquier proyecto, un equipo de agentes coordinado por Herdr:
un planificador, un ejecutor y Claude como orquestador, con vault de Obsidian (`brain/`) y memoria engram.
Nada se ejecuta solo: todo empieza cuando invocas un skill.

## Instalar

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -CentralIndexDir "<carpeta de tu vault central para las notas índice>"
```

Instala el runtime en `~/.agents/team-kit`, los skills en `~/.agents/skills` (Kimi Code y Antigravity los leen ahí)
y crea enlaces en `~/.claude/skills` para Claude Code. Vuelve a correrlo después de cada cambio en el repo.

## Usar

- **Proyecto nuevo o sin equipo:** en Claude, invoca `team-bootstrap` dentro de la carpeta del proyecto.
- **Retomar:** en Claude, invoca `team-resume`.
- **Durante el trabajo (cualquier agente):** `team-handoff`, `team-verify`, `team-checkpoint`, `team-doctor`.

## Requisitos

- Herdr (los tres agentes en panes del mismo workspace).
- Windows PowerShell 5.1.
- engram configurado como MCP en todos los agentes, con el mismo `ENGRAM_DATA_DIR`.
- En Windows, Herdr no detecta agentes que corren como `node.exe`: ver `team-doctor`.

## Desarrollo

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run.ps1
```

Diseño: `docs/superpowers/specs/2026-10-11-agent-team-kit-design.md`.
````

- [ ] **Step 6: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run.ps1`
Expected: PASS, `Failed: 0`.

- [ ] **Step 7: Commit**

```bash
git add install.ps1 tests/Install.Tests.ps1 README.md skills/team-bootstrap/SKILL.md
git -c user.name="jcgmU" -c user.email="jcgm1047@gmail.com" commit -m "feat: add installer with junctions for Claude skills" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Skills `team-bootstrap` y `team-resume`

**Files:**
- Replace: `skills/team-bootstrap/SKILL.md`
- Create: `skills/team-resume/SKILL.md`

**Interfaces:**
- Consumes: CLI de la Task 8 (tabla de comandos y códigos de salida), comandos `herdr` (`agent prompt|wait|read|rename|start`, `pane split|read`).
- Produces: los dos skills que invoca el usuario.

- [ ] **Step 1: Escribir `skills/team-bootstrap/SKILL.md`**

````markdown
---
name: team-bootstrap
description: Arma la base de un equipo de agentes coordinado por Herdr en la carpeta de un proyecto - vault brain/, engram, fichas de capacidades, roles y protocolo. Usar SOLO cuando el usuario invoca team-bootstrap explicitamente. Solo lo ejecuta Claude como orquestador.
---

# team-bootstrap

Eres el **orquestador** (siempre Claude). Este skill crea la base del equipo en la carpeta de un proyecto. No escribe código del producto ni elige stack.

**CLI.** En los pasos, `TEAM` significa:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE\.agents\team-kit\team.ps1"
```

Desde Git Bash antepone `MSYS_NO_PATHCONV=1` si algún valor empieza con `/`. Todos los comandos llevan `--project "<ruta>"`.

## Pasos (en orden, sin saltarte ninguno)

### 1. Precondiciones
- `test "$HERDR_ENV" = 1`. Si falla: explica que hay que abrir esta sesión dentro de un pane de Herdr y **detente**.
- Confirma con el usuario la **ruta absoluta** del proyecto y un **nombre corto** (`minúsculas-y-guiones`).
- `TEAM init --project "<ruta>" --name <nombre>`. Si el error dice `team-resume`, el proyecto ya tiene equipo: **detente** y sugiere `team-resume`.

### 2. Descubrir el equipo
- `TEAM agents --name` → JSON con `Agents` (`Name`, `Kind`, `PaneId`, `Status`, `IsSelf`, `Version`, `Cwd`) y `UndetectedPanes`.
- Para cada pane de `UndetectedPanes`: `herdr pane read <PaneId> --source visible --lines 30`. Si ves la interfaz de un agente, dile al usuario que Herdr no lo detecta y que `team-doctor` explica cómo arreglarlo. No lo uses hasta que esté detectado.
- Si hay menos de dos agentes además de ti, explícalo y detente.

### 3. Salud
- `TEAM doctor --project "<ruta>" --skip-project`. Muéstrale al usuario la tabla con ✅ (`[OK]`), ⚠ (`[WARN]`) y ❌ (`[FAIL]`).
- Si hay ❌ en `engram`, pregunta si continuar igual.

### 4. Fichas autodeclaradas (todos los agentes menos tú, en paralelo)
- Para cada agente `<n>`, con su ruta absoluta `<F>` = `<ruta>\brain\Equipo\Fichas\<n>.md` y `<T>` = `<ruta>\brain\Equipo\Fichas\_plantilla-ficha.md`:

  ```
  herdr agent prompt <n> "Escribe tu ficha de capacidades en <F> siguiendo la plantilla <T>. Se honesto: si no tienes algo, dilo. Incluye como se invocan exactamente tus subagentes o tu modo multi-agente. Al terminar responde solo FICHA LISTA." --wait --until working --until done --until blocked --timeout 15000
  ```

  El texto del prompt **no** puede llevar comillas dobles dentro.
- Después, por cada agente: `herdr agent wait <n> --timeout 300000`.
- Si un agente queda `blocked`: `herdr agent read <n> --source visible --lines 40`, muéstrale el diálogo al usuario y pregúntale qué responder. **Nunca** lo respondas tú.
- Si a los 5 minutos no existe `<F>`: créalo con el frontmatter de la plantilla y `estado: sin-respuesta`, y sigue.
- Escribe tu propia ficha en `<ruta>\brain\Equipo\Fichas\<tu-nombre>.md` con la misma plantilla.

### 5. Verificación cruzada
En cada ficha completa la tabla "Verificación del orquestador":
- **Versión:** `TEAM version --kind <Kind>`.
- **Detección en Herdr** y **Engram:** de la tabla del paso 3.
- **Rutas de skills:** comprueba con `ls` que existan las carpetas que declaró.

Marca cada dato ✅ verificado, ⚠ declarado (no verificable) o ❌ contradicho.

### 6. Roles
Muestra los agentes detectados (nombre, tipo, versión) y pregunta con AskUserQuestion, en una sola llamada con dos preguntas:
- "¿Quién será el planificador?"
- "¿Quién será el ejecutor?"

Tienen que ser distintos entre sí y distintos de ti: tú eres siempre el orquestador. No sugieras uno por defecto.

### 7. Generar la base
- `TEAM finalize --project "<ruta>" --name <nombre> --planner <p> --executor <e>`.
- engram: `mem_save` con `project: <nombre>`, título `Bootstrap del equipo <nombre>`, y en el contenido los roles, los agentes y sus versiones. Si falla: `TEAM state --project "<ruta>" --engram-pending`.
- Avisa a cada agente:

  ```
  herdr agent prompt <n> "Eres el <planificador|ejecutor> del proyecto <nombre>. Lee <ruta>\brain\Equipo\Protocolo.md, <ruta>\brain\Equipo\Comandos.md y las fichas de <ruta>\brain\Equipo\Fichas. Responde solo PROTOCOLO LEIDO." --wait --timeout 300000
  ```

  Luego confirma la respuesta con `herdr agent read <n> --source recent-unwrapped --lines 20`.
- `TEAM checkpoint --project "<ruta>"`.
- Repórtale al usuario:
  - que abra `<ruta>\brain` en Obsidian con "Abrir carpeta como vault";
  - la ruta del índice central (o que no se creó por falta de `central_index_dir`);
  - el resultado del doctor;
  - que el siguiente paso es contarte el primer objetivo (si no hay stack, el primer hilo es `stack`).
- Pregunta si hacer commit. **No** lo hagas sin permiso.

## Reglas
- Nunca uses nombres de agentes fijos: todo sale de `TEAM agents` y de lo que responda el usuario.
- No elijas stack ni escribas código del producto.
- Nunca cierres panes ni mates procesos que no creaste.
````

- [ ] **Step 2: Escribir `skills/team-resume/SKILL.md`**

````markdown
---
name: team-resume
description: Retoma un proyecto que ya tiene equipo de agentes (brain/ y .team/team.toml) - carga el contexto desde el vault de Obsidian y engram, revisa que el planificador y el ejecutor sigan en Herdr y reanuda el ciclo donde quedo. Usar SOLO cuando el usuario invoca team-resume. Solo lo ejecuta Claude como orquestador.
---

# team-resume

Eres el **orquestador** (siempre Claude). `TEAM` = `powershell -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE\.agents\team-kit\team.ps1"`. Desde Git Bash antepone `MSYS_NO_PATHCONV=1` si algún valor empieza con `/`.

## Pasos

### 1. Precondiciones
- `test "$HERDR_ENV" = 1`. Si falla: explica que hay que abrir la sesión dentro de Herdr y **detente**.
- Ruta del proyecto: la que diga el usuario o la carpeta actual. Comprueba que exista `<ruta>\.team\team.toml`. Si no existe: **detente** y sugiere `team-bootstrap`.

### 2. Cargar contexto
- Lee `brain\00-Inicio.md`, `brain\Equipo\Protocolo.md`, `brain\Equipo\Comandos.md`, `brain\Estado\STATE.md` y `.team\team.toml`.
- `TEAM handoffs --project "<ruta>" --open` y lee cada handoff abierto completo.
- Lee la nota más reciente de `brain\Verificaciones\` (por nombre de archivo).
- engram: `mem_context` y `mem_search` (consulta = la fase y los hilos abiertos), siempre con `project` = `engram_project` de `team.toml`.
- Si `STATE.md` tiene `engram_pendiente: si`: guarda ahora con `mem_save` el resumen que quedó pendiente y corre `TEAM state --project "<ruta>" --engram-saved`.

### 3. Salud y equipo
Corre `TEAM doctor --project "<ruta>"` y actúa según cada fila:
- **`rol-*` en `[WARN]`** (mismo tipo de agente, otro nombre): ejecuta el arreglo que indica la fila (`herdr agent rename <pane> <nombre>`).
- **`rol-*` en `[FAIL]`** (no está): pregúntale al usuario si lo lanzas o si prefiere asignar otro agente.
  - **Lanzar:** `herdr pane split --current --direction right --cwd "<ruta>" --no-focus` → anota `.result.pane.pane_id`. Si `team.toml` tiene `last_session_id` para ese rol, ofrécele reanudar esa sesión:
    - `kimi`: `herdr agent start <nombre> --kind kimi --pane <id> -- --session <last_session_id>`
    - `agy`: `herdr agent start <nombre> --kind agy --pane <id> -- --conversation <last_session_id>`
    - `claude`: `herdr agent start <nombre> --kind claude --pane <id> -- --resume <last_session_id>`
    - Otro tipo, o sin sesión: `herdr agent start <nombre> --kind <kind> --pane <id>`; si no conoces el flag para reanudar, pregúntale al usuario.
    - Si el arranque queda `blocked` (por ejemplo "Trust this folder"), muéstraselo al usuario y pregúntale. Nunca lo apruebes tú.
  - **Asignar otro:** `TEAM set-role --project "<ruta>" --role <planner|executor> --agent <nombre>`, y después genera su ficha como en el paso 4 de `team-bootstrap`.
- **`version-*` en `[WARN]`:** regenera solo la ficha de ese agente (prompt del paso 4 de `team-bootstrap`, más tu verificación cruzada) y corre `TEAM set-role --project "<ruta>" --role <rol> --agent <nombre>` para registrar la versión nueva.
- **Cualquier otro `[FAIL]`:** muéstraselo al usuario con su arreglo y pregunta si seguir.

### 4. Poner al día a los agentes
- A cada agente:

  ```
  herdr agent prompt <n> "Retomamos el proyecto <nombre>. Lee <ruta>\brain\Estado\STATE.md y tus handoffs abiertos en <ruta>\brain\Handoffs (los que tienen para: <n> y estado pendiente, en-curso o no-entregado). Responde solo LISTO." --wait --timeout 300000
  ```

- Por cada handoff con `estado: no-entregado`: `TEAM send-handoff --project "<ruta>" --file "<ruta del handoff>"`.

### 5. Reporte y continuar
- Reporte breve al usuario: fase, ronda, quién tiene el turno, el siguiente paso, los hilos abiertos y el resultado del doctor.
- Si el turno es tuyo, sigue el Protocolo. Si es de otro agente, espera su handoff.
- Al terminar: `team-checkpoint`.

## Reglas
- `team.toml` manda: no cambies roles sin que el usuario lo pida.
- Nunca cierres panes ni mates procesos que no creaste.
````

- [ ] **Step 3: Revisar cada skill con un subagente nuevo (prueba de comportamiento)**

Despacha un subagente `general-purpose` nuevo por skill. Dale solo el texto del `SKILL.md` y estos escenarios. Pídele la lista exacta de comandos que ejecutaría, en orden, sin ejecutar nada:

- `team-bootstrap`, escenario A: "HERDR_ENV=1, proyecto `C:\x\demo` sin `brain`, agentes en Herdr: tú (claude), `kimi`, `agy`". Esperado: init → agents → doctor → prompts de ficha + waits → verificación cruzada → AskUserQuestion con dos preguntas → finalize → mem_save → avisos → checkpoint. Sin commit.
- `team-bootstrap`, escenario B: "`brain` ya existe". Esperado: se detiene y sugiere `team-resume` justo después de `init`.
- `team-resume`, escenario C: "el doctor muestra `rol-executor [FAIL]`, `team.toml` tiene `kind = agy` y `last_session_id = abc`". Esperado: pregunta al usuario y, si autoriza, `pane split` + `agent start ... --kind agy ... -- --conversation abc`.

Si un paso falta o aparece desordenado, corrige el `SKILL.md` y repite el escenario.

- [ ] **Step 4: Commit**

```bash
git add skills/team-bootstrap/SKILL.md skills/team-resume/SKILL.md
git -c user.name="jcgmU" -c user.email="jcgm1047@gmail.com" commit -m "feat: add team-bootstrap and team-resume skills" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Skills `team-handoff`, `team-verify`, `team-checkpoint`, `team-doctor`

**Files:**
- Create: `skills/team-handoff/SKILL.md`, `skills/team-verify/SKILL.md`, `skills/team-checkpoint/SKILL.md`, `skills/team-doctor/SKILL.md`

**Interfaces:**
- Consumes: CLI de la Task 8.
- Produces: skills que usan los tres agentes. Deben funcionar en Claude Code, Kimi Code y Antigravity CLI, así que el texto no puede depender de herramientas propias de Claude, salvo donde se indique "si eres Claude".

- [ ] **Step 1: Escribir `skills/team-handoff/SKILL.md`**

````markdown
---
name: team-handoff
description: Crea y entrega un handoff (traspaso de trabajo) a otro agente del equipo en un proyecto con brain/ y .team/team.toml. Usalo cada vez que termines tu parte del ciclo, abras un objetivo o devuelvas hallazgos. Nunca pases trabajo solo por texto en la terminal.
---

# team-handoff

`TEAM` = `powershell -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE\.agents\team-kit\team.ps1"` (en Windows `%USERPROFILE%`). Desde Git Bash antepone `MSYS_NO_PATHCONV=1` si algún valor empieza con `/`.

## Quién eres
Busca tu nombre de Herdr en `<ruta>\.team\team.toml`: `[orchestrator]`, `[roles.planner]` o `[roles.executor]`.

## Qué puedes enviar (ver `brain\Equipo\Comandos.md`)
| Tu rol | Para | Tipos |
|---|---|---|
| orquestador | planificador | `objetivo`, `hallazgos` |
| orquestador | `usuario` | `aprobado`, `bloqueo` |
| planificador | ejecutor | `plan` |
| planificador | orquestador | `listo-para-verificar` |
| planificador | `usuario` | `bloqueo` |
| ejecutor | planificador | `ejecucion` |

## Pasos
1. Escribe el cuerpo en un archivo `.md` temporal:
   - qué se pide o qué se hizo;
   - archivos tocados;
   - cómo verificarlo;
   - si quieres que el destinatario use sus subagentes o su modo multi-agente, revisa su ficha (`brain\Equipo\Fichas\<destinatario>.md`) y nombra la capacidad exacta.
2. Elige `hilo` (un slug estable del tema, ej. `login-form`) y `ronda` (1 + cuántos handoffs del mismo hilo y tipo ya existen; revísalo con `TEAM handoffs --project "<ruta>"`).
3. Ejecuta:

   ```
   TEAM handoff --project "<ruta>" --from <tu-nombre> --to <destinatario|usuario> --type <tipo> --thread <hilo> --round <n> --criteria "criterio 1|criterio 2" --refs "ruta1|ruta2" --body-file "<archivo.md>"
   ```

4. Lee el código de salida:
   - **0** (`ENTREGADO`): el destinatario ya está trabajando.
   - **0** (`PARA_USUARIO`): si eres el orquestador, preséntaselo al usuario. Si no lo eres, el orquestador lo verá.
   - **3** (`BLOQUEO`): el hilo acumuló 3 rechazos. Detente: el orquestador se lo informa al usuario.
   - **4** (`NO_ENTREGADO`): el destinatario no respondió tras un reintento. Si eres el orquestador, avísale al usuario. Si no, déjalo así: `team-doctor` lo mostrará.

## Al recibir un handoff
1. Léelo completo.
2. Haz el trabajo.
3. Márcalo con `TEAM handoff-state --file "<ruta del handoff>" --state hecho`.
4. Responde con tu propio handoff según el Protocolo.
````

- [ ] **Step 2: Escribir `skills/team-verify/SKILL.md`**

````markdown
---
name: team-verify
description: Verificacion del trabajo del equipo con los chequeos de .team/verify.toml. El orquestador la ejecuta tras un handoff listo-para-verificar; el planificador mantiene verify.toml cuando el stack esta decidido.
---

# team-verify

`TEAM` = `powershell -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE\.agents\team-kit\team.ps1"`.

## Si eres el planificador
Cuando el stack esté decidido, mantén `.team\verify.toml` (el formato está en su encabezado):
- solo bloques `[[check]]`, con las claves `name`, `run`, `expect_exit`, `expect_output` y `manual`;
- textos entre comillas; rutas de Windows con comillas simples;
- sin tablas inline ni textos multilínea.

Incluye siempre los tests, el build y al menos un chequeo `manual` de la experiencia real (UI, API o CLI) cuando aplique.

## Si eres el orquestador
1. Tras recibir `listo-para-verificar`, corre `TEAM verify --project "<ruta>"`.
   - **Exit 2** (sin chequeos): manda un handoff `hallazgos` al planificador pidiéndole que defina `verify.toml`.
2. Para cada chequeo `MANUAL`, hazlo **tú de verdad**. Por ejemplo, una UI se prueba en el navegador. Anota el resultado y la evidencia en la sección "Detalle" de la nota de verificación generada.
3. Nunca des por bueno un reporte de otro agente sin volver a ejecutarlo.
4. Según el resultado:
   - **Todo pasa:** handoff `aprobado` a `usuario` y reporte al usuario.
   - **Algo falla:** handoff `hallazgos` al planificador, con la ruta de la nota y la evidencia.
````

- [ ] **Step 3: Escribir `skills/team-checkpoint/SKILL.md`**

````markdown
---
name: team-checkpoint
description: Guarda el punto de control del proyecto del equipo - estado en brain/Estado/STATE.md, ids de sesion de los agentes en .team/team.toml y resumen de sesion en engram. El orquestador lo usa en cada transicion del ciclo y todos los agentes antes de cerrar sesion.
---

# team-checkpoint

`TEAM` = `powershell -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE\.agents\team-kit\team.ps1"`.

## Pasos
1. `TEAM checkpoint --project "<ruta>"`: guarda los IDs de sesión de Herdr y la fecha.
2. Actualiza solo los campos que cambiaron:

   ```
   TEAM state --project "<ruta>" --phase <fase> --round <n> --turn <quien> --next "<siguiente paso>"
   ```

3. engram: guarda el resumen de sesión (`mem_session_summary` o la herramienta equivalente de tu agente) con estas secciones: Goal, Discoveries, Accomplished, Next Steps, Relevant Files. Usa el proyecto `engram_project` de `.team\team.toml` (pásalo en el parámetro `project` si tu herramienta lo admite).
   - Si falla: `TEAM state --project "<ruta>" --engram-pending`.
   - Si estaba pendiente y ahora funciona: guarda y corre `TEAM state --project "<ruta>" --engram-saved`.

## Cuándo usarlo
- **Orquestador:** cada vez que el ciclo cambia de manos.
- **Todos los agentes:** antes de cerrar la sesión.
````

- [ ] **Step 4: Escribir `skills/team-doctor/SKILL.md`**

````markdown
---
name: team-doctor
description: Revisa la salud del equipo de agentes - deteccion en Herdr, integraciones, engram compartido, vault, punteros, roles, versiones y handoffs - y explica como arreglar cada problema.
---

# team-doctor

`TEAM` = `powershell -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE\.agents\team-kit\team.ps1"`.

## Pasos
1. Corre `TEAM doctor --project "<ruta>"`, o `TEAM doctor --skip-project` si todavía no hay proyecto.
2. Muestra la tabla con ✅ (`[OK]`), ⚠ (`[WARN]`) y ❌ (`[FAIL]`), y para cada fila que no esté OK explica el arreglo que indica (`->`).
3. No apliques arreglos que toquen la configuración del usuario o de otros agentes sin preguntarle antes.

## Arreglos frecuentes
- **`deteccion` [WARN] en Windows:** Herdr no ve agentes que corren como `node.exe`.
  1. Busca el alias del agente en `%LOCALAPPDATA%\herdr\agent-detection\remote\<kind>.toml` (campo `aliases`).
  2. Crea una copia de `node.exe` con ese nombre (ej. `kimi-code.exe`).
  3. Lanza el agente desde esa copia con una función en el perfil de PowerShell:

     ```powershell
     function <comando> {
         $node = (Get-Command node.exe).Source
         $launcher = "$env:USERPROFILE\.<agente>\launcher\<alias>.exe"
         if (-not (Test-Path $launcher) -or (Get-Item $node).LastWriteTime -ne (Get-Item $launcher).LastWriteTime) {
             New-Item -ItemType Directory -Force -Path (Split-Path $launcher) | Out-Null
             Copy-Item $node $launcher -Force
         }
         & $launcher "<ruta al main.mjs del paquete npm>" @args
     }
     ```

  4. Los panes ya abiertos necesitan `. $PROFILE`.
- **`engram` [FAIL] "bases distintas":** todos los agentes deben apuntar al mismo `ENGRAM_DATA_DIR`. Lo recomendado es `~/.engram`, fuera de cualquier proyecto. Los archivos que hay que editar son `~/.claude.json`, `~/.kimi-code/mcp.json` y `~/.gemini/config/mcp_config.json`. **Pregunta antes de editarlos.**
- **`integracion` [WARN]:** `herdr integration install <nombre>`.
- **`vault` / `punteros`:** `TEAM docs --project "<ruta>"` regenera Protocolo, Comandos y punteros. Lo demás se restaura desde git.
- **`rol-*` / `version-*`:** usa `team-resume`, que sabe relanzar o reasignar.
- **`handoffs`:** `TEAM send-handoff --project "<ruta>" --file "<handoff>"`, o ciérralo con `TEAM handoff-state --file "<handoff>" --state cerrado`.
````

- [ ] **Step 5: Revisar con un subagente nuevo**

Despacha un subagente `general-purpose` nuevo con el texto de `team-handoff` y este escenario: "eres el ejecutor `agy` del proyecto `C:\x\demo`; terminaste el hilo `login` ronda 1". Esperado: escribe el cuerpo en un archivo, usa `--type ejecucion --to <planificador según team.toml> --thread login --round 1 --body-file`, interpreta el código de salida y no manda el trabajo solo por texto. Si se desvía, corrige el skill y repite.

- [ ] **Step 6: Commit**

```bash
git add skills
git -c user.name="jcgmU" -c user.email="jcgm1047@gmail.com" commit -m "feat: add handoff, verify, checkpoint and doctor skills" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Instalación real y prueba de aceptación E2E

**Files:**
- Ninguno en el repo. Esta tarea instala el kit y prueba en una carpeta descartable. Al final se borran la carpeta, los panes de prueba y la nota índice de prueba.

**Interfaces:**
- Consumes: todo lo anterior.

- [ ] **Step 1: Suite completa en verde**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run.ps1`
Expected: PASS, `Failed: 0`.

- [ ] **Step 2: Instalar**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -CentralIndexDir "C:\Users\jcgm1\OneDrive\Desktop\Devia\DevIA-Brain\03-Proyectos"`
Expected: `agent-team-kit instalado en C:\Users\jcgm1\.agents\team-kit`. `~/.claude/skills/team-bootstrap` es una junction.

- [ ] **Step 3: Comprobar el descubrimiento de skills en Kimi (riesgo de duplicados del spec)**

Pídele al agente `kimi` existente, con `herdr agent prompt kimi "Lista solo los nombres de tus skills que empiecen con team-, uno por linea, y nada mas." --wait --timeout 120000`, y lee la respuesta con `herdr agent read kimi --source recent-unwrapped --lines 30`. Expected: cada `team-*` aparece **una sola vez**. Si aparece duplicado, anótalo y avísale al usuario antes de seguir; no improvises un arreglo.

- [ ] **Step 4: Preparar la carpeta y los agentes de prueba**

```bash
mkdir -p /c/Users/jcgm1/team-sandbox
herdr pane split --current --direction right --cwd "C:\\Users\\jcgm1\\team-sandbox" --no-focus   # anotar pane A
herdr pane split <pane A> --direction down --cwd "C:\\Users\\jcgm1\\team-sandbox" --no-focus      # anotar pane B
herdr pane run <pane A> '. $PROFILE'
herdr agent start kimi-sb --kind kimi --pane <pane A>
herdr agent start agy-sb --kind agy --pane <pane B>
```

Si un arranque queda `blocked` por confiar en la carpeta, muéstraselo al usuario y, con su sí, envía `herdr agent send-keys <nombre> enter`.

- [ ] **Step 5: Bootstrap**

Invoca el skill `team-bootstrap` sobre `C:\Users\jcgm1\team-sandbox` con el nombre `team-sandbox`. Cuando pregunte los roles, elige **planificador = `kimi-sb`** y **ejecutor = `agy-sb`**.

Expected:
- existen `brain\Equipo\Fichas\kimi-sb.md`, `agy-sb.md` y la ficha de Claude, cada una con la tabla de verificación completa;
- `.team\team.toml` tiene esos roles;
- `CLAUDE.md`, `AGENTS.md` y `GEMINI.md` tienen el bloque del equipo;
- existe `DevIA-Brain\03-Proyectos\PRJ-team-sandbox.md`;
- `STATE.md` dice `fase: equipo-listo`;
- `TEAM doctor --project "C:\Users\jcgm1\team-sandbox"` no muestra ningún `[FAIL]` atribuible al kit. Los `[WARN]`/`[FAIL]` de engram por la ruta no estándar se anotan, pero no bloquean.

- [ ] **Step 6: Ciclo mínimo**

1. Abre el ciclo con un `objetivo` al planificador:

   ```
   TEAM handoff --project "C:\Users\jcgm1\team-sandbox" --from <tu nombre> --to kimi-sb --type objetivo --thread hola --criteria "existe hola.txt|contiene hola equipo" --body "Crear hola.txt en la raiz con el texto: hola equipo. Stack: no aplica, es una prueba del flujo."
   ```

2. Espera sin intervenir. Expected:
   - `kimi-sb` manda un `plan` a `agy-sb`;
   - `agy-sb` crea `hola.txt` y manda `ejecucion`;
   - `kimi-sb` revisa y te manda `listo-para-verificar`, que te llega como prompt en tu pane.
3. Verifica: agrega a `.team\verify.toml` un check `run = "if ((Get-Content hola.txt -Raw).Trim() -ne 'hola equipo') { exit 1 }"` (o pídeselo al planificador) y corre `TEAM verify`. Expected: `PASA` ≥ 1, `FALLA: 0`.
4. Manda `aprobado` a `usuario`.

Expected:
- `brain\Handoffs\` tiene la secuencia `objetivo → plan → ejecucion → listo-para-verificar → aprobado`;
- ningún archivo quedó en `no-entregado`;
- `STATE.md` tiene `turno: usuario`.

- [ ] **Step 7: Retomar después de cerrar**

1. Sal de `kimi-sb` y `agy-sb` (con `MSYS_NO_PATHCONV=1 herdr pane send-text <pane> "/exit"` y `enter`) y cierra los panes A y B, que creaste tú.
2. Crea a mano un handoff con estado `no-entregado`:

   ```
   TEAM handoff --project "C:\Users\jcgm1\team-sandbox" --from kimi-sb --to agy-sb --type plan --thread pendiente --body "prueba de reenvio" --no-send
   ```

   y luego `TEAM handoff-state --file <ese archivo> --state no-entregado`.
3. Invoca `team-resume` sobre la carpeta de prueba. Expected:
   - el doctor muestra `rol-planner` y `rol-executor` en `[FAIL]`;
   - el skill pregunta, relanza cada agente en panes nuevos ofreciendo su `last_session_id`, y los pone al día;
   - reenvía el handoff `no-entregado`, que pasa a `en-curso`;
   - el reporte final muestra la fase y el turno correctos.

- [ ] **Step 8: Limpieza**

Sal de los agentes de prueba y cierra **solo** los panes que creaste. Pídele al usuario confirmación antes de borrar:
- `C:\Users\jcgm1\team-sandbox`;
- `C:\Users\jcgm1\OneDrive\Desktop\Devia\DevIA-Brain\03-Proyectos\PRJ-team-sandbox.md`.

Las memorias de engram del proyecto `team-sandbox` se quedan.

- [ ] **Step 9: Registrar el resultado**

Agrega al `README.md` una sección "Probado" con la fecha, las versiones (Herdr, Claude, Kimi, Agy) y cualquier limitación encontrada en los pasos 3, 5 y 7. Commit:

```bash
git add README.md
git -c user.name="jcgmU" -c user.email="jcgm1047@gmail.com" commit -m "docs: record end-to-end acceptance results" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
