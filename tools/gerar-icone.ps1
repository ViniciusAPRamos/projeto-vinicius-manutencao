#Requires -Version 5.1
<#
    Gera assets\techpulse.ico (16, 24, 32, 48, 64, 128 e 256 px) e assets\techpulse.png.
    Quadrado arredondado no gradiente do app (verde-água → azul) com uma linha de pulso.
    Só precisa rodar de novo se o desenho mudar; o .ico fica no repositório.
#>
Add-Type -AssemblyName System.Drawing
$raiz = Split-Path -Parent $PSScriptRoot
$pasta = Join-Path $raiz 'assets'
New-Item -ItemType Directory -Path $pasta -Force | Out-Null

function New-ImagemIcone([int]$Tam) {
    $bmp = New-Object Drawing.Bitmap $Tam, $Tam, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.PixelOffsetMode = 'HighQuality'
    $g.Clear([Drawing.Color]::Transparent)
    # Fundo: quadrado arredondado com gradiente
    $m = [math]::Max(1, $Tam * 0.04)
    $r = $Tam * 0.22
    $ret = New-Object Drawing.RectangleF $m, $m, ($Tam - 2 * $m), ($Tam - 2 * $m)
    $caminho = New-Object Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $caminho.AddArc($ret.X, $ret.Y, $d, $d, 180, 90)
    $caminho.AddArc($ret.Right - $d, $ret.Y, $d, $d, 270, 90)
    $caminho.AddArc($ret.Right - $d, $ret.Bottom - $d, $d, $d, 0, 90)
    $caminho.AddArc($ret.X, $ret.Bottom - $d, $d, $d, 90, 90)
    $caminho.CloseFigure()
    $grad = New-Object Drawing.Drawing2D.LinearGradientBrush $ret, ([Drawing.Color]::FromArgb(255, 13, 148, 136)), ([Drawing.Color]::FromArgb(255, 37, 99, 235)), 45.0
    $g.FillPath($grad, $caminho)
    # Linha de pulso (eletrocardiograma)
    $w = $Tam; $h = $Tam
    $pts = @(
        (New-Object Drawing.PointF ($w * 0.16), ($h * 0.54))
        (New-Object Drawing.PointF ($w * 0.36), ($h * 0.54))
        (New-Object Drawing.PointF ($w * 0.45), ($h * 0.30))
        (New-Object Drawing.PointF ($w * 0.56), ($h * 0.74))
        (New-Object Drawing.PointF ($w * 0.65), ($h * 0.46))
        (New-Object Drawing.PointF ($w * 0.84), ($h * 0.46))
    )
    $espessura = [math]::Max(1.6, $Tam * 0.075)
    $caneta = New-Object Drawing.Pen ([Drawing.Color]::White), $espessura
    $caneta.LineJoin = 'Round'; $caneta.StartCap = 'Round'; $caneta.EndCap = 'Round'
    $g.DrawLines($caneta, [Drawing.PointF[]]$pts)
    $g.Dispose()
    return $bmp
}

# ICO com imagens PNG dentro (aceito pelo Windows Vista em diante, pelo csc e pelo Inno Setup)
$tamanhos = @(16, 24, 32, 48, 64, 128, 256)
$pngs = New-Object System.Collections.Generic.List[byte[]]
foreach ($t in $tamanhos) {
    $b = New-ImagemIcone $t
    $ms = New-Object IO.MemoryStream
    $b.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
    $pngs.Add($ms.ToArray())
    if ($t -eq 256) { $b.Save((Join-Path $pasta 'techpulse.png'), [Drawing.Imaging.ImageFormat]::Png) }
    $b.Dispose()
}
$saida = New-Object IO.MemoryStream
$bw = New-Object IO.BinaryWriter $saida
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$tamanhos.Count)
$desloc = 6 + 16 * $tamanhos.Count
for ($i = 0; $i -lt $tamanhos.Count; $i++) {
    $t = $tamanhos[$i]
    $lado = if ($t -ge 256) { 0 } else { $t }
    $bw.Write([byte]$lado); $bw.Write([byte]$lado); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$pngs[$i].Length); $bw.Write([uint32]$desloc)
    $desloc += $pngs[$i].Length
}
foreach ($p in $pngs) { $bw.Write($p) }
$bw.Flush()
[IO.File]::WriteAllBytes((Join-Path $pasta 'techpulse.ico'), $saida.ToArray())
Write-Host "Gerado: $(Join-Path $pasta 'techpulse.ico')" -ForegroundColor Green
