# No installation changes. Stop on compiler/runtime failure; a log must contain PASS.
param([string]$Vivado='E:\AppDownloadE\Vitis\Vivado\2024.2',
      [ValidateSet('both','pipeline','integration')][string]$Suite='both')
$ErrorActionPreference='Stop'
$projectDir=Split-Path $PSScriptRoot -Parent
$workspace=(Resolve-Path (Join-Path $projectDir '../../..')).Path
$output=Join-Path $workspace 'Claude_Temp/PID_Motor_validation'
New-Item -ItemType Directory -Force $output | Out-Null
$sources=@(
    "$projectDir/src/top.v", "$projectDir/src/MyPID.v",
    "$workspace/DLB/DLB/DLB.srcs/sources_1/new/tb6612_motor_driver.v",
    "$workspace/DLB/DLB/DLB.srcs/sources_1/new/encoder_quad.v",
    "$workspace/DLB/DLB/DLB.srcs/sources_1/new/PWM.v",
    "$projectDir/../uart_loopback/src/uart_byte_rx.v",
    "$projectDir/../uart_loopback/src/uart_byte_tx.v",
    "$PSScriptRoot/tb_pid_motor.sv", "$PSScriptRoot/tb_pid_pipeline.sv"
)
Push-Location $output
try {
    & "$Vivado/bin/xvlog.bat" -sv @sources
    if($LASTEXITCODE -ne 0){throw 'xvlog failed'}
    $suites=@()
    if($Suite -ne 'integration'){$suites+=@{Top='tb_pid_pipeline';Snapshot='pid_pipeline_sim';Pass='PASS PID pipeline:'}}
    if($Suite -ne 'pipeline'){$suites+=@{Top='tb_pid_motor';Snapshot='pid_sim';Pass='PASS PID_Motor:'}}
    foreach($test in $suites){
        & "$Vivado/bin/xelab.bat" $test.Top -s $test.Snapshot -debug typical
        if($LASTEXITCODE -ne 0){throw 'xelab failed; simulation has NOT passed'}
        $log=$test.Snapshot+'.log'
        & "$Vivado/bin/xsim.bat" $test.Snapshot -runall -log $log
        if($LASTEXITCODE -ne 0){throw 'xsim failed'}
        if(!(Select-String -LiteralPath $log -Pattern $test.Pass -Quiet)) {
            throw 'No self-check PASS marker; simulation has NOT passed'
        }
    }
} finally { Pop-Location }
