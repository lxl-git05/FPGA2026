param([string]$VivadoBin = '')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$sourceRoot = Join-Path $workspace 'DLB/DLB/DLB.srcs/sources_1/new'
$tempRoot = Join-Path $workspace 'Claude_Temp/PID_UART_validation'
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
if (!$VivadoBin) { $VivadoBin = Split-Path (Get-Command xvlog.bat -ErrorAction Stop).Source -Parent }
$files = 'Test.v','MyPID.v','Key.v','Seg8.v','encoder_quad.v','tb6612_motor_driver.v','PWM.v','protocol_rx.v','protocol_tx.v','parameter_manager.v','telemetry_param_mux.v','uart_byte_rx.v','uart_byte_tx.v'
$sourceFiles = @($files | ForEach-Object { Join-Path $sourceRoot $_ })
Push-Location $tempRoot
try {
    & (Join-Path $VivadoBin 'xvlog.bat') --sv @sourceFiles (Join-Path $workspace 'DLB/tests/pid_uart_tb.sv')
    if ($LASTEXITCODE) { throw 'xvlog failed' }
    & (Join-Path $VivadoBin 'xelab.bat') pid_uart_tb -s pid_uart_sim -debug typical
    if ($LASTEXITCODE) { throw 'xelab failed' }
    & (Join-Path $VivadoBin 'xsim.bat') pid_uart_sim -runall -log pid_uart_sim.log
    if ($LASTEXITCODE) { throw 'xsim failed' }
    $simulationLog = Get-Content -LiteralPath 'pid_uart_sim.log' -Raw
    if ($simulationLog -notmatch 'PASS:' -or $simulationLog -match '(Fatal:|Error:)') { throw 'Simulation did not pass' }
} finally { Pop-Location }
