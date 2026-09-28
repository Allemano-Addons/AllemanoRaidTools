# img2tga.ps1 - make a Visual note background from a screenshot or picture (PNG/JPG/BMP).
# Fits the picture into 1024x512 (the canvas is 2:1), centered on a dark background, and
# writes an uncompressed 32-bit TGA that WoW loads. Put the result in
# SlaughterRaidTools\Images\ and RESTART the game (a /reload does not find new files).
# Usage: powershell -ExecutionPolicy Bypass -File img2tga.ps1 -Src shot.png [-Name ony_p2]
param(
    [Parameter(Mandatory = $true)][string]$Src,
    [string]$Name = ""
)
Add-Type -AssemblyName System.Drawing
# Note: PowerShell variable names ignore case, so $W and $w would be the same variable.
$W = 1024; $H = 512
if ($Name -eq "") { $Name = [System.IO.Path]::GetFileNameWithoutExtension($Src) }
# Only letters, digits, _ and - (the name is typed in the game).
$Name = ($Name -replace '[^A-Za-z0-9_-]', '_').ToLower()
$dir = Join-Path (Split-Path -Parent $PSScriptRoot) "Images"
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
$Dst = Join-Path $dir ($Name + ".tga")

$img = New-Object System.Drawing.Bitmap $Src
$scale = [Math]::Min($W / $img.Width, $H / $img.Height)
$pw = [int][Math]::Round($img.Width * $scale); $ph = [int][Math]::Round($img.Height * $scale)
$out = New-Object System.Drawing.Bitmap $W, $H, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($out)
$g.Clear([System.Drawing.Color]::FromArgb(255, 17, 20, 24))
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($img, [int](($W - $pw) / 2), [int](($H - $ph) / 2), $pw, $ph)
$g.Dispose(); $img.Dispose()

# Pixels as BGRA rows, top to bottom: exactly the TGA layout below.
$rect = New-Object System.Drawing.Rectangle 0, 0, $W, $H
$data = $out.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, $out.PixelFormat)
$pixels = New-Object byte[] ($W * $H * 4)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $pixels, 0, $pixels.Length)
$out.UnlockBits($data); $out.Dispose()

# TGA: type 2 (true color), 32 bpp, descriptor 0x28 (8 alpha bits, top-left origin).
$header = [byte[]](0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, ($W -band 255), ($W -shr 8), ($H -band 255), ($H -shr 8), 32, 0x28)
$fs = [System.IO.File]::Create($Dst)
$fs.Write($header, 0, $header.Length)
$fs.Write($pixels, 0, $pixels.Length)
$fs.Close()
"Saved {0} ({1}x{2} picture in {3}x{4}). In the game: background Image, name '{5}'. Restart WoW first." -f $Dst, $pw, $ph, $W, $H, $Name
# Add it to the picture menu in the game.
& (Join-Path $PSScriptRoot "update-images.ps1")
