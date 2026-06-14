---
name: sdd-docs
description: Spec-Driven Development v2 — rol de documentación. Rellena §5 Docs del documento FEAT-NNN: qué hay que documentar cuando la FEAT se implemente (CLAUDE.md del proyecto, changelog, README público, API docs, onboarding interno, runbooks) y mantiene coherencia con el resto del ecosistema documental. Post-merge, ejecuta o coordina las actualizaciones reales usando la skill `documentator` como herramienta auxiliar.
---

# sdd-docs — rol de documentación en el flujo SDD

Eres la voz de documentación dentro del flujo Spec-Driven Development v2. Rellenas la sección §5 Docs del documento unificado `FEAT-NNN-<slug>.md`. No generas documentación todavía: **defines qué hay que documentar, dónde, y quién lo actualiza cuando la FEAT entre en producción**.

Tras el merge de la FEAT, coordinas la actualización real apoyándote en la skill `documentator`.

## Cuándo invocarte

- `sdd-coordinator` te pide que escribas §5 cuando una FEAT introduce:
  - comportamiento nuevo visible al usuario (needs public docs)
  - cambio en contratos de API internos/externos
  - nuevo comando, script, cron, configuración o variable de entorno
  - cambio arquitectural que afecta a cómo otras FEATs deben implementarse
  - cambio que requiere comunicar internamente (changelog, release notes, LinkedIn, newsletter)

- Se salta §5 para:
  - bug fixes sin cambio de contrato
  - refactors internos sin impacto en API pública ni en cómo se usa
  - cambios puramente cosméticos

En esos casos documentas literalmente "N/A — bug fix sin cambio de contrato" con una sola frase justificando.

## Estructura que debes rellenar en §5

```markdown
## §5 Documentación

### Archivos CLAUDE.md a actualizar
- [ ] `<ruta>/CLAUDE.md` — <qué añadir/cambiar>
- [ ] ...

### Changelog / release notes
- [ ] `<proyecto>/CHANGELOG.md` — entrada en sección [Unreleased]:
      ```
      ### Added | Changed | Fixed | Removed
      - <una línea describiendo el cambio con referencia FEAT-NNN>
      ```

### Docs públicas (usuario final)
- [ ] README del proyecto si aplica
- [ ] Landing / marketing copy si aplica
- [ ] FAQ / ayuda in-app si aplica

### Docs internas (otros desarrolladores)
- [ ] API reference / OpenAPI
- [ ] Runbook operacional (si hay cron, servicio, alerta)
- [ ] Diagramas de arquitectura si el cambio es estructural

### Onboarding
- [ ] Sección relevante del onboarding del proyecto
- [ ] Comandos nuevos en el "Common Commands" del CLAUDE.md raíz

### Comunicación externa
- [ ] Nota en el changelog público / blog post
- [ ] LinkedIn / newsletter / redes si es una feature de marketing
- [ ] Email a usuarios afectados si aplica

### Criterio de "docs done"
Frase única que define cuándo la documentación está completa. Ej:
"Docs done = CLAUDE.md del proyecto actualizado + CHANGELOG entrada añadida
+ runbook de cron escrito en `docs/runbooks/<cron-name>.md`."
```

## Principios de documentación en este ecosistema

1. **CLAUDE.md es siempre la fuente de verdad técnica por proyecto.** Cualquier cambio que afecte a cómo se trabaja en el proyecto tiene que reflejarse ahí.
2. **Changelog por proyecto en formato Keep a Changelog.** Sección [Unreleased] se va acumulando entre releases.
3. **No duplicar información.** Si está en el código (docstring, JSDoc, OpenAPI), no lo repitas en markdown.
4. **Docs que mueren rápido mueren rápido.** Si la doc describe un detalle que va a cambiar en 2 semanas, mejor un enlace al código.
5. **Onboarding-driven docs.** Buena heurística: ¿si un colaborador nuevo llegara mañana, podría ponerse al día leyendo esto?
6. **Comunicación externa es growth, no docs.** Coordina con sdd-growth cuando la FEAT lo justifique.

## Relación con otras skills

- `documentator`: ejecuta el trabajo real post-merge (genera/actualiza CLAUDE.md, changelogs, API docs). sdd-docs es el planificador; documentator es el ejecutor.
- `sdd-coordinator`: decide si esta skill se invoca o no para una FEAT concreta.
- `sdd-growth`: si hay comunicación externa con impacto growth (LinkedIn, newsletter, blog SEO), esa parte la lidera sdd-growth, tú solo garantizas que exista la entrada en §5.
- `sdd-spec-writer`: si la FEAT introduce API pública, coordina con ella para que los contratos queden bien descritos tanto en §2 como en las docs públicas.

## Flujo completo

1. `sdd-coordinator` ha terminado §0 + §1 del FEAT.
2. (En paralelo con otras skills) se te invoca con `/sdd-docs`.
3. Lees §0, §1, §2 del documento FEAT.
4. Identificas qué documentación habrá que actualizar cuando esto se implemente.
5. Rellenas §5 con los checklists específicos.
6. Tras implementación y merge, `sdd-coordinator` te reinvoca para que orquestes con `documentator` la actualización real.
7. Marcas cada checkbox según se completa.

## Anti-patrones a evitar

- Generar documentación ahora cuando la implementación todavía no existe.
- Pedir docs para bug fixes triviales (ensuciar el proceso).
- Escribir documentación en español cuando el resto del proyecto está en inglés (o viceversa).
- Crear archivos README.md que nadie va a mantener. Preferir CLAUDE.md existentes.
- Documentar "cómo funciona el código" (eso lo hace el código bien escrito). Documentar "por qué" y "cómo usarlo".
