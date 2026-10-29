#Requires -Version 5.1
<#
.SYNOPSIS
  Arranque 100% portable (cualquier disco/ruta) — servidores + FastAPI + panel.

.DESCRIPTION
  - Funciona desde E:\, D:\, USB, etc. (todo relativo a esta carpeta).
  - Usa runtime\python (Python embeddable incluido) si no hay Python real del sistema.
  - Ignora el alias falso de Microsoft Store (WindowsApps\python.exe).
  - Instala fastapi/uvicorn/httpx desde vendor\wheels (offline).

  Uso: doble clic en iniciar.cmd  |  .\iniciar.ps1
#>

$ErrorActionPreference = "Stop"

# Raiz = carpeta del script (sirve en cualquier unidad: C:, E:, USB...)
$Root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$Root = [System.IO.Path]::GetFullPath($Root)
Set-Location -LiteralPath $Root

$RuntimeDir = Join-Path $Root "runtime\python"
$RuntimePy = Join-Path $RuntimeDir "python.exe"
$GetPip = Join-Path $Root "runtime\get-pip.py"
$WheelsDir = Join-Path $Root "vendor\wheels"
$ReqFile = Join-Path $Root "requirements.txt"
$MarkerFile = Join-Path $RuntimeDir ".deps_ok"
$UiPortPref = if ($env:UI_PORT) { [int]$env:UI_PORT } else { 5500 }
$script:UiPort = $UiPortPref
$script:Procs = @()
$script:ProcLogs = @{}
$script:Py = $null

Write-Host "[*] Carpeta del proyecto: $Root" -ForegroundColor DarkGray

function Stop-All {
  Write-Host ""
  Write-Host "[*] Deteniendo procesos..." -ForegroundColor Yellow
  foreach ($p in $script:Procs) {
    if ($null -ne $p -and -not $p.HasExited) {
      try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
  }
  foreach ($port in @(28001, 28002, 28003, 28000, $script:UiPort, $UiPortPref)) {
    Free-Port $port | Out-Null
  }
}

function Test-PortBusy([int]$Port) {
  try {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
    $listener.Start()
    $listener.Stop()
    return $false
  } catch {
    return $true
  }
}

function Free-Port([int]$Port) {
  try {
    Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
      ForEach-Object {
        try {
          Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
          Write-Host "    liberado puerto $Port (PID $($_.OwningProcess))"
        } catch {}
      }
  } catch {}
  try {
    netstat -ano -p tcp | Select-String ":$Port\s+.*LISTENING" | ForEach-Object {
      $parts = ($_.ToString() -split '\s+') | Where-Object { $_ -ne '' }
      $procId = $parts[-1]
      if ($procId -match '^\d+$') {
        Stop-Process -Id ([int]$procId) -Force -ErrorAction SilentlyContinue
        Write-Host "    liberado puerto $Port (PID $procId)"
      }
    }
  } catch {}
  Start-Sleep -Milliseconds 300
  return -not (Test-PortBusy $Port)
}

function Ensure-PortFree([int]$Port, [string]$Name) {
  if (Test-PortBusy $Port) {
    Write-Host "[!] Puerto $Port ocupado ($Name). Liberando..." -ForegroundColor Yellow
    if (-not (Free-Port $Port)) {
      throw "No se pudo liberar :$Port"
    }
  }
}

function Quote-Arg([string]$Value) {
  if ($null -eq $Value) { return '""' }
  if ($Value -match '[\s"]') {
    return '"' + ($Value -replace '"', '\"') + '"'
  }
  return $Value
}

function Wait-Port([int]$Port, [string]$Name, $Process = $null, [string]$LogFile = $null) {
  # Hasta ~25s (USB/discos lentos)
  for ($i = 0; $i -lt 100; $i++) {
    if ($null -ne $Process) {
      $Process.Refresh()
      if ($Process.HasExited) {
        $tail = ""
        if ($LogFile -and (Test-Path -LiteralPath $LogFile)) {
          $tail = Get-Content -LiteralPath $LogFile -Raw -ErrorAction SilentlyContinue
        }
        throw @"
$Name termino antes de abrir el puerto :$Port (exit $($Process.ExitCode)).
Log: $LogFile

$tail
"@
      }
    }

    try {
      $client = New-Object System.Net.Sockets.TcpClient
      $iar = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
      $ok = $iar.AsyncWaitHandle.WaitOne(200, $false)
      if ($ok -and $client.Connected) {
        $client.EndConnect($iar) | Out-Null
        $client.Close()
        Write-Host "    OK $Name listo en :$Port" -ForegroundColor Green
        return
      }
      $client.Close()
    } catch {}
    Start-Sleep -Milliseconds 250
  }

  $tail = ""
  if ($LogFile -and (Test-Path -LiteralPath $LogFile)) {
    $tail = Get-Content -LiteralPath $LogFile -Raw -ErrorAction SilentlyContinue
  }
  throw @"
Timeout esperando $Name (:$Port).
Log: $LogFile

$tail
"@
}

function Start-Bg {
  param(
    [Parameter(Mandatory = $true)][string]$FileName,
    [Parameter(Mandatory = $true)][string[]]$ArgumentList,
    [string]$LogName = "proc"
  )

  $logsDir = Join-Path $Root "logs"
  New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
  $logFile = Join-Path $logsDir ($LogName + ".log")
  if (Test-Path -LiteralPath $logFile) {
    Remove-Item -LiteralPath $logFile -Force -ErrorAction SilentlyContinue
  }

  $argLine = ($ArgumentList | ForEach-Object { Quote-Arg $_ }) -join " "
  $exeQuoted = Quote-Arg $FileName
  $logQuoted = Quote-Arg $logFile
  $rootQuoted = Quote-Arg $Root

  # cmd.exe + redireccion: fiable en cualquier disco; evita bug ArgumentList de PS 5.1
  $runtimeBin = [System.IO.Path]::GetDirectoryName($FileName)
  $pre = "set PYTHONUNBUFFERED=1&& set PYTHONIOENCODING=utf-8&& set PYTHONPATH=$rootQuoted&&"
  if ($runtimeBin) {
    $pre = "set `"PATH=$runtimeBin;%PATH%`"&& " + $pre
  }
  $cmdline = "/c $pre $exeQuoted $argLine > $logQuoted 2>&1"

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $env:ComSpec
  $psi.Arguments = $cmdline
  $psi.WorkingDirectory = $Root
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true

  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  $null = $p.Start()

  $script:Procs += $p
  $script:ProcLogs[$p.Id] = $logFile
  return $p
}

function Test-RealPython([string]$Exe) {
  if (-not $Exe -or -not (Test-Path -LiteralPath $Exe)) { return $false }
  # Alias falso de Microsoft Store
  if ($Exe -match 'WindowsApps\\python') { return $false }
  if ($Exe -match 'WindowsApps/') { return $false }
  try {
    $out = & $Exe -c "import sys; assert sys.version_info >= (3, 10); print(sys.version_info[0], sys.version_info[1], sep='.')" 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    return [bool]$out
  } catch {
    return $false
  }
}

function Enable-EmbeddableSite {
  $pth = Get-ChildItem -LiteralPath $RuntimeDir -Filter "python*._pth" -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $pth) { return }
  @"
python312.zip
.
Lib\site-packages
import site
"@ | Set-Content -LiteralPath $pth.FullName -Encoding ASCII
}

function Ensure-PortableRuntime {
  if (-not (Test-Path -LiteralPath $RuntimePy)) {
    throw @"
No esta el Python portable en:
  $RuntimePy

Copia completa la carpeta 'windows' (incluye runtime\python y vendor\wheels).
"@
  }
  Enable-EmbeddableSite
  New-Item -ItemType Directory -Force -Path (Join-Path $RuntimeDir "Lib\site-packages") | Out-Null
}

function Ensure-Pip {
  $pipOk = $false
  try {
    & $script:Py -m pip --version 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $pipOk = $true }
  } catch { $pipOk = $false }

  if ($pipOk) { return }

  if (-not (Test-Path -LiteralPath $GetPip)) {
    throw "Falta runtime\get-pip.py para instalar pip en el Python portable."
  }

  Write-Host "[*] Instalando pip en el runtime portable..." -ForegroundColor Cyan
  & $script:Py $GetPip --no-warn-script-location --disable-pip-version-check
  if ($LASTEXITCODE -ne 0) {
    throw "No se pudo instalar pip en el runtime portable."
  }
}

function Test-DepsOk {
  try {
    & $script:Py -c "import fastapi, uvicorn, httpx; print('ok')" 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
  } catch {
    return $false
  }
}

function Install-Libraries {
  if (Test-DepsOk) {
    Write-Host "[*] Librerias OK (fastapi/uvicorn/httpx ya disponibles)." -ForegroundColor Green
    return
  }

  Ensure-Pip

  $wheelCount = 0
  if (Test-Path -LiteralPath $WheelsDir) {
    $wheelCount = @(Get-ChildItem -LiteralPath $WheelsDir -Filter *.whl -ErrorAction SilentlyContinue).Count
  }

  Write-Host "[*] Instalando librerias Python automaticamente..." -ForegroundColor Cyan
  if ($wheelCount -gt 0) {
    Write-Host "    Fuente: vendor\wheels ($wheelCount paquetes, offline)" -ForegroundColor DarkGray
    & $script:Py -m pip install --no-index --find-links $WheelsDir -r $ReqFile --disable-pip-version-check
    if ($LASTEXITCODE -eq 0 -and (Test-DepsOk)) {
      "ok $(Get-Date -Format o)" | Set-Content -LiteralPath $MarkerFile -Encoding UTF8
      Write-Host "    OK instalacion desde wheels locales." -ForegroundColor Green
      return
    }
    Write-Host "    Offline incompleto. Intentando PyPI (internet)..." -ForegroundColor Yellow
  } else {
    Write-Host "    Sin vendor\wheels. Intentando PyPI..." -ForegroundColor Yellow
  }

  & $script:Py -m pip install -r $ReqFile --disable-pip-version-check
  if ($LASTEXITCODE -ne 0 -or -not (Test-DepsOk)) {
    throw "No se pudieron instalar las librerias. Revisa vendor\wheels o la conexion a internet."
  }
  "ok $(Get-Date -Format o)" | Set-Content -LiteralPath $MarkerFile -Encoding UTF8
  Write-Host "    OK librerias instaladas." -ForegroundColor Green
}

function Resolve-Python {
  # 1) Python portable incluido (preferido: no depende del sistema ni del disco)
  if (Test-RealPython $RuntimePy) {
    Write-Host "[*] Usando Python portable: $RuntimePy" -ForegroundColor Cyan
    return $RuntimePy
  }

  # 2) Python real del sistema (nunca WindowsApps)
  $candidates = New-Object System.Collections.Generic.List[string]

  $pyLauncher = Get-Command py -ErrorAction SilentlyContinue
  if ($pyLauncher -and $pyLauncher.Source -notmatch 'WindowsApps') {
    foreach ($ver in @("-3.12", "-3.13", "-3.11", "-3.10", "-3")) {
      try {
        $exe = & $pyLauncher.Source $ver -c "import sys; print(sys.executable)" 2>$null
        if ($exe) { $candidates.Add($exe.Trim()) }
      } catch {}
    }
  }

  foreach ($name in @("python", "python3")) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { $candidates.Add($cmd.Source) }
  }

  foreach ($c in $candidates) {
    if (Test-RealPython $c) {
      Write-Host "[*] Usando Python del sistema: $c" -ForegroundColor Cyan
      return $c
    }
  }

  # 3) Portable presente pero Test-RealPython fallo (primera vez sin ._pth): forzar
  if (Test-Path -LiteralPath $RuntimePy) {
    Ensure-PortableRuntime
    if (Test-RealPython $RuntimePy) {
      Write-Host "[*] Usando Python portable (activado): $RuntimePy" -ForegroundColor Cyan
      return $RuntimePy
    }
  }

  throw @"
No se encontro un Python usable.

- El acceso directo de Microsoft Store (WindowsApps) NO sirve.
- Esta carpeta debe incluir runtime\python\python.exe (Python portable).

Copia de nuevo la carpeta 'windows' completa y ejecuta iniciar.cmd
"@
}

try {
  Ensure-PortableRuntime
  $script:Py = Resolve-Python
  Install-Libraries

  # Puertos 2800x: evitan rangos reservados por Hyper-V/WSL en Windows (~8000)
  Ensure-PortFree 28001 "Servidor 1"
  Ensure-PortFree 28002 "Servidor 2"
  Ensure-PortFree 28003 "Servidor 3"
  Ensure-PortFree 28000 "Balanceador"
  if (Test-PortBusy $UiPortPref) { Free-Port $UiPortPref | Out-Null }

  $servidoresPy = Join-Path $Root "servidores.py"

  Write-Host "[*] Iniciando Servidor 1 -> :28001" -ForegroundColor Cyan
  $p1 = Start-Bg -FileName $script:Py -ArgumentList @($servidoresPy, "28001", "Servidor 1") -LogName "servidor-28001"
  Write-Host "[*] Iniciando Servidor 2 -> :28002" -ForegroundColor Cyan
  $p2 = Start-Bg -FileName $script:Py -ArgumentList @($servidoresPy, "28002", "Servidor 2") -LogName "servidor-28002"
  Write-Host "[*] Iniciando Servidor 3 -> :28003" -ForegroundColor Cyan
  $p3 = Start-Bg -FileName $script:Py -ArgumentList @($servidoresPy, "28003", "Servidor 3") -LogName "servidor-28003"

  Wait-Port 28001 "Servidor 1" $p1 $script:ProcLogs[$p1.Id]
  Wait-Port 28002 "Servidor 2" $p2 $script:ProcLogs[$p2.Id]
  Wait-Port 28003 "Servidor 3" $p3 $script:ProcLogs[$p3.Id]

  Write-Host "[*] Iniciando balanceador FastAPI -> :28000" -ForegroundColor Cyan
  $pb = Start-Bg -FileName $script:Py -ArgumentList @(
    "-m", "uvicorn", "balanceador:app",
    "--host", "127.0.0.1", "--port", "28000"
  ) -LogName "balanceador-28000"
  Wait-Port 28000 "Balanceador" $pb $script:ProcLogs[$pb.Id]

  Write-Host "[*] Sirviendo panel web (preferido :$UiPortPref)..." -ForegroundColor Cyan
  $uiProc = Start-Bg -FileName $script:Py -ArgumentList @(
    (Join-Path $Root "servir_ui.py"), "$UiPortPref", "--root", "$Root"
  ) -LogName "ui"
  $uiLog = $script:ProcLogs[$uiProc.Id]

  $script:UiPort = $null
  for ($i = 0; $i -lt 80; $i++) {
    if (Test-Path -LiteralPath $uiLog) {
      $line = Select-String -LiteralPath $uiLog -Pattern '^UI_PORT=' -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($line) {
        $script:UiPort = ($line.Line -split '=', 2)[1].Trim()
        break
      }
    }
    $uiProc.Refresh()
    if ($uiProc.HasExited) {
      $content = if (Test-Path -LiteralPath $uiLog) { Get-Content -LiteralPath $uiLog -Raw } else { "(sin log)" }
      throw "Fallo el servidor de la UI:`n$content"
    }
    Start-Sleep -Milliseconds 150
  }

  if (-not $script:UiPort) {
    $content = if (Test-Path -LiteralPath $uiLog) { Get-Content -LiteralPath $uiLog -Raw } else { "(sin log)" }
    throw "No se pudo determinar el puerto de la UI.`n$content"
  }
  Wait-Port ([int]$script:UiPort) "UI estatica" $uiProc $uiLog

  Write-Host ""
  Write-Host "==============================================" -ForegroundColor Green
  Write-Host "  Panel:       http://127.0.0.1:$($script:UiPort)/"
  Write-Host "  Balanceador: http://127.0.0.1:28000/"
  Write-Host "  Docs API:    http://127.0.0.1:28000/docs"
  Write-Host "  Logs:        $Root\logs\"
  Write-Host "  Python:      $script:Py"
  Write-Host "  Raiz:        $Root"
  Write-Host "  Ctrl+C para detener todo"
  Write-Host "==============================================" -ForegroundColor Green
  Write-Host ""

  try { Start-Process "http://127.0.0.1:$($script:UiPort)/" | Out-Null } catch {}

  while ($true) {
    $dead = $script:Procs | Where-Object { $_.HasExited }
    if ($dead) {
      Write-Host "[!] Proceso terminado (PID $($dead[0].Id))." -ForegroundColor Red
      break
    }
    Start-Sleep -Seconds 1
  }
}
finally {
  Stop-All
}
