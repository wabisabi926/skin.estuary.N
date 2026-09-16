param(
  [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\media\settings')
)

Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

function Draw-Lines($g, $pen, [float[]]$points) {
  $vertices = [System.Drawing.PointF[]]@(
    for ($i = 0; $i -lt $points.Count; $i += 2) {
      [System.Drawing.PointF]::new($points[$i], $points[$i + 1])
    }
  )
  $g.DrawLines($pen, $vertices)
}

function New-RoundedPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
  $p = [System.Drawing.Drawing2D.GraphicsPath]::new()
  $d = $r * 2
  $p.AddArc($x, $y, $d, $d, 180, 90)
  $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $p.CloseFigure()
  return $p
}

function Draw-Rounded($g, $pen, $x, $y, $w, $h, $r) {
  $p = New-RoundedPath $x $y $w $h $r
  try { $g.DrawPath($pen, $p) } finally { $p.Dispose() }
}

function Save-Icon([string]$name, [scriptblock]$draw) {
  $bitmap = [System.Drawing.Bitmap]::new(128, 128, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bitmap)
  $p = [System.Drawing.Pen]::new([System.Drawing.Color]::White, 2.4)
  try {
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.ScaleTransform(2, 2)
    $p.StartCap = $p.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $p.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    & $draw $g $p
    $bitmap.Save((Join-Path $OutputDirectory "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  }
  finally { $p.Dispose(); $g.Dispose(); $bitmap.Dispose() }
}

Save-Icon 'player' {
  param($g, $p)
  Draw-Rounded $g $p 6 10 52 37 5
  Draw-Lines $g $p @(27, 20, 40, 29, 27, 38, 27, 20)
  $g.DrawLine($p, 23, 54, 41, 54)
}
Save-Icon 'media' {
  param($g, $p)
  Draw-Rounded $g $p 7 9 31 40 3
  $g.DrawLine($p, 15, 9, 15, 49)
  foreach ($y in @(18, 28, 39)) { $g.DrawLine($p, 7, $y, 15, $y) }
  Draw-Lines $g $p @(44, 46, 44, 25, 56, 22, 56, 43)
  $g.DrawEllipse($p, 34, 45, 10, 7)
  $g.DrawEllipse($p, 46, 42, 10, 7)
}
Save-Icon 'interface' {
  param($g, $p)
  Draw-Lines $g $p @(27, 37, 45, 12, 53, 8, 51, 17, 33, 42, 27, 37)
  $g.DrawBezier($p, 27, 37, 14, 30, 22, 49, 9, 52)
  $g.DrawBezier($p, 9, 52, 22, 60, 37, 50, 33, 42)
}
Save-Icon 'additionalfeatures' {
  param($g, $p)
  Draw-Lines $g $p @(10, 52, 10, 10, 16, 7, 44, 36, 44, 10, 50, 7, 55, 12, 55, 54, 49, 57, 21, 28, 21, 53, 15, 57, 10, 52)
}
Save-Icon 'filemanager' {
  param($g, $p)
  Draw-Lines $g $p @(7, 19, 7, 14, 23, 14, 29, 20, 55, 20, 57, 24, 57, 48, 53, 52, 10, 52, 7, 49, 7, 19)
}
Save-Icon 'addons' {
  param($g, $p)
  Draw-Lines $g $p @(9, 24, 9, 12, 24, 12)
  $g.DrawArc($p, 23, 4, 16, 16, 150, 240)
  Draw-Lines $g $p @(38, 12, 51, 12, 51, 26)
  $g.DrawArc($p, 43, 25, 16, 16, 240, 240)
  Draw-Lines $g $p @(51, 40, 51, 53, 37, 53)
  $g.DrawArc($p, 23, 45, 16, 16, 210, 240)
  Draw-Lines $g $p @(24, 53, 9, 53, 9, 39)
  $g.DrawArc($p, 1, 24, 16, 16, 300, 240)
}
Save-Icon 'network' {
  param($g, $p)
  Draw-Rounded $g $p 25 5 14 14 3
  Draw-Rounded $g $p 5 44 15 14 3
  Draw-Rounded $g $p 25 44 14 14 3
  Draw-Rounded $g $p 44 44 15 14 3
  Draw-Lines $g $p @(12, 44, 12, 33, 51, 33, 51, 44)
  $g.DrawLine($p, 32, 19, 32, 44)
}
Save-Icon 'system' {
  param($g, $p)
  $points = [float[]]@()
  for ($i = 0; $i -le 64; $i++) {
    $angle = $i * [Math]::PI / 32
    $r = if (($i % 8) -in @(0, 1, 6, 7)) { 22 } else { 27 }
    $points += [float](32 + $r * [Math]::Cos($angle))
    $points += [float](32 + $r * [Math]::Sin($angle))
  }
  Draw-Lines $g $p $points
  $g.DrawEllipse($p, 23, 23, 18, 18)
}
Save-Icon 'livetv' {
  param($g, $p)
  Draw-Rounded $g $p 7 20 50 34 6
  Draw-Lines $g $p @(19, 8, 31, 20, 45, 6)
}
Save-Icon 'profiles' {
  param($g, $p)
  $g.DrawEllipse($p, 23, 6, 18, 18)
  $g.DrawArc($p, 9, 31, 46, 45, 180, 180)
  Draw-Lines $g $p @(9, 53, 9, 56, 55, 56, 55, 53)
}
Save-Icon 'sysinfo' {
  param($g, $p)
  $g.DrawEllipse($p, 6, 6, 52, 52)
  $g.DrawLine($p, 32, 30, 32, 46)
  $g.FillEllipse([System.Drawing.Brushes]::White, 30, 18, 4, 4)
}
Save-Icon 'eventlog' {
  param($g, $p)
  Draw-Rounded $g $p 14 6 36 52 4
  $g.DrawLine($p, 23, 31, 41, 31)
  $g.DrawLine($p, 23, 42, 41, 42)
  $g.DrawEllipse($p, 23, 15, 5, 5)
}

foreach ($enabled in @($false, $true)) {
  $bitmap = [System.Drawing.Bitmap]::new(144, 80, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bitmap)
  $track = [System.Drawing.SolidBrush]::new($(if ($enabled) { [System.Drawing.Color]::FromArgb(210, 164, 181, 176) } else { [System.Drawing.Color]::FromArgb(100, 128, 128, 128) }))
  $path = New-RoundedPath 2 2 140 76 38
  try {
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.FillPath($track, $path)
    $g.FillEllipse([System.Drawing.Brushes]::White, $(if ($enabled) { 73 } else { 9 }), 9, 62, 62)
    $name = if ($enabled) { 'switch-on.png' } else { 'switch-off.png' }
    $bitmap.Save((Join-Path $OutputDirectory $name), [System.Drawing.Imaging.ImageFormat]::Png)
  }
  finally { $path.Dispose(); $track.Dispose(); $g.Dispose(); $bitmap.Dispose() }
}
