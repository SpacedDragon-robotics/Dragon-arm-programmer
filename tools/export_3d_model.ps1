# export_3d_model.ps1 -- rebuild the Dragon-Arm One model used by the 3D view.
#
#   powershell -ExecutionPolicy Bypass -File tools\export_3d_model.ps1
#
# 1. Blender bakes the rigged .blend into per-joint, per-material meshes
#    (tools/export_3d_model.py; the .blend is opened read-only, never saved).
# 2. balsam converts the GLB into Qt Quick 3D .mesh files.
# 3. The generated rig QML and the meshes replace content/view3d/rigs/dragon-arm-one/.
#
# Only needed when the CAD changes. The paths below are this machine's; pass
# your own with -Blender / -Balsam / -Blend.

param(
    # The trailer file carries the corrected part-to-joint assignments and the
    # gripper; dragon_arm_gen1.blend has mounts on the wrong links.
    [string]$Blend   = "D:\Claude\dragon-arm\dragon_arm_trailer.blend",
    [string]$Blender = "D:\programy\steam\steamapps\common\Blender\blender.exe",
    [string]$Balsam  = "D:\programy\Qt\6.11.2\mingw_64\bin\balsam.exe",
    [double]$Ratio   = 0.2
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path $env:TEMP "spacedragon_3d_export"
$dest = Join-Path $root "content\view3d\rigs\dragon-arm-one"

if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory -Force $work | Out-Null

& $Blender -b $Blend -P (Join-Path $PSScriptRoot "export_3d_model.py") -- $work $Ratio |
    Select-String -Pattern "EXPORTED|CAL|Error|Traceback" | ForEach-Object { $_.Line }
if (-not (Test-Path (Join-Path $work "dragon_arm_one.glb"))) { throw "Blender export failed" }

& $Balsam --disable-generateSmoothNormals --disable-optimizeMeshes --disable-optimizeGraph `
          --disable-fixInfacingNormals -o (Join-Path $work "balsam") (Join-Path $work "dragon_arm_one.glb") | Out-Null
$meshes = Join-Path $work "balsam\meshes"
if (-not (Test-Path $meshes)) { throw "balsam conversion failed" }

New-Item -ItemType Directory -Force (Join-Path $dest "meshes") | Out-Null
Get-ChildItem (Join-Path $dest "meshes") -Filter *.mesh | Remove-Item -Force
Copy-Item (Join-Path $meshes "*.mesh") (Join-Path $dest "meshes")
Copy-Item (Join-Path $work "DragonArmOneRig.qml") $dest -Force
Copy-Item (Join-Path $work "rig.json") $dest -Force

# Every mesh the QML names must exist, or the model silently loses parts.
$qml = Get-Content (Join-Path $dest "DragonArmOneRig.qml") -Raw
$missing = [regex]::Matches($qml, 'meshes/([^"]+\.mesh)') | ForEach-Object { $_.Groups[1].Value } |
    Where-Object { -not (Test-Path (Join-Path $dest "meshes\$_")) }
if ($missing) { throw "Missing meshes: $($missing -join ', ')" }

$size = (Get-ChildItem (Join-Path $dest "meshes") | Measure-Object Length -Sum).Sum / 1MB
"Rig written to $dest ({0:N1} MB of meshes). Re-run cmake before a release build." -f $size
