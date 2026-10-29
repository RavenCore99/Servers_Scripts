# Servers_Scripts

Panel de administración de **servidores dinámicos** + API FastAPI (balanceador + nodos) + UI web.

Repositorio pensado para que cualquier compañero clone y pruebe en Linux o Windows.

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

- Panel: http://127.0.0.1:5500/
- API: http://127.0.0.1:8000/

Requisito: Python 3.10+. El script crea `venv` e instala dependencias.

## Windows

Copia o clona el repo y entra en `windows\`:

```text
doble clic en iniciar.cmd
```

o en PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\iniciar.ps1
```

- Panel: http://127.0.0.1:5500/ (o el que indique la consola)
- API: http://127.0.0.1:28000/ (puertos altos para evitar reservas de Hyper-V/WSL)

Incluye `runtime\python` y `vendor\wheels`: no hace falta instalar librerías a mano. Ignora el alias falso de Microsoft Store.

## Nota sobre `venv/`

El entorno virtual de Linux **no** se sube al repo (no es portable a Windows y se regenera con `./iniciar.sh`). La carpeta `windows/runtime` sí viaja con el clone.
