# agent-team-kit

Dos skills para que **tres agentes de IA trabajen como un equipo** en cualquier proyecto, coordinados por [Herdr](https://github.com/ogulcancelik/herdr):

| Rol | Quién | Qué hace |
|---|---|---|
| **Orquestador** | Siempre Claude Code | Recibe tus objetivos, coordina, verifica de verdad y te reporta. No corrige código. |
| **Planificador** | El agente que elijas (ej. Kimi Code) | Convierte objetivos en planes multi-agente, por oleadas, con criterios de aceptación. |
| **Ejecutor** | El agente que elijas (ej. Antigravity CLI) | Ejecuta el plan con sus propios subagentes, en paralelo. |

Cada proyecto recibe un **segundo cerebro**: un vault de Obsidian (`brain/`) y memoria persistente en **engram**. Así puedes cerrar todo y retomar exactamente donde quedaste, sin repetir instrucciones.

| Skill | Cuándo se usa |
|---|---|
| `team-bootstrap` | **Una vez por proyecto.** Detecta los agentes, les pide que describan sus capacidades, te pregunta quién planifica y quién ejecuta, y crea toda la base. |
| `team-resume` | **Cada vez que vuelves al proyecto.** Carga el vault y engram, revisa que los agentes sigan vivos (o los relanza) y continúa el ciclo. |

Ninguna de las dos se ejecuta sola: solo corren cuando tú las invocas.

---

## 1. Requisitos

| Requisito | Para qué | Comprobar |
|---|---|---|
| **Herdr** (probado con 0.8.2) | Multiplexor de terminal: los agentes viven en sus panes y se envían mensajes entre ellos | `herdr --version` |
| **Claude Code** | El orquestador. Las skills se invocan desde aquí | `claude --version` |
| **Al menos 2 agentes CLI más** que Herdr reconozca (Kimi Code, Antigravity CLI, Codex, Gemini CLI, OpenCode, …) | Planificador y ejecutor | `herdr agent` (al final aparece la lista de tipos soportados) |
| **engram** configurado como servidor MCP en **los tres** agentes, con el **mismo** `ENGRAM_DATA_DIR` | Memoria compartida entre sesiones y agentes | ver [Solución de problemas](#7-solución-de-problemas) |
| **Obsidian** (opcional) | Ver y editar el vault `brain/` de cada proyecto | — |
| **git** | Clonar este repo | `git --version` |

Sistemas: **Windows** (probado, con PowerShell 5.1), macOS y Linux (instalador `install.sh`).

---

## 2. Instalación

```bash
git clone https://github.com/jcgmU/agent-team-kit.git
cd agent-team-kit
```

**Windows (PowerShell):**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

**macOS / Linux:**
```bash
bash install.sh
```

### Qué hace el instalador

1. Copia cada carpeta de `skills/` a `~/.agents/skills/<skill>`.
2. Crea un enlace `~/.claude/skills/<skill>` → `~/.agents/skills/<skill>`, para que Claude Code las vea.
3. Si en `~/.claude/skills` ya existe una carpeta real (no un enlace) con el mismo nombre, se detiene sin tocarla.

### Qué agente lee cada carpeta

| Agente | Carpeta de skills |
|---|---|
| Claude Code | `~/.claude/skills` (por eso el enlace) |
| Kimi Code | `~/.agents/skills` (también lee `~/.claude/skills`) |
| Antigravity CLI | `~/.gemini/skills`. Si no es un enlace a `~/.agents/skills`, créalo: Windows `mklink /J %USERPROFILE%\.gemini\skills %USERPROFILE%\.agents\skills`; macOS/Linux `ln -s ~/.agents/skills ~/.gemini/skills` |
| Otros | Consulta su documentación y copia o enlaza `~/.agents/skills/team-*` ahí |

Planificador y ejecutor no necesitan invocar las skills: siguen el **Protocolo** que `team-bootstrap` escribe en cada proyecto. Las skills solo las ejecuta Claude.

### Configuración opcional: índice central

Si tienes un vault central de Obsidian (tu "segundo cerebro" global), `team-bootstrap` puede dejar en él una nota índice por proyecto. Crea `~/.agents/team-kit.toml`:

```toml
central_index_dir = 'C:\ruta\a\tu\vault\Proyectos'
```

Si no existe, la skill te pregunta la carpeta la primera vez y la guarda.

### Verificar la instalación

- `ls ~/.claude/skills/team-bootstrap/SKILL.md` y `ls ~/.agents/skills/team-resume/SKILL.md` existen.
- Abre Claude Code: `team-bootstrap` y `team-resume` aparecen en la lista de skills (o escribe `/team` y deben autocompletarse).

---

## 3. Preparar la sesión de trabajo

1. Abre **Herdr**.
2. En un mismo workspace, abre **tres panes** en la carpeta del proyecto:
   - uno con **Claude Code** (`claude`);
   - uno con el agente que será **planificador** (ej. `kimi`);
   - uno con el agente que será **ejecutor** (ej. `agy`).
3. Comprueba que Herdr los detecta: `herdr agent list` debe mostrar los tres con su tipo. Si alguno no aparece, ve a [Solución de problemas](#7-solución-de-problemas).

---

## 4. Usar `team-bootstrap` (una vez por proyecto)

En el pane de Claude Code escribe:

```
/team-bootstrap
```

Claude hará, en orden:

| Paso | Qué pasa | Te pregunta |
|---|---|---|
| 1 | Comprueba que corre dentro de Herdr y que el proyecto aún no tiene `brain/` | Ruta del proyecto y nombre corto |
| 2 | Descubre los agentes en Herdr, les asigna nombres estables y revisa los panes sin agente detectado | — |
| 3 | **Revisión de salud**: detección, hooks de integración de Herdr y engram compartido. Te muestra una tabla ✅ / ⚠ / ❌ | Si sigue a pesar de un ❌ |
| 4 | Pide a cada agente su **ficha de capacidades**: herramientas, subagentes, modelos por nivel, comandos `/`, skills y plugins. Luego la verifica | Si un agente queda bloqueado en un diálogo |
| 5 | Muestra los agentes detectados | **¿Quién planifica? ¿Quién ejecuta?** |
| 6 | Crea `brain/`, `.team/team.toml`, los punteros en `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` y la nota índice | Carpeta del índice central (solo la primera vez) |
| 7 | Guarda el arranque en engram, informa a cada agente de su rol y te deja un resumen | Si hacer commit |

### Lo que queda en el proyecto

```
<proyecto>/
  brain/                         ← ábrelo en Obsidian: "Abrir carpeta como vault"
    00-Inicio.md                 ← mapa del vault
    Equipo/Protocolo.md          ← reglas del equipo (lo leen los tres agentes)
    Equipo/Comandos.md           ← quién puede pedirle qué a quién
    Equipo/Verificacion.md       ← chequeos que corre el orquestador
    Equipo/Fichas/<agente>.md    ← capacidades de cada agente (✅ verificado / ⚠ declarado / ❌ contradicho)
    Estado/STATE.md              ← fase, ronda, quién tiene el turno, siguiente paso
    Handoffs/                    ← un archivo por cada traspaso de trabajo
    Decisiones/                  ← ADRs
    Verificaciones/              ← resultados de cada verificación
  .team/team.toml                ← roles → agentes, versiones, sesiones, proyecto engram
  CLAUDE.md · AGENTS.md · GEMINI.md  ← bloque que manda a cada agente a leer el vault
```

### Empezar a trabajar

Cuéntale a Claude tu primer objetivo, por ejemplo: *"Quiero una API de reservas con login"*. Claude lo convierte en un handoff `objetivo` para el planificador y el ciclo arranca solo. Si el proyecto no tiene stack definido, el primer hilo es `stack`: el planificador propone 3 opciones por capa y nadie escribe código hasta que tú elijas.

---

## 5. Usar `team-resume` (cada vez que vuelves)

Abre Herdr con los panes (o solo el de Claude; los demás se pueden relanzar) y escribe:

```
/team-resume
```

Claude:
1. Lee el vault (`Protocolo`, `STATE`, fichas, handoffs abiertos, última verificación) y engram.
2. Busca al planificador y al ejecutor en Herdr. Si cambiaron de pane, los renombra. Si no están, te pregunta y los relanza **retomando su sesión anterior** (`kimi --session`, `agy --conversation`, `claude --resume`).
3. Si un agente cambió de versión, le pide que actualice su ficha.
4. Pone al día a cada agente, reenvía los handoffs que no se entregaron y te dice en qué fase van, de quién es el turno y qué sigue.

---

## 6. Cómo trabaja el equipo (el Protocolo)

El texto completo está en `skills/team-bootstrap/templates/Protocolo.md`; cada proyecto recibe su copia en `brain/Equipo/Protocolo.md`.

**Ciclo**

```
tú ─► orquestador ──objetivo──► planificador ──plan──► ejecutor
          ▲                         ▲   └──◄── ejecucion ──┘
          │◄── listo-para-verificar ┘
          ├── hallazgos ──► planificador        (si la verificación falla)
          └── aprobado / bloqueo ──► tú
```

**Reglas clave**

- **Handoffs como archivos.** Todo traspaso de trabajo es un `.md` con encabezado YAML (`de`, `para`, `tipo`, `estado`, `hilo`, `ronda`, criterios) en `brain/Handoffs/`. Por Herdr solo se manda el aviso. Si el aviso no llega, se reintenta una vez; si vuelve a fallar, el handoff queda `no-entregado` y `team-resume` lo reenvía.
- **Multi-agente obligatorio.**
  - El planificador usa sus subagentes para investigar.
  - Divide el plan en **unidades** independientes agrupadas en **oleadas**, y asigna cada unidad a un subagente concreto del ejecutor (según su ficha).
  - El ejecutor corre cada oleada en paralelo y reporta el resultado por unidad.
- **Nivel de modelo según la dificultad.**
  - *Potente:* arquitectura, depuración difícil, seguridad, planificación.
  - *Estándar:* implementación normal.
  - *Ligero:* tareas mecánicas.

  Cada agente traduce el nivel a sus modelos reales según su ficha. Si una unidad falla, sube un nivel en la siguiente ronda.
- **Verificación real.** El orquestador vuelve a ejecutar cada chequeo él mismo y nunca da por bueno el reporte de otro agente. Si falla, devuelve hallazgos; no corrige código.
- **Límite de rechazos.** Al 3er `hallazgos` en un mismo hilo, se crea un `bloqueo` para ti y el hilo se pausa.
- **Checkpoint.** Antes de cerrar sesión, cada agente actualiza `STATE.md` y guarda su resumen en engram con el nombre del proyecto.
- **Las aprobaciones son tuyas.** Si un agente queda esperando una aprobación o una pregunta, solo tú respondes.

---

## 7. Solución de problemas

| Síntoma | Causa | Solución |
|---|---|---|
| Un agente no aparece en `herdr agent list` (Windows) | Herdr en Windows no ve agentes que corren como `node.exe` (CLIs instalados con npm) | Lanza el agente desde una copia de `node.exe` renombrada con el alias que espera Herdr (receta abajo) |
| `herdr integration status` muestra un agente `outdated` o sin instalar | Los hooks de estado de Herdr no están al día | `herdr integration install <nombre>` (Antigravity se llama `antigravity-cli`) |
| La tabla de salud muestra engram ❌ "rutas distintas" | Cada agente guarda la memoria en un `ENGRAM_DATA_DIR` diferente | Usa la misma ruta (recomendado `~/.engram`) en `~/.claude.json`, `~/.kimi-code/mcp.json` y `~/.gemini/config/mcp_config.json` |
| El agente recibe `C:/Program Files/Git/exit` en vez de `/exit` | Git Bash convierte en ruta los argumentos que empiezan con `/` | Antepón `MSYS_NO_PATHCONV=1` al comando |
| Un agente queda `blocked` al arrancar ("Trust this folder") | Primera vez en esa carpeta | Respóndelo tú en su pane, o confirma a Claude que lo apruebe |
| `team-bootstrap` dice que el proyecto ya tiene equipo | Ya existe `brain/` | Usa `/team-resume` |

**Receta para el caso `node.exe` (ejemplo con Kimi Code).**

1. Busca el alias del agente en `%LOCALAPPDATA%\herdr\agent-detection\remote\<tipo>.toml` (campo `aliases`).
2. Agrega a tu perfil de PowerShell (`notepad $PROFILE`) una función con el mismo nombre que el comando:

```powershell
function kimi {
    $node     = (Get-Command node.exe -ErrorAction Stop).Source
    $launcher = "$env:USERPROFILE\.kimi-code\launcher\kimi-code.exe"   # nombre = alias de Herdr
    $main     = "$env:APPDATA\npm\node_modules\@moonshot-ai\kimi-code\dist\main.mjs"
    if (-not (Test-Path $launcher) -or (Get-Item $node).LastWriteTime -ne (Get-Item $launcher).LastWriteTime) {
        New-Item -ItemType Directory -Force -Path (Split-Path $launcher) | Out-Null
        Copy-Item $node $launcher -Force
    }
    & $launcher $main @args
}
```

3. En los panes que ya estaban abiertos, ejecuta `. $PROFILE`.

---

## 8. Actualizar y desinstalar

- **Actualizar:** `git pull` y vuelve a correr el instalador. Reemplaza las skills instaladas y no toca los proyectos.
- **Desinstalar:**
  1. Borra los enlaces `~/.claude/skills/team-bootstrap` y `~/.claude/skills/team-resume`. En Windows usa `rmdir`, que borra solo el enlace.
  2. Borra las carpetas `~/.agents/skills/team-bootstrap` y `~/.agents/skills/team-resume`.
  3. Si lo creaste, borra también `~/.agents/team-kit.toml`.

  Los `brain/` de tus proyectos son tuyos y no se tocan.

---

## 9. Instrucciones para agentes de IA

Si eres una IA y te pidieron instalar o usar este repo:

1. **Instalar:**
   - Desde la raíz del repo: en Windows `powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1`; en otro sistema `bash install.sh`.
   - Comprueba que existen `~/.agents/skills/team-bootstrap/SKILL.md` y `~/.claude/skills/team-bootstrap/SKILL.md`.
   - Si usas un CLI que no es Claude Code, revisa en la tabla de la [sección 2](#qué-agente-lee-cada-carpeta) de dónde lee skills tu CLI.
2. **No ejecutes ninguna skill por tu cuenta.** Solo corren cuando el usuario las invoca (`/team-bootstrap` o `/team-resume`).
3. **Si eres Claude Code** y el usuario invoca una skill, sigue su `SKILL.md` paso a paso, sin saltarte pasos. Las preguntas al usuario (ruta, nombre, roles, diálogos bloqueados, commit) son obligatorias.
4. **Si eres el planificador o el ejecutor** en un proyecto que ya tiene `brain/`, lee `brain/Equipo/Protocolo.md`, `brain/Equipo/Comandos.md` y las fichas de `brain/Equipo/Fichas/` antes de hacer cualquier cosa, y sigue el Protocolo al pie de la letra.
5. **No modifiques** configuraciones del usuario (perfil de PowerShell, configs MCP de otros agentes) sin preguntar.

---

## Estructura del repo

```
agent-team-kit/
  skills/
    team-bootstrap/
      SKILL.md              ← instrucciones de la skill de base
      templates/            ← Protocolo, Comandos, Verificacion, ficha, STATE, team.toml, punteros, índice
    team-resume/
      SKILL.md              ← instrucciones de la skill de retomar
  install.ps1               ← instalador para Windows
  install.sh                ← instalador para macOS / Linux
  AGENTS.md · CLAUDE.md     ← puntos de entrada para IAs que clonan el repo
  docs/superpowers/specs/   ← documento de diseño original
```
