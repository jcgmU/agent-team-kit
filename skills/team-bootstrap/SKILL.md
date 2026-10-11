---
name: team-bootstrap
description: Arma la base de trabajo de un equipo de agentes coordinado por Herdr (Claude orquestador + un planificador + un ejecutor) en la carpeta de un proyecto - vault de Obsidian brain/, memoria engram, fichas de capacidades, roles y protocolo. Usar SOLO cuando el usuario lo invoca explicitamente. Lo ejecuta Claude como orquestador.
---

# team-bootstrap

Eres el **orquestador** (siempre Claude). Vas a dejar lista la base para que tú y los otros dos agentes trabajen juntos en este proyecto. **No** eliges stack ni escribes código del producto.

Las plantillas están en la carpeta `templates/` junto a este archivo (`~/.agents/skills/team-bootstrap/templates/`). En ellas, `{{X}}` es un valor que tú rellenas.

Desde Git Bash, antepone `MSYS_NO_PATHCONV=1` a cualquier comando cuyo argumento empiece con `/` (por ejemplo `/exit`); si no, Git Bash lo convierte en una ruta.

## 1. Precondiciones
- `test "$HERDR_ENV" = 1`. Si falla: explica que hay que abrir esta sesión dentro de un pane de Herdr y **detente**.
- Confirma con el usuario la **ruta absoluta** del proyecto (`<ruta>`) y un **nombre corto** (`<nombre>`, en minúsculas y con guiones).
- Si ya existe `<ruta>\brain`, el proyecto ya tiene equipo: **detente** y sugiere `team-resume`.

## 2. Descubrir el equipo (siempre antes que nada)
- `herdr agent list` y `herdr pane list --workspace "$HERDR_WORKSPACE_ID"`.
- Agentes = los panes que tienen campo `agent`. El tuyo es el que tiene `pane_id` = `$HERDR_PANE_ID`.
- **Panes sin agente:** léelos con `herdr pane read <pane> --source visible --lines 30`. Si ves la interfaz de un agente que Herdr no detecta, avísale al usuario. En Windows, Herdr no ve agentes que corren como `node.exe`. El arreglo es lanzarlos desde una copia de `node.exe` renombrada con el alias del agente (el alias está en `%LOCALAPPDATA%\herdr\agent-detection\remote\<kind>.toml`, campo `aliases`), como se hizo con Kimi en la función `kimi` del perfil de PowerShell.
- A cada agente sin nombre asígnale uno: `herdr agent rename <pane> <kind>` (si el nombre ya está tomado, `<kind>-2`).
- Versión de cada agente: `<kind> --version` (`claude`, `kimi`, `agy`, …).
- Si no hay al menos dos agentes además de ti, explícalo y detente.

## 3. Revisión de salud
Revisa y muéstrale al usuario una tabla con ✅ / ⚠ / ❌ y, al lado de cada problema, su arreglo:
- **Detección:** todos los agentes detectados (paso 2).
- **Integración de hooks:** `herdr integration status`. Cada tipo de agente del equipo debe aparecer como `current` (el tipo `agy` aparece como `antigravity-cli`). Arreglo: `herdr integration install <nombre>`.
- **Engram compartido:** lee `ENGRAM_DATA_DIR` del servidor MCP `engram` en `~/.claude.json` (claude), `~/.kimi-code/mcp.json` (kimi) y `~/.gemini/config/mcp_config.json` (agy). Para otros tipos, marca ⚠ "no verificable".
  - ❌ si a algún agente le falta engram o si las rutas no coinciden;
  - ⚠ si la ruta común está dentro de la carpeta de un proyecto (lo recomendado es `~/.engram`).
  - **Nunca** edites esas configuraciones sin preguntar.
- Si hay ❌ en engram, pregunta si continuar igual.

## 4. Fichas de capacidades (cada agente se describe a sí mismo)
- Crea `<ruta>\brain\Equipo\Fichas\` y copia allí `templates/ficha-plantilla.md` como `_plantilla-ficha.md`.
- A cada agente `<n>` (menos tú), en paralelo:
  ```
  herdr agent prompt <n> "Escribe tu ficha de capacidades en <ruta>\brain\Equipo\Fichas\<n>.md siguiendo la plantilla <ruta>\brain\Equipo\Fichas\_plantilla-ficha.md. Se honesto: si no tienes algo, dilo. Explica como se invocan exactamente tus subagentes o tu modo multi-agente, tus comandos slash, skills y plugins o MCP. Al terminar responde solo FICHA LISTA." --wait --until working --until done --until blocked --timeout 15000
  ```
  El texto del prompt **no** puede llevar comillas dobles dentro.
- Luego espera a cada uno con `herdr agent wait <n> --timeout 300000`.
- **Si un agente queda `blocked`:** léelo con `herdr agent read <n> --source visible --lines 40`, muéstrale el diálogo al usuario y pregúntale qué hacer. **Nunca** lo respondas tú.
- **Si a los 5 minutos no hay ficha:** créala con `estado: sin-respuesta` en el encabezado y sigue.
- Escribe **tu propia ficha** con la misma plantilla.
- **Verificación cruzada:** en cada ficha, completa la tabla "Verificación del orquestador":
  - versión real (`<kind> --version`);
  - detección y engram (resultados del paso 3);
  - que existan las carpetas de skills que el agente declaró.

  Marca cada dato como ✅ verificado, ⚠ declarado (no verificable) o ❌ contradicho.

## 5. Roles
Muéstrale al usuario los agentes (nombre, tipo, versión) y pregunta con AskUserQuestion, en una sola llamada con dos preguntas:
- "¿Quién será el planificador?"
- "¿Quién será el ejecutor?"

Tienen que ser distintos entre sí y distintos de ti, porque tú eres siempre el orquestador. No sugieras ningún agente por defecto.

## 6. Generar la base
Copia las plantillas rellenando `{{PROJECT}}` (nombre), `{{DATE}}` (hoy, `yyyy-MM-dd`), `{{ORCHESTRATOR}}` (tu nombre en Herdr), `{{PLANNER}}`, `{{PLANNER_KIND}}`, `{{EXECUTOR}}`, `{{EXECUTOR_KIND}}`, `{{PROJECT_PATH}}` (`<ruta>`) y los demás que aparezcan:

| Plantilla | Destino |
|---|---|
| `00-Inicio.md` | `<ruta>\brain\00-Inicio.md` |
| `Protocolo.md` | `<ruta>\brain\Equipo\Protocolo.md` |
| `Comandos.md` | `<ruta>\brain\Equipo\Comandos.md` |
| `Verificacion.md` | `<ruta>\brain\Equipo\Verificacion.md` |
| `STATE.md` | `<ruta>\brain\Estado\STATE.md` (fase `equipo-listo`, turno = tú) |
| `team.toml` | `<ruta>\.team\team.toml` (incluye los `agent_session` actuales de `herdr agent list` y las versiones) |
| `pointer-block.md` | al final de `<ruta>\CLAUDE.md`, `<ruta>\AGENTS.md` y `<ruta>\GEMINI.md`. Si el archivo existe, **agrega** el bloque (o reemplaza el que ya esté entre `<!-- team:begin -->` y `<!-- team:end -->`), sin tocar el resto. |

Crea también las carpetas vacías `<ruta>\brain\Handoffs`, `<ruta>\brain\Decisiones` y `<ruta>\brain\Verificaciones`.

**Índice central:** lee `central_index_dir` de `~/.agents/team-kit.toml`. Si no existe, pregúntale al usuario la carpeta y guárdala ahí con el formato `central_index_dir = '<carpeta>'`. Crea `<carpeta>\PRJ-<nombre>.md` desde `central-index.md`, salvo que ya exista. `{{OBSIDIAN_URI}}` = `obsidian://open?path=` + la ruta de `<ruta>\brain\00-Inicio.md` codificada para URL.

## 7. Cerrar el bootstrap
- **engram:** `mem_save` con `project: <nombre>`, título `Bootstrap del equipo <nombre>`, y en el contenido los roles, los agentes y sus versiones. Si falla, pon `engram_pendiente: si` en `STATE.md`.
- **Avisa a cada agente su rol:**
  ```
  herdr agent prompt <n> "Eres el <planificador|ejecutor> del proyecto <nombre>. Lee <ruta>\brain\Equipo\Protocolo.md, <ruta>\brain\Equipo\Comandos.md y las fichas de <ruta>\brain\Equipo\Fichas. Responde solo PROTOCOLO LEIDO." --wait --timeout 300000
  ```
  Confírmalo con `herdr agent read <n> --source recent-unwrapped --lines 20`.
- **Repórtale al usuario:**
  - que abra `<ruta>\brain` en Obsidian ("Abrir carpeta como vault");
  - la ruta del índice central;
  - la tabla de salud;
  - que el siguiente paso es que te cuente el primer objetivo (si no hay stack, el primer hilo es `stack`).
- Pregunta si hacer commit. **No** lo hagas sin permiso.

## Reglas
- Nada de nombres de agentes fijos: todo sale de Herdr y de lo que conteste el usuario.
- Nunca cierres panes ni mates procesos que no creaste.
