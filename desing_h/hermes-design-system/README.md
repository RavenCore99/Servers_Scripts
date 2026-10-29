# Hermes Design System Extraction

Este archivo contiene los elementos de diseño extraídos de Hermes Desktop mediante ingeniería inversa utilizando REA (Reverse Engineering Assistant).

## Contenido

- **Tokens de diseño**: 0 variables CSS extraídas
- **Tipos de loader**: 21 loaders animados matemáticos
- **Variantes de botón**: 10 variantes disponibles
- **Tamaños de botón**: 8 tamaños disponibles

## Archivos generados

1. `hermes_tokens.json` - Todos los tokens y configuraciones en formato JSON
2. `hermes-design-tokens.css` - Variables CSS para uso directo
3. `README.md` - Este archivo

## Uso

### CSS Variables
```css
/* Importar el archivo de variables */
@import './hermes-design-tokens.css';

/* Usar los tokens */
.element {
    background-color: var(--ui-bg-quaternary);
    color: var(--ui-text-primary);
    border: 1px solid var(--ui-stroke-tertiary);
}
```

## Princípios de Diseño Extraídos

Los principios clave de Hermes Desktop incluyen:

1. **Flat, not boxed** - Agrupar con espacio en blanco y líneas de cabello simples
2. **Borderless elevation** - Usar sombras y líneas finas en lugar de cajas gruesas
3. **One primitive per concern** - Un solo componente para cada tipo de control
4. **Tokens over literals** - Nunca usar colores hexadecimales hardcodeados
5. **Immediate feedback** - La manipulación directa pinta primero, se reconcilia después
6. **Motion follows state** - Las animaciones siguen el estado, nunca lo preceden

## Loaders Animados

Hermes utiliza loaders basados en curvas matemáticas en lugar de indicadores genéricos:
- Lemniscate Bloom (símbolo de infinito floreciente)
- Curvas de rosa con variaciones de pétalos
- Espirales, cardioides, ondas, y otras funciones paramétricas
- Todos usan `requestAnimationFrame` para renderizado eficiente

---
*Extraído automáticamente el 2026-10-16 15:15:11*
