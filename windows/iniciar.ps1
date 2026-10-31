#Requires -Version 5.1
<#
.SYNOPSIS
  Arranque 100% portable (cualquier disco/ruta) — servidores + FastAPI + panel.

.DESCRIPTION
  - Funciona desde carpetas escribibles en C:\, D:\, USB, etc.
  - Usa el Python 3.12 x64 embebido; no necesita Python del sistema.
  - Instala fastapi/uvicorn/httpx desde vendor\wheels (offline).

  Uso: doble clic en iniciar.cmd  |  .\iniciar.ps1
#>

param([switch]$CheckOnly, [switch]$NoBrowser)
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

$UiPortPref = if ($env:UI_PORT) { [int]$env:UI_PORT } else { 5500 }
$script:UiPort = $UiPortPref
$script:Procs = @()
$script:ProcLogs = @{}
$script:Py = $null
$script:SetupProcess = $null
$script:Stage = 0
$script:StageCount = 8
$script:Interactive = [Environment]::UserInteractive -and -not [Console]::IsOutputRedirected
if ($script:Interactive -and $env:WT_SESSION) {
  try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}
}
$script:Braille = $script:Interactive -and [Console]::OutputEncoding.WebName -eq 'utf-8'

function Show-Stage([string]$Message) {
  $script:Stage++
  $width = 14
  $filled = [int][Math]::Floor($script:Stage * $width / $script:StageCount)
  $bar = ('#' * $filled) + ('-' * ($width - $filled))
  Write-Host "[$bar] $($script:Stage)/$($script:StageCount) $Message" -ForegroundColor Cyan
}

function Show-Wait([string]$Message, [int]$Tick) {
  if (-not $script:Interactive) { return }
  $frames = if ($script:Braille) { @(0x280B,0x2819,0x2839,0x2838,0x283C,0x2834,0x2826,0x2827,0x2807,0x280F) | ForEach-Object { [char]$_ } } else { @('|','/','-','\') }
  Write-Host "`r    $Message $($frames[$Tick % $frames.Count])   " -NoNewline -ForegroundColor Yellow
}

function Clear-Wait {
  if ($script:Interactive) { Write-Host '' }
}

function Test-Workspace {
  if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'El paquete incluye Python y wheels para Windows x64; Windows de 32 bits no es compatible.'
  }
  foreach ($file in @($RuntimePy, $GetPip, $ReqFile, (Join-Path $Root 'servidores.py'), (Join-Path $Root 'balanceador.py'), (Join-Path $Root 'servir_ui.py'), (Join-Path $Root 'index.html'))) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Copia incompleta; falta: $file" }
  }
  $probe = Join-Path $Root ('.write-test-' + [guid]::NewGuid().ToString('N'))
  try {
    [System.IO.File]::WriteAllText($probe, 'ok')
    [System.IO.File]::Delete($probe)
    $runtimeProbe = Join-Path $RuntimeDir ('.write-test-' + [guid]::NewGuid().ToString('N'))
    [System.IO.File]::WriteAllText($runtimeProbe, 'ok')
    [System.IO.File]::Delete($runtimeProbe)
  } catch {
    Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    if ($runtimeProbe) { Remove-Item -LiteralPath $runtimeProbe -Force -ErrorAction SilentlyContinue }
    throw "No se puede escribir en '$Root'. Mueve la carpeta a Documentos u otra ruta con permisos (C: tambien sirve). Detalle: $_"
  }
}

Write-Host "[*] Carpeta del proyecto: $Root" -ForegroundColor DarkGray

function Stop-All {
  if ($null -ne $script:SetupProcess -and -not $script:SetupProcess.HasExited) {
    try { Stop-Process -Id $script:SetupProcess.Id -Force -ErrorAction SilentlyContinue } catch {}
  }
  Write-Host ""
  Write-Host "[*] Deteniendo procesos..." -ForegroundColor Yellow
  foreach ($p in $script:Procs) {
    if ($null -ne $p -and -not $p.HasExited) {
      try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
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

function Ensure-PortFree([int]$Port, [string]$Name) {
  if (Test-PortBusy $Port) {
    throw "Puerto $Port ocupado ($Name). Cierra la aplicacion que lo utiliza; no se cerraran procesos ajenos."
  }
}

function Quote-Arg([string]$Value) {
  if ($null -eq $Value) { return '""' }
  if ($Value -match '[\s"]') {
    return '"' + ($Value -replace '"', '\"') + '"'
  }
  return $Value
}

function Invoke-PythonTask {
  param([string[]]$Arguments, [string]$Message)
  $logsDir = Join-Path $Root 'logs'
  New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
  $base = Join-Path $logsDir ('setup-' + [guid]::NewGuid().ToString('N'))
  $out = $base + '.out.log'
  $err = $base + '.err.log'
  $argLine = ($Arguments | ForEach-Object { Quote-Arg $_ }) -join ' '
  try {
    $script:SetupProcess = Start-Process -FilePath $script:Py -ArgumentList $argLine -WorkingDirectory $Root -PassThru -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden
    $tick = 0
    while (-not $script:SetupProcess.HasExited) {
      Show-Wait $Message $tick
      $tick++
      Start-Sleep -Milliseconds 120
      $script:SetupProcess.Refresh()
    }
    $script:SetupProcess.WaitForExit()
    Clear-Wait
    foreach ($file in @($out, $err)) {
      if (Test-Path -LiteralPath $file) { Get-Content -LiteralPath $file | ForEach-Object { Write-Host $_ } }
    }
    $exitCode = $script:SetupProcess.ExitCode
  } finally {
    Clear-Wait
    if ($null -ne $script:SetupProcess -and -not $script:SetupProcess.HasExited) {
      Stop-Process -Id $script:SetupProcess.Id -Force -ErrorAction SilentlyContinue
    }
    $script:SetupProcess = $null
    Remove-Item -LiteralPath $out, $err -Force -ErrorAction SilentlyContinue
  }
  return $exitCode
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
        Clear-Wait
        Write-Host "    OK $Name listo en :$Port" -ForegroundColor Green
        return
      }
      $client.Close()
    } catch {}
    Show-Wait "Esperando $Name" $i
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
  $errorFile = Join-Path $logsDir ($LogName + ".err.log")
  if (Test-Path -LiteralPath $logFile) {
    Remove-Item -LiteralPath $logFile -Force -ErrorAction SilentlyContinue
  }
  if (Test-Path -LiteralPath $errorFile) {
    Remove-Item -LiteralPath $errorFile -Force -ErrorAction SilentlyContinue
  }

  $argLine = ($ArgumentList | ForEach-Object { Quote-Arg $_ }) -join " "
  $p = Start-Process -FilePath $FileName -ArgumentList $argLine -WorkingDirectory $Root -PassThru -RedirectStandardOutput $logFile -RedirectStandardError $errorFile -WindowStyle Hidden

  $script:Procs += $p
  $script:ProcLogs[$p.Id] = $logFile
  return $p
}

function Enable-EmbeddableSite {
  $pth = Get-ChildItem -LiteralPath $RuntimeDir -Filter "python*._pth" -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $pth) { throw 'Falta python312._pth en el runtime portable.' }
  @"
python312.zip
.
Lib\site-packages
import site
"@ | Set-Content -LiteralPath $pth.FullName -Encoding ASCII
}

function Ensure-PortableRuntime {
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
  $status = Invoke-PythonTask -Arguments @($GetPip, '--no-warn-script-location', '--disable-pip-version-check') -Message 'Instalando pip'
  if ($status -ne 0) {
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
  $depsOk = Test-DepsOk
  Clear-Wait
  if ($depsOk) {
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
    $status = Invoke-PythonTask -Arguments @('-m', 'pip', 'install', '--no-index', '--find-links', $WheelsDir, '-r', $ReqFile, '--disable-pip-version-check') -Message 'Instalando paquetes offline'
    if ($status -eq 0 -and (Test-DepsOk)) {
      Write-Host "    OK instalacion desde wheels locales." -ForegroundColor Green
      return
    }
    Write-Host "    Offline incompleto. Intentando PyPI (internet)..." -ForegroundColor Yellow
  } else {
    Write-Host "    Sin vendor\wheels. Intentando PyPI..." -ForegroundColor Yellow
  }

  $status = Invoke-PythonTask -Arguments @('-m', 'pip', 'install', '-r', $ReqFile, '--disable-pip-version-check') -Message 'Instalando paquetes desde PyPI'
  if ($status -ne 0 -or -not (Test-DepsOk)) {
    throw "No se pudieron instalar las librerias. Revisa vendor\wheels o la conexion a internet."
  }
  Write-Host "    OK librerias instaladas." -ForegroundColor Green
}

try {
  $env:PYTHONUNBUFFERED = '1'
  $env:PYTHONIOENCODING = 'utf-8'
  $env:PYTHONPATH = $Root
  $env:PATH = "$RuntimeDir;$env:PATH"
  Show-Stage 'Comprobando permisos y archivos'
  Show-Wait 'Comprobando sistema' 0
  Test-Workspace
  Clear-Wait
  Show-Stage 'Preparando Python portable x64'
  Show-Wait 'Preparando Python' 0
  Ensure-PortableRuntime
  $script:Py = $RuntimePy
  & $script:Py -c "import sys; assert sys.version_info[:2] == (3, 12) and sys.maxsize > 2**32" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'El runtime incluido no es Python 3.12 x64 o no puede ejecutarse en este equipo.' }
  Clear-Wait
  Show-Stage 'Verificando dependencias Python'
  Show-Wait 'Verificando librerias' 0
  Install-Libraries
  if ($CheckOnly) { Write-Host 'Comprobacion completada; no se iniciaron servidores.'; return }

  # Puertos 2800x: evitan rangos reservados por Hyper-V/WSL en Windows (~8000)
  Show-Stage 'Comprobando puertos sin cerrar otros programas'
  Ensure-PortFree 28001 "Servidor 1"
  Ensure-PortFree 28002 "Servidor 2"
  Ensure-PortFree 28003 "Servidor 3"
  Ensure-PortFree 28000 "Balanceador"
  if ($UiPortPref -lt 1 -or $UiPortPref -gt 65506) { throw 'UI_PORT debe estar entre 1 y 65506.' }

  $servidoresPy = Join-Path $Root "servidores.py"

  Show-Stage 'Iniciando tres servidores'
  $p1 = Start-Bg -FileName $script:Py -ArgumentList @($servidoresPy, "28001", "Servidor 1") -LogName "servidor-28001"
  Write-Host "[*] Iniciando Servidor 2 -> :28002" -ForegroundColor Cyan
  $p2 = Start-Bg -FileName $script:Py -ArgumentList @($servidoresPy, "28002", "Servidor 2") -LogName "servidor-28002"
  Write-Host "[*] Iniciando Servidor 3 -> :28003" -ForegroundColor Cyan
  $p3 = Start-Bg -FileName $script:Py -ArgumentList @($servidoresPy, "28003", "Servidor 3") -LogName "servidor-28003"

  Wait-Port 28001 "Servidor 1" $p1 $script:ProcLogs[$p1.Id]
  Wait-Port 28002 "Servidor 2" $p2 $script:ProcLogs[$p2.Id]
  Wait-Port 28003 "Servidor 3" $p3 $script:ProcLogs[$p3.Id]

  Show-Stage 'Iniciando balanceador FastAPI'
  $pb = Start-Bg -FileName $script:Py -ArgumentList @(
    "-m", "uvicorn", "balanceador:app",
    "--host", "127.0.0.1", "--port", "28000"
  ) -LogName "balanceador-28000"
  Wait-Port 28000 "Balanceador" $pb $script:ProcLogs[$pb.Id]

  Show-Stage 'Iniciando panel web'
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
    Show-Wait 'Esperando panel web' $i
    Start-Sleep -Milliseconds 150
  }

  if (-not $script:UiPort) {
    $content = if (Test-Path -LiteralPath $uiLog) { Get-Content -LiteralPath $uiLog -Raw } else { "(sin log)" }
    throw "No se pudo determinar el puerto de la UI.`n$content"
  }
  Wait-Port ([int]$script:UiPort) "UI estatica" $uiProc $uiLog
  Show-Stage 'Servicios listos'

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

  if (-not $NoBrowser) { try { Start-Process "http://127.0.0.1:$($script:UiPort)/" | Out-Null } catch {} }

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
