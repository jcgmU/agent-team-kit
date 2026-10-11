# agent-team-kit — Diseño

- **Fecha:** 2026-10-11
- **Estado:** Borrador para revisión del usuario
- **Repo:** `C:\Users\jcgm1\OneDrive\Desktop\agent-team-kit`

## 1. Propósito

Convertir la forma de trabajar validada en RESTAURANTE-OS (un agente planifica, otro ejecuta y Claude
orquesta y verifica, coordinados por Herdr) en un **sistema genérico y reutilizable** para cualquier
proyecto, que:

- se arme **solo cuando el usuario lo invoca** (nunca automáticamente);
- no dependa de qué LLM cumple cada rol (se elige al iniciar cada proyecto);
- deje en cada proyecto un **segundo cerebro** (vault de Obsidian) y memoria persistente (engram)
  compartidos por los tres agentes;
- permita **retomar** cualquier sesión exactamente donde quedó, sin que el usuario repita
  instrucciones.

**Éxito =** el usuario invoca `team-bootstrap` en una carpeta vacía o existente, elige planificador y
ejecutor, y a partir de ahí el ciclo planificar → ejecutar → revisar → verificar corre entre agentes
sin que el usuario haga de mensajero. Tras cerrar todo, `team-resume` recupera el estado y reenvía lo
pendiente.

### Fuera de alcance

- Elegir stack o escribir código del producto (el primer ciclo de un proyecto greenfield es el
  brainstorm de stack que exige el `CLAUDE.md` global del usuario).
- Hooks automáticos que disparen skills sin invocación explícita.
- Registrar el vault en Obsidian editando su configuración interna.
- Vigilante en segundo plano para despertar a Claude (innecesario: Herdr entrega los avisos al pane de
  Claude y los archivos de handoff garantizan que nada se pierda).

## 2. Roles

| Rol | Quién | Cómo se define |
|---|---|---|
| **Orquestador** | Siempre Claude | Fijo en el protocolo. Incluye la verificación final y el reporte al usuario. |
| **Planificador** | Cualquier agente detectado en Herdr | El usuario lo elige al iniciar (`team-bootstrap`). Se guarda en `team.toml`. |
| **Ejecutor** | Cualquier agente detectado en Herdr | Ídem. |

Las fichas de capacidades **no** se usan para asignar roles; sirven para que cada agente sepa qué
puede pedirle al otro (incluidos sus subagentes o modos multi-agente).

## 3. Arquitectura y componentes

### 3.1 Global (instalado una vez desde este repo)

```
agent-team-kit/                    ← este repo (fuente versionada)
  skills/
    team-bootstrap/   SKILL.md, templates/, scripts/
    team-resume/      SKILL.md
    team-handoff/     SKILL.md   (+ script de escritura/entrega)
    team-verify/      SKILL.md
    team-checkpoint/  SKILL.md
    team-doctor/      SKILL.md, team-doctor.ps1
  install.ps1                      ← copia a ~/.agents/skills y crea junctions en ~/.claude/skills
  docs/superpowers/specs/          ← este documento
```

Destino de instalación:

- `~/.agents/skills/team-*` — fuente única en tiempo de ejecución. **Kimi Code** la descubre de forma
  nativa (`.agents/skills`) y **Antigravity CLI** también (`~/.gemini/skills` es un enlace a
  `~/.agents/skills`).
- `~/.claude/skills/team-*` — junctions hacia lo anterior, para Claude Code.

Riesgo conocido: Kimi también lee `~/.claude/skills`, por lo que podría ver cada skill dos veces.
Mitigación: verificar en la prueba E2E; si duplica, `install.ps1` excluye los junctions de su
descubrimiento o se usa solo `~/.agents/skills` + `--skills-dir`.

Convención de idioma: nombres de skills, scripts y código en inglés; contenido del vault en español.

### 3.2 Por proyecto (creado por `team-bootstrap` en la carpeta donde se invoca)

```
<proyecto>/
  brain/                           ← vault de Obsidian (notas operativas)
    00-Inicio.md
    Equipo/Protocolo.md            ← reglas del ciclo con los roles ya resueltos
    Equipo/Fichas/<agente>.md      ← capacidades: ✅ verificado / ⚠ declarado / ❌ sin respuesta
    Equipo/Comandos.md             ← matriz quién puede pedir qué a quién
    Estado/STATE.md                ← fase, ronda, quién tiene el turno, siguiente paso
    Handoffs/                      ← un archivo por traspaso
    Decisiones/                    ← ADRs
    Verificaciones/                ← resultados de /team-verify
  .team/
    team.toml                      ← roles→agentes, panes, versiones, sesiones, proyecto engram
    verify.toml                    ← chequeos del proyecto (vacío con ejemplos al inicio)
  CLAUDE.md · AGENTS.md · GEMINI.md ← bloque puntero <!-- team:begin/end -->
```

### 3.3 Central

`DevIA-Brain/03-Proyectos/PRJ-<nombre>.md`: nota índice con enlaces `obsidian://` al vault del repo
(modelo híbrido: lo operativo vive con el código, el índice en el segundo cerebro global).

### 3.4 Engram

`team.toml` fija `engram_project = "<nombre>"`. Los tres agentes guardan y buscan con ese proyecto
explícito, en vez de dejar que engram lo adivine por la carpeta de trabajo (causa de que memorias de
Resto quedaran bajo "system32").

### 3.5 Formato de `team.toml`

```toml
[project]
name = "<nombre>"
engram_project = "<nombre>"
created = "YYYY-MM-DD"

[orchestrator]
kind = "claude"

[roles.planner]
agent_name = "<nombre-herdr>"
kind = "<kind herdr>"        # p.ej. kimi
version = "<x.y.z>"
last_session_id = ""

[roles.executor]
agent_name = "<nombre-herdr>"
kind = "<kind herdr>"        # p.ej. agy
version = "<x.y.z>"
last_session_id = ""
```

## 4. Flujo de `team-bootstrap` (Skill 1)

1. **Precondiciones.** `HERDR_ENV=1`; confirmar carpeta destino. Si existe `brain/` → abortar y
   sugerir `team-resume`.
2. **Descubrir agentes.** `herdr agent list` + revisar panes `unknown` (posible agente mal detectado)
   y avisar. Asignar nombres estables si faltan (`herdr agent rename`).
3. **`/team-doctor`** (sección 6).
4. **Fichas autodeclaradas.** Claude envía a cada agente, vía `herdr agent prompt … --wait`, la
   plantilla de ficha; cada uno escribe `brain/Equipo/Fichas/<nombre>.md`: identidad (kind, versión,
   modelo), herramientas, subagentes/modo multi-agente y cómo invocarlos, comandos `/`, skills,
   plugins/MCP, límites, cómo prefiere recibir trabajo. Claude escribe la suya. Timeout 5 min.
5. **Verificación cruzada.** Claude comprueba lo verificable (rutas de skills, engram en config MCP,
   versión, detección Herdr) y marca cada dato ✅ / ⚠.
6. **Preguntar roles.** Mostrar los agentes detectados y preguntar al usuario quién es planificador y
   quién ejecutor. Escribir `team.toml`.
7. **Generar la base.** `Protocolo.md`, `Comandos.md`, `STATE.md` (fase "inicio"), `verify.toml`
   vacío, bloques puntero, nota índice central, registro en engram. Avisar a cada agente su rol y
   pedir confirmación de lectura. No hace commit sin preguntar.

## 5. Protocolo de comunicación

### 5.1 Handoff (unidad de trabajo)

Archivo `brain/Handoffs/YYYY-MM-DD-HHMM-<de>-a-<para>.md` con frontmatter:

```yaml
de: <agente>
para: <agente>
tipo: plan | ejecucion | listo-para-verificar | hallazgos | aprobado | bloqueo
estado: pendiente | en-curso | hecho | no-entregado | cerrado
hilo: <id del hilo de trabajo>
ronda: <n>
criterios_de_aceptacion: [...]
referencias: [...]
```

El archivo es la fuente de verdad; el mensaje por Herdr solo avisa.

### 5.2 `/team-handoff`

1. Escribe la nota y actualiza `STATE.md`.
2. `herdr agent prompt <para> "Nuevo handoff: brain/Handoffs/<archivo>"`.
3. Confirma entrega: si Herdr responde `agent_prompt_stalled`, reintenta una vez; si vuelve a fallar
   → `estado: no-entregado` y aviso al usuario.

### 5.3 Ciclo

```
planificador ──plan──► ejecutor ──hecho──► planificador (revisa de verdad)
      ▲                                         │ listo-para-verificar
      └──────────── hallazgos ◄── Claude (orquestador) ◄─┘
                                       │ aprobado
                                       ▼
                              reporte al usuario
```

- El orquestador **no corrige código**: devuelve hallazgos al planificador.
- **Circuit breaker:** 3 rechazos en un mismo `hilo` → handoff `bloqueo` al usuario y pausa.

### 5.4 `Comandos.md`

Matriz de qué tipo de handoff puede emitir cada rol hacia cada otro, y cómo pedir explícitamente que
el destinatario use sus propios subagentes (según su ficha).

### 5.5 `/team-verify`

Ejecuta los chequeos de `.team/verify.toml` (comandos con resultado esperado: tests, build, E2E; y
chequeos manuales tipo "probar UI real"). Guarda el resultado en `brain/Verificaciones/`. Regla: el
orquestador re-ejecuta todo por su cuenta; nunca da por bueno el reporte de otro agente.

## 6. `team-resume` (Skill 2), `/team-checkpoint` y `/team-doctor`

### 6.1 `team-resume`

1. Precondiciones: Herdr + `brain/` + `.team/team.toml`; si faltan → sugerir `team-bootstrap`.
2. Cargar contexto: `00-Inicio`, `Protocolo`, `STATE.md`, handoffs abiertos, última verificación;
   engram `mem_context` + `mem_search` con `engram_project`.
3. `/team-doctor`. Re-ubicar planificador y ejecutor por `kind` (los panes cambian tras reinicios) y
   reasignar nombres. Si falta uno: preguntar si lanzarlo o asignar otro; si hay `last_session_id`,
   ofrecer reanudarlo con el CLI del agente (p.ej. `kimi -r <id>`, `agy --conversation <id>`). Si
   cambió la versión de un agente, regenerar solo su ficha.
4. Re-briefing: avisar a cada agente "retomamos, lee STATE.md y tus handoffs pendientes"; reenviar
   los `no-entregado`.
5. Reporte breve al usuario (fase, quién tiene el turno, qué sigue) y continuar el ciclo.

### 6.2 `/team-checkpoint`

Actualiza `STATE.md`, escribe `mem_session_summary` con `engram_project` y registra los
`last_session_id` en `team.toml`. Lo ejecuta Claude en cada transición del ciclo; el protocolo obliga
a los tres agentes a ejecutarlo antes de cerrar. Sin hooks automáticos.

### 6.3 `/team-doctor`

Tabla ✅/⚠/❌ con arreglo sugerido por fila:

| Chequeo | Detecta |
|---|---|
| Detección nativa en Herdr | agentes `unknown` (p.ej. CLIs sobre `node.exe` en Windows) |
| Integración Herdr | hooks desactualizados o ausentes (`herdr integration status`) |
| Engram por agente | MCP no configurado o proyecto mal fijado |
| Roles ↔ agentes vivos | rol asignado a un agente ausente |
| Vault y archivos | `brain/` incompleto, punteros faltantes |
| Handoffs | `no-entregado` o abiertos demasiado tiempo |

## 7. Manejo de errores

| Situación | Respuesta |
|---|---|
| Fuera de Herdr | Detenerse y explicar cómo abrirlo dentro de Herdr |
| Agente no entrega ficha en 5 min | Ficha ❌ "sin respuesta", continuar, reportar en doctor |
| Agente `blocked` (diálogo de aprobación) | Mostrar el diálogo y preguntar al usuario; nunca aprobar solo |
| `brain/` ya existe | Bootstrap aborta, sugiere `team-resume` |
| Archivos puntero ya existen | Agregar bloque `<!-- team:begin/end -->` sin tocar el resto |
| Engram falla | Continuar; `STATE.md` marca "pendiente de guardar"; el próximo checkpoint reintenta |
| Comandos `/` desde Git Bash | Scripts en PowerShell; toda llamada desde bash con `MSYS_NO_PATHCONV=1` |

## 8. Pruebas

1. **Scripts PowerShell** (`team-doctor.ps1`, escritura/entrega de handoffs): pruebas con carpetas de
   ejemplo (vault completo, incompleto, `team.toml` con rol huérfano).
2. **Skills:** método TDD de `superpowers:writing-skills` (comportamiento del agente sin skill vs con
   skill; que siga el protocolo y no se salte pasos).
3. **Aceptación E2E** en una carpeta descartable con los tres agentes reales en Herdr:
   bootstrap → fichas + `team.toml` + vault; ciclo mínimo (planificador pide crear `hola.txt`,
   ejecutor lo hace, planificador revisa, Claude verifica y aprueba); cerrar todo → `team-resume` →
   estado recuperado y un handoff a medias reenviado.

## 9. Prerrequisitos y contexto del entorno

- Herdr 0.8.2 en Windows. Kimi Code se detecta solo si corre como `kimi-code.exe` (función `kimi`
  en `OneDrive\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`, que ejecuta Kimi con
  una copia de `node.exe` renombrada en `~/.kimi-code/launcher/`). Cualquier otro CLI
  basado en `node.exe` tendrá el mismo problema; `team-doctor` debe detectarlo y explicarlo.
- Engram ya configurado en los tres agentes (`~/.claude/CLAUDE.md`, `~/.kimi-code/AGENTS.md`,
  `~/.gemini/GEMINI.md`).
- Vault central existente: `C:\Users\jcgm1\OneDrive\Desktop\Devia\DevIA-Brain`.
