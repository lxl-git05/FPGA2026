param([string]$Vivado='E:\AppDownloadE\Vitis\Vivado\2024.2')
$ErrorActionPreference='Stop'
$projectDir=Split-Path $PSScriptRoot -Parent
$workspace=(Resolve-Path (Join-Path $projectDir '../../..')).Path
$output=Join-Path $workspace 'Claude_Temp/DLB_refactor'
New-Item -ItemType Directory -Force $output | Out-Null
[xml]$project=(Get-Content "$projectDir/DLB.gprj" -Raw).Replace('version="1"','version="1.0"')
$sources=@($project.Project.FileList.File | Where-Object {$_.type -eq 'file.verilog'} |
    ForEach-Object {Join-Path $projectDir $_.path})
$sources+=@(Get-ChildItem $PSScriptRoot -Filter '*.sv' | ForEach-Object {$_.FullName})
Push-Location $output
try {
    & "$Vivado/bin/xvlog.bat" -sv @sources
    if($LASTEXITCODE -ne 0){throw 'RTL/testbench compile failed'}
    $failures=@()
    foreach($name in @('protocol','safety','adc_range_only','pid_safety','swing','cascade','telemetry')) {
        $snapshot='dlb_'+$name
        & "$Vivado/bin/xelab.bat" ('tb_'+$name) -s $snapshot -debug typical -log ($snapshot+'_elab.log')
        if($LASTEXITCODE -ne 0){$failures+=$name+': elaboration/toolchain';continue}
        & "$Vivado/bin/xsim.bat" $snapshot -runall -log ($snapshot+'.log')
        if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath ($snapshot+'.log') -Pattern '^PASS ' -Quiet)) {
            $failures+=$name+': no self-check PASS'
        }
    }
    if($failures.Count){throw ('Simulation NOT passed: '+($failures -join ', '))}
} finally {Pop-Location}
