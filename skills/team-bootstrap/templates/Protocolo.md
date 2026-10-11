# Protocolo del equipo — {{PROJECT}}

> Generado el {{DATE}} con team-bootstrap. Es la fuente de verdad del trabajo en equipo: todo agente lo lee al empezar cada sesión.

## Roles

| Rol | Agente (nombre en Herdr) | Tipo |
|---|---|---|
| Orquestador | {{ORCHESTRATOR}} | claude |
| Planificador | {{PLANNER}} | {{PLANNER_KIND}} |
| Ejecutor | {{EXECUTOR}} | {{EXECUTOR_KIND}} |

- **Orquestador:** recibe los objetivos del usuario, coordina, verifica de verdad y reporta al usuario. **No corrige código:** devuelve hallazgos al planificador.
- **Planificador:** convierte objetivos en planes con criterios de aceptación verificables, revisa de verdad el trabajo del ejecutor antes de pasarlo a verificación y mantiene `brain/Equipo/Verificacion.md`.
- **Ejecutor:** implementa exactamente el plan (con TDD cuando aplique) y reporta qué hizo y cómo verificarlo.
- Cada uno puede y debe usar sus propios subagentes o su modo multi-agente cuando convenga (ver su ficha en `Fichas/`).

## Ciclo

1. El orquestador abre un hilo con un handoff `objetivo` al planificador.
2. El planificador envía un `plan` al ejecutor.
3. El ejecutor implementa y envía `ejecucion` al planificador.
4. El planificador revisa de verdad (corre tests y build, lee el diff). Si no cumple: nuevo `plan` (ronda + 1). Si cumple: `listo-para-verificar` al orquestador.
5. El orquestador verifica (sección Verificación). Si falla: `hallazgos` al planificador. Si pasa: `aprobado` al usuario y reporte.
6. **Límite de rechazos:** cuando un hilo llega a su 3er `hallazgos`, en lugar de enviarlo el orquestador crea un `bloqueo` con `para: usuario`, se lo presenta al usuario y el hilo queda en pausa.

## Handoffs (traspasos de trabajo)

Todo traspaso de trabajo es un **archivo**. Nada se pasa solo por texto en la terminal.

**Archivo:** `brain/Handoffs/yyyy-MM-dd-HHmm-<de>-a-<para>.md`. Si ya existe, agrega `-2`, `-3`, etc.

```
---
de: <tu nombre en Herdr>
para: <destinatario | usuario>
tipo: objetivo | plan | ejecucion | listo-para-verificar | hallazgos | aprobado | bloqueo
estado: pendiente
hilo: <slug estable del tema, ej. login-form>
ronda: <1 + cuántos handoffs previos hay del mismo hilo y tipo>
creado: <yyyy-MM-ddTHH:mm:ss>
criterios_de_aceptacion:
  - "..."
referencias:
  - "rutas o archivos relevantes"
---

# <tipo> - <hilo> - ronda <n>

Qué se pide o qué se hizo, archivos tocados, cómo verificarlo y, si quieres que el destinatario use sus subagentes o su modo multi-agente, la capacidad exacta tal como figura en su ficha.
```

**Enviar:**
1. Escribe el archivo.
2. Avisa al destinatario:
   ```
   herdr agent prompt <para> "Nuevo handoff para ti: <ruta del archivo> - leelo completo y actua segun brain/Equipo/Protocolo.md" --wait --until working --until done --until blocked --timeout 15000
   ```
   El texto no puede llevar comillas dobles dentro.
3. Si el comando funcionó, cambia `estado:` a `en-curso` y actualiza `turno` en `STATE.md`.
4. Si falló, reintenta **una vez**. Si vuelve a fallar, cambia `estado:` a `no-entregado` y avisa al orquestador o al usuario.
5. Los handoffs con `para: usuario` no se envían por Herdr: el orquestador se los presenta al usuario.

**Recibir:** lee el handoff completo, haz el trabajo, cambia su `estado:` a `hecho` y responde con tu propio handoff.

## Verificación (orquestador)

- `brain/Equipo/Verificacion.md` contiene la lista de chequeos (comandos con su resultado esperado y pruebas manuales). La mantiene el planificador una vez decidido el stack.
- El orquestador ejecuta **él mismo** cada chequeo. Nunca da por bueno el reporte de otro agente sin comprobarlo. Las pruebas manuales, por ejemplo una UI, se hacen de verdad.
- El resultado se guarda en `brain/Verificaciones/yyyy-MM-dd-HHmm-verificacion.md`: tabla de chequeos (PASA / FALLA / MANUAL) más la evidencia.
- Si no hay chequeos definidos, el orquestador envía `hallazgos` al planificador pidiéndole que los defina.

## Checkpoint (todos)

Antes de cerrar sesión, y el orquestador cada vez que cambia el turno:

1. Actualiza el bloque de `brain/Estado/STATE.md`: fase, ronda, turno, siguiente paso, fecha.
2. Guarda el resumen de sesión en engram con el proyecto `{{PROJECT}}`, con estas secciones: Goal, Discoveries, Accomplished, Next Steps, Relevant Files. Si falla, pon `engram_pendiente: si` en `STATE.md`.
3. **Solo el orquestador:** actualiza `last_session_id` de cada rol en `.team/team.toml` con el `agent_session` que muestra `herdr agent list`.

## Reglas

- **Memoria engram:** usa siempre el proyecto `{{PROJECT}}`.
- **Decisiones importantes:** un ADR en `brain/Decisiones/`.
- **Proyecto sin stack definido:** el primer hilo es `stack`. El planificador propone 3 opciones reales por capa (frontend, backend, base de datos, colas, despliegue, IA). El orquestador las presenta al usuario, y nadie escribe código hasta que el usuario confirma. El stack elegido queda en un ADR.
- **Diálogos de aprobación o preguntas de un agente** (estado `blocked` en Herdr): solo los responde el usuario.
- **Desde Git Bash:** antepone `MSYS_NO_PATHCONV=1` si un argumento empieza con `/`.
