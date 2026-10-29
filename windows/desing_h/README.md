# Referencias visuales para la Fase 3 de Vultus

Este directorio conserva material recopilado de Hermes Desktop como inspiración, no una implementación de Vultus ni una fuente de reglas superior a `../../CLAUDE.md` y `../../PLANNING.md`. En Fase 3 se adaptarán los patrones a las pantallas de Vultus; no se debe copiar sin más la navegación centrada en chat, nombres de componentes, rutas o colores ajenos.

- `DESIGN.md` y `HERMES_DESKTOP_README_SOURCE.md`: instantáneas de documentación de Hermes Desktop. Sus referencias a `apps/desktop`, `AGENTS.md` y comandos `hermes` pertenecen al proyecto de origen y **no** existen necesariamente aquí.
- `hermes-design-system-final/`: referencia detallada de tokens y su CSS; `hermes-design-system-complete/` y `hermes-design-system/` son capturas alternativas, no configuraciones simultáneas. El CSS de `hermes-design-system/` solo contiene un `:root` vacío: no importarlo en la app.
- `hermes_design_tokens.pseudocode.txt`: apunte ilustrativo extraído por scraping. Contiene secuencias de escape literales, no es Python ejecutable ni debe importarse.
- `../fuentes/` y `../icons/`: recursos disponibles en el repo; verificar licencia y aplicación antes de integrarlos.

La Fase 3 definirá los tokens propios en `desktop/src/styles/` siguiendo el alcance de `PLANNING.md`, probará estados de carga/error/reduced-motion y documentará con capturas qué se adoptó. Hasta entonces, estos archivos son solo referencia. Para el código actual del backend, consultar `../../README.md`.
