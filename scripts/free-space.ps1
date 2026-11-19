# Frees space on C: when a build fails with "not enough space on the disk".
#
#   powershell -ExecutionPolicy Bypass -File scripts/free-space.ps1
#
# Deletes only what Windows' own Disk Cleanup would: items in the user's
# Temp folder untouched for a day (leftover installers, old build scratch).
# Anything in use is skipped, and Claude Code's session folder is kept.

$temp = Join-Path $env:LOCALAPPDATA "Temp"
$cutoff = (Get-Date).AddDays(-1)
$before = (Get-PSDrive C).Free

Get-ChildItem $temp -Force -ErrorAction SilentlyContinue |
  Where-Object { $_.LastWriteTime -lt $cutoff -and $_.Name -ne "claude" } |
  ForEach-Object {
    try { Remove-Item $_.FullName -Recurse -Force -Confirm:$false -ErrorAction Stop } catch {}
  }

$after = (Get-PSDrive C).Free
"Freed {0:N1} GB. C: now has {1:N1} GB free." -f (($after - $before) / 1GB), ($after / 1GB)
