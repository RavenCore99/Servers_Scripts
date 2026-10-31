# Servers_Scripts

![Python 3.10+](assets/badges/python.svg)
![Shell Bash](assets/badges/shell.svg)
![PowerShell 5.1+](assets/badges/powershell.svg)
![JavaScript](assets/badges/javascript.svg)
![HTML5](assets/badges/html5.svg)
![CSS3](assets/badges/css3.svg)

Panel de administración de **servidores dinámicos** + API FastAPI (balanceador + nodos) + UI web.

Repositorio para ejecutar el panel localmente en Linux o Windows x64. Los lanzadores no modifican `servidores.py` ni `balanceador.py`, la base de la actividad.

## Contenido

| Ruta | Descripción |
|------|-------------|
| `balanceador.py` / `servidores.py` | API FastAPI (versión Linux, puertos 8000–8003) |
| `index.html` `estilos.css` `script.js` | Panel web |
| `iniciar.sh` | Arranque Linux |
| `windows/` | Copia portable para Windows (Python embeddable + wheels) |
| `desing_h/` | Iconos y referencias de diseño |

## Linux

```bash
git clone https://github.com/RavenCore99/Servers_Scripts.git
cd Servers_Scripts
./iniciar.sh
```

- Panel: http://127.0.0.1:5500/ (si está ocupado, consulta el puerto anunciado)
- API: http://127.0.0.1:8000/

Requisitos: Linux, Bash y Python 3.10+ con `venv` y `pip`; conexión a internet en la primera instalación. El script crea `venv` e instala dependencias. Ctrl+C detiene los procesos iniciados por el lanzador. Los puertos de API 8000–8003 deben estar libres.

## Windows

Requisitos: Windows x64, PowerShell 5.1 y permisos de escritura en la carpeta de trabajo. Clona o extrae el repositorio completo dentro de una carpeta escribible del usuario, por ejemplo `C:\Users\TU_USUARIO\Documents\Servers_Scripts` o `D:\Proyectos\Servers_Scripts`. Entra en `windows\` y ejecuta:

```text
doble clic en iniciar.cmd
```

o en PowerShell:

```powershell
.\iniciar.cmd
```

- Panel: http://127.0.0.1:5500/ (o el que indique la consola)
- API: http://127.0.0.1:28000/ (puertos altos para evitar reservas de Hyper-V/WSL)

Incluye Python 3.12 x64 en `runtime\python` y paquetes offline en `vendor\wheels`; no utiliza el alias de Microsoft Store ni modifica el Python instalado en el sistema. En el primer arranque detecta el entorno, instala `pip` y dependencias que falten en el runtime local; si los wheels no bastan intenta PyPI (requiere internet). Puedes verificar la instalación sin iniciar servidores con `powershell -NoProfile -ExecutionPolicy Bypass -File .\iniciar.ps1 -CheckOnly`.

No coloques `windows\` en `C:\`, `C:\Program Files`, `C:\Windows` ni otra carpeta protegida: la instalación local necesita escribir allí y fallará sin permisos. **El disco C: no está prohibido**; `C:\Users\...\Documents` funciona si tu usuario tiene permisos. Tampoco basta con copiar solo `iniciar.cmd`: conserva toda la carpeta `windows\`, incluidos `runtime\` y `vendor\`.

La barra muestra etapas completadas, no un porcentaje inventado de instalación. Mientras se espera un puerto aparece un spinner braille en terminales UTF-8 interactivas, o caracteres ASCII cuando no son compatibles; la salida redirigida evita animaciones. Si un puerto de API está ocupado, el lanzador no cierra procesos ajenos: libera el puerto tú mismo y vuelve a ejecutar. La UI busca otro puerto disponible automáticamente. Los errores de los procesos se guardan en `windows\logs\`.

Compatibilidad: el paquete portable actual es **solo Windows x64**; no se promete funcionamiento en Windows de 32 bits ni en equipos con ejecución de PowerShell bloqueada por políticas corporativas.

## Nota sobre `venv/`

El entorno virtual de Linux **no** se sube al repo (no es portable a Windows y se regenera con `./iniciar.sh`). La carpeta `windows/runtime` sí viaja con el clone.
