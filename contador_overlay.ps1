$lockFile = "$env:TEMP\ContadorOverlay.lock"
if (Test-Path $lockFile) {
    $pid_guardado = Get-Content $lockFile -ErrorAction SilentlyContinue
    $sigue_vivo   = Get-Process -Id $pid_guardado -ErrorAction SilentlyContinue
    if ($sigue_vivo) { exit }
}
$PID | Set-Content $lockFile

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
}
"@

# ════════════════════════════════════════
#         CONFIGURACION  ← edita aqui
# ════════════════════════════════════════

# Meta normal (horas sin break ni comida)
$GOAL          = 32

# Umbral morado en horas normales
$PURPLE_NORMAL = 35

# Horas CON break (formato 24h, solo el inicio de la hora)
$BREAK_HOURS   = @(16, 18)

# Meta reducida en horas de break
$GOAL_BREAK    = 24

# Umbral morado en horas de break
$PURPLE_BREAK  = 28

# Hora de comida (formato 24h) — no cuenta contra el buffer
$LUNCH_HOURS   = @(19)

# Inicio y fin de turno (formato 24h)
$SHIFT_START   = 14   # 2pm
$SHIFT_END     = 23   # 11pm

# Segundos minimos entre dos Alt+S para que el segundo cuente
# Sube este valor si tu flujo de reintento tarda mas de 10 seg
$DEBOUNCE_SECS = 10

# Bills en la hora (o buffer) para activar el arcoiris RGB (easter egg)
$RGB_UMBRAL    = 50

# ════════════════════════════════════════
#         (no editar de aqui para abajo)
# ════════════════════════════════════════
$REG_PATH = "HKCU:\Software\ContadorOverlay"

$form                 = New-Object System.Windows.Forms.Form
$form.TopMost         = $true
$form.FormBorderStyle = 'None'
$form.BackColor       = [System.Drawing.Color]::Black
$form.Opacity         = 0.75
$form.Width           = 145
$form.Height          = 38
$form.StartPosition   = 'Manual'
$form.ShowInTaskbar   = $false

$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = New-Object System.Drawing.Point(($screen.Width - $form.Width - 130), 20)

$rtb                  = New-Object System.Windows.Forms.RichTextBox
$rtb.Dock             = 'Fill'
$rtb.BackColor        = [System.Drawing.Color]::Black
$rtb.Font             = New-Object System.Drawing.Font('Consolas', 14, [System.Drawing.FontStyle]::Bold)
$rtb.ReadOnly         = $true
$rtb.BorderStyle      = 'None'
$rtb.ScrollBars       = 'None'
$rtb.WordWrap         = $false
$rtb.Multiline        = $false
$rtb.TabStop          = $false
$rtb.ShortcutsEnabled = $false
$form.Controls.Add($rtb)

function Load-State {
    $now   = Get-Date
    $state = @{ Buffer = 0; Count = 0; Day = $now.Day; Hour = $now.Hour }
    try {
        if (Test-Path $REG_PATH) {
            $reg = Get-ItemProperty -Path $REG_PATH -ErrorAction Stop
            if ($reg.PSObject.Properties["Buffer"]) { $state.Buffer = [int]$reg.Buffer }
            if ($reg.PSObject.Properties["Count"])  { $state.Count  = [int]$reg.Count  }
            if ($reg.PSObject.Properties["Day"])    { $state.Day    = [int]$reg.Day    }
            if ($reg.PSObject.Properties["Hour"])   { $state.Hour   = [int]$reg.Hour   }
        }
    } catch {}
    return $state
}

function Save-State($buffer, $count, $day, $hour) {
    try {
        if (-not (Test-Path $REG_PATH)) {
            New-Item -Path $REG_PATH -Force | Out-Null
        }
        Set-ItemProperty -Path $REG_PATH -Name "Buffer" -Value $buffer
        Set-ItemProperty -Path $REG_PATH -Name "Count"  -Value $count
        Set-ItemProperty -Path $REG_PATH -Name "Day"    -Value $day
        Set-ItemProperty -Path $REG_PATH -Name "Hour"   -Value $hour
    } catch {}
}

function Save-HourLog($hour, $count, $mins, $isOT = $false) {
    try {
        if (-not (Test-Path $REG_PATH)) { New-Item -Path $REG_PATH -Force | Out-Null }
        Set-ItemProperty -Path $REG_PATH -Name "Hora$hour" -Value $count
        Set-ItemProperty -Path $REG_PATH -Name "Mins$hour" -Value $mins
        if ($isOT) { Set-ItemProperty -Path $REG_PATH -Name "OT$hour" -Value 1 }
    } catch {}
}

function Mark-HourClosed($hour) {
    try {
        if (-not (Test-Path $REG_PATH)) { New-Item -Path $REG_PATH -Force | Out-Null }
        Set-ItemProperty -Path $REG_PATH -Name "Closed$hour" -Value 1
    } catch {}
}

function Is-HourClosed($hour) {
    try {
        if (Test-Path $REG_PATH) {
            $reg = Get-ItemProperty -Path $REG_PATH -ErrorAction Stop
            if ($reg.PSObject.Properties["Closed$hour"]) { return [int]$reg."Closed$hour" -eq 1 }
        }
    } catch {}
    return $false
}

function Clear-HourLog {
    try {
        if (Test-Path $REG_PATH) {
            $reg = Get-ItemProperty -Path $REG_PATH -ErrorAction Stop
            $reg.PSObject.Properties |
                Where-Object { $_.Name -match '^(Hora|Mins|Closed|OT)\w+$' } |
                ForEach-Object { Remove-ItemProperty -Path $REG_PATH -Name $_.Name -ErrorAction SilentlyContinue }
        }
    } catch {}
}

function Load-HourLog {
    $log = @{}
    try {
        if (Test-Path $REG_PATH) {
            $reg = Get-ItemProperty -Path $REG_PATH -ErrorAction Stop

            $reg.PSObject.Properties |
                Where-Object { $_.Name -match '^Hora\d+$' } |
                ForEach-Object {
                    $h = $_.Name -replace 'Hora', ''
                    $log[$h] = @{
                        Bills = [int]$_.Value
                        Mins  = if ($reg.PSObject.Properties["Mins$h"]) { [int]$reg."Mins$h" } else { 60 }
                        IsOT  = $reg.PSObject.Properties["OT$h"] -ne $null
                    }
                }

            if ($reg.PSObject.Properties["HoraMEDIA"]) {
                $log["MEDIA"] = @{
                    Bills = [int]$reg.HoraMEDIA
                    Mins  = 30
                    IsOT  = $false
                }
            }
        }
    } catch {}
    return $log
}

$saved           = Load-State
$now             = Get-Date
$global:lastDay  = $now.Day
$global:lastHour = $now.Hour

$resetPorCuatroAm = ($global:lastHour -ge 4) -and ($saved.Day -ne $global:lastDay)
if ($resetPorCuatroAm) {
    $global:buffer = 0
    $global:count  = 0
    Clear-HourLog
    Save-State 0 0 $global:lastDay $global:lastHour
} elseif ($saved.Hour -eq $global:lastHour) {
    $global:buffer = $saved.Buffer
    $global:count  = $saved.Count
} else {

    $savedEsOT = ($saved.Hour -lt $SHIFT_START) -or ($saved.Hour -ge $SHIFT_END)
    if ($saved.Hour -in $LUNCH_HOURS) {

        $global:buffer = $saved.Buffer
    } elseif ($savedEsOT -and $saved.Count -eq 0) {

        $global:buffer = $saved.Buffer
    } elseif ($savedEsOT) {

        $global:buffer = $saved.Buffer + ($saved.Count - $GOAL)
        Save-HourLog $saved.Hour $saved.Count 60 $true
        Mark-HourClosed $saved.Hour
    } else {

        $meta          = if ($saved.Hour -in $BREAK_HOURS) { $GOAL_BREAK } else { $GOAL }
        $global:buffer = $saved.Buffer + ($saved.Count - $meta)
        $missedMins    = if ($saved.Hour -in $BREAK_HOURS) { 45 } else { 60 }
        Save-HourLog $saved.Hour $saved.Count $missedMins
        Mark-HourClosed $saved.Hour
    }
    $global:count  = 0
    Save-State $global:buffer 0 $global:lastDay $global:lastHour
}

$global:pressedAltS  = $false
$global:pressedF11   = $false
$global:pressedF12   = $false

$global:lastAltSTime = [DateTime]::MinValue

function Get-Meta {
    $h = (Get-Date).Hour
    if ($h -in $LUNCH_HOURS) { return $GOAL }
    if ($h -in $BREAK_HOURS) { return $GOAL_BREAK }
    return $GOAL
}

function Get-CountColor($c, $meta) {
    $purple = if ($meta -eq $GOAL_BREAK) { $PURPLE_BREAK } else { $PURPLE_NORMAL }
    if ($c -ge $purple)        { return [System.Drawing.Color]::MediumOrchid }
    if (($c / $meta) -ge 1.0) { return [System.Drawing.Color]::Lime }
    if (($c / $meta) -ge 0.5) { return [System.Drawing.Color]::Yellow }
    return [System.Drawing.Color]::Red
}

function Get-BufferColor($b) {
    if ($b -ge 16) { return [System.Drawing.Color]::MediumOrchid }
    if ($b -ge 8)  { return [System.Drawing.Color]::Lime }
    if ($b -ge 1)  { return [System.Drawing.Color]::Yellow }
    return [System.Drawing.Color]::Red
}

$global:rgbHue    = 0
$global:rptHue    = 0
$global:rngBufIni = 0

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class RgbWin32 {
    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
}
"@ -ErrorAction SilentlyContinue

function Hue-Color([double]$h) {
    $h = (($h % 360) + 360) % 360
    $x = 1 - [Math]::Abs((($h / 60) % 2) - 1)
    switch ([int][Math]::Floor($h / 60)) {
        0       { $r = 1;  $g = $x; $b = 0  }
        1       { $r = $x; $g = 1;  $b = 0  }
        2       { $r = 0;  $g = 1;  $b = $x }
        3       { $r = 0;  $g = $x; $b = 1  }
        4       { $r = $x; $g = 0;  $b = 1  }
        default { $r = 1;  $g = 0;  $b = $x }
    }
    return [System.Drawing.Color]::FromArgb(255, [int]($r * 255), [int]($g * 255), [int]($b * 255))
}

function Pintar-Arcoiris($box, $rangos, $hueBase) {
    $selIni = $box.SelectionStart; $selLen = $box.SelectionLength
    [void][RgbWin32]::SendMessage($box.Handle, 0x0B, [IntPtr]::Zero, [IntPtr]::Zero)
    foreach ($rg in $rangos) {
        for ($i = 0; $i -lt $rg[1]; $i++) {
            $box.SelectionStart  = $rg[0] + $i
            $box.SelectionLength = 1
            $box.SelectionColor  = Hue-Color ($hueBase + $i * 40)
        }
    }
    $box.SelectionStart = $selIni; $box.SelectionLength = $selLen
    [void][RgbWin32]::SendMessage($box.Handle, 0x0B, [IntPtr]1, [IntPtr]::Zero)
    $box.Invalidate()
}

function Aplicar-RGBOverlay {
    $rangos = @()
    if ($global:count  -ge $RGB_UMBRAL) { $rangos += ,@(0, "$($global:count)".Length) }
    if ($global:buffer -ge $RGB_UMBRAL) { $rangos += ,@($global:rngBufIni, "+$($global:buffer)".Length) }
    if ($rangos.Count -gt 0) { Pintar-Arcoiris $rtb $rangos $global:rgbHue }
}

function Update-Display {
    $meta       = Get-Meta
    $countTxt   = "$($global:count)"
    $bufTxt     = if ($global:buffer -ge 0) { "+$($global:buffer)" } else { "$($global:buffer)" }
    $countColor = Get-CountColor $global:count $meta
    $bufColor   = Get-BufferColor $global:buffer
    $sepColor   = [System.Drawing.Color]::DimGray

    $rtb.Clear()
    $rtb.SelectionStart = $rtb.TextLength; $rtb.SelectionLength = 0
    $rtb.SelectionColor = $countColor;     $rtb.AppendText($countTxt)
    $rtb.SelectionStart = $rtb.TextLength; $rtb.SelectionLength = 0
    $rtb.SelectionColor = $sepColor;       $rtb.AppendText('|')
    $rtb.SelectionStart = $rtb.TextLength; $rtb.SelectionLength = 0
    $global:rngBufIni   = $rtb.TextLength
    $rtb.SelectionColor = $bufColor;       $rtb.AppendText($bufTxt)
    $rtb.SelectAll()
    $rtb.SelectionAlignment = 'Center'
    Aplicar-RGBOverlay
}

Update-Display

function Redondear-AcuartO($minutos) {

    if ($minutos -le 7)      { return 0,  $false }
    elseif ($minutos -le 22) { return 15, $false }
    elseif ($minutos -le 37) { return 30, $true  }
    elseif ($minutos -le 52) { return 45, $false }
    else                     { return 60, $false }
}

function Formato-12h($clave) {
    if ($clave -eq "MEDIA") { return "Half hr" }
    $h     = [int]$clave
    $sufx  = if ($h -lt 12) { "am" } else { "pm" }
    $h12   = $h % 12; if ($h12 -eq 0) { $h12 = 12 }
    return "$h12$sufx"
}

function Mins-DeClave($clave, $log) {
    if ($clave -eq "MEDIA")                     { return 30 }
    if ([string]$clave -in ($LUNCH_HOURS | ForEach-Object { "$_" })) { return 0 }
    if ([string]$clave -in ($BREAK_HOURS | ForEach-Object { "$_" })) {
        $m = if ($log.ContainsKey($clave)) { $log[$clave].Mins } else { 45 }
        return [Math]::Min($m, 45)
    }
    if ($log.ContainsKey($clave)) { return [int]$log[$clave].Mins } else { return 60 }
}

function Generar-Reporte($log) {
    if ($log.Count -eq 0) { return @(@{ text = "BPH REPORT"; color = "White" }, @{ text = "No records for today."; color = "DimGray" }) }

    $breakStrs = $BREAK_HOURS | ForEach-Object { "$_" }
    $lunchStrs = $LUNCH_HOURS | ForEach-Object { "$_" }

    $bills    = @{}
    $msjPenal = ""
    foreach ($k in $log.Keys) {

        if ((Mins-DeClave $k $log) -eq 0) { continue }
        $bills[$k] = $log[$k].Bills
    }
    if ($bills.ContainsKey("MEDIA")) {
        $msjPenal       = "[!] PENALTY: -$($bills['MEDIA']) (Half hour)"
        $bills["MEDIA"] = 0
    }

    $totalMins  = 0
    $totalBills = 0
    foreach ($k in $bills.Keys) {
        $totalBills += $bills[$k]
        $totalMins  += Mins-DeClave $k $log
    }

    if ($totalMins -eq 0) { return @(@{ text = "No active time."; color = "DimGray" }) }

    $promedio   = ($totalBills / $totalMins) * 60
    $diferencia = $totalBills - (($totalMins / 60) * $GOAL)

    $bphPorHora = @{}
    foreach ($k in $bills.Keys) {
        $mBph = Mins-DeClave $k $log
        if ($bills[$k] -gt 0 -and $mBph -gt 0 -and $k -notin $breakStrs -and $k -notin $lunchStrs -and $k -ne "MEDIA") {
            $bphPorHora[$k] = ($bills[$k] / $mBph) * 60
        }
    }
    $mejorClave = if ($bphPorHora.Count -gt 0) { ($bphPorHora.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key } else { $null }
    $efficiency = if ($mejorClave -and $promedio -gt 0) { ($promedio / $bills[$mejorClave] * 100) } else { 0 }

    $hEnt    = [Math]::Floor($totalMins / 60)
    $hFrac   = @(0, 0.25, 0.5, 0.75, 1)[[Math]::Round(($totalMins % 60) / 15)]
    $tTotal  = $hEnt + $hFrac
    $tDisplay = "${tTotal}hr"

    $lines   = [System.Collections.Generic.List[object]]::new()
    $onTrack = $promedio -ge $GOAL

    $lines.Add(@{ text = "BPH STATS";      color = "White" })
    $lines.Add(@{ text = "---------------"; color = "DimGray" })
    $lines.Add(@{ text = "$(if($onTrack){'[OK]'}else{'[!!]'}) $(if($onTrack){'ON TRACK'}else{'BELOW GOAL'})"; color = if($onTrack){"Lime"}else{"Red"} })
    $lines.Add(@{ text = "AVG: $([Math]::Round($promedio,2))/hr"; color = if($onTrack){"Lime"}else{"OrangeRed"} })
    $lines.Add(@{ text = "TOTAL: $totalBills bills";              color = "White" })
    $lines.Add(@{ text = "TIME: $tDisplay";                       color = "White" })
    $lines.Add(@{ text = "--------------------"; color = "DimGray" })

    if ($diferencia -ge 0) {
        $lines.Add(@{ text = "[+] BUFFER: +$([int]$diferencia)"; color = "Lime"; rgb = ([int]$diferencia -ge $RGB_UMBRAL) })
    } else {
        $lines.Add(@{ text = "[-] MISSING: $([int][Math]::Abs($diferencia))"; color = "OrangeRed" })
    }
    if ($msjPenal) { $lines.Add(@{ text = $msjPenal; color = "OrangeRed" }) }

    if ($mejorClave) {
        $lines.Add(@{ text = "--------------------"; color = "DimGray" })
        $lines.Add(@{ text = "BEST: $(Formato-12h $mejorClave) -> $($bills[$mejorClave]) bills"; color = "MediumOrchid" })
        $lines.Add(@{ text = "CONSISTENCY: $([int]$efficiency)%"; color = "Yellow" })
    }

    $entradas = $bills.GetEnumerator() |
        Sort-Object { if ($_.Key -eq "MEDIA") { 9999 } else { [int]$_.Key } } |
        Where-Object { -not ($_.Key -eq "MEDIA" -and $_.Value -eq 0) } |
        Where-Object { $_.Key -notin $lunchStrs }

    $lines.Add(@{ text = "--------------------"; color = "DimGray" })
    $lines.Add(@{ text = "BREAKDOWN";            color = "White" })

    foreach ($entry in $entradas) {
        $k = $entry.Key
        $v = $entry.Value
        $isBreak = $k -in $breakStrs
        $isMEDIA = $k -eq "MEDIA"
        $meta_k  = if ($isBreak) { $GOAL_BREAK } else { $GOAL }
        $purp_k  = if ($isBreak) { $PURPLE_BREAK } else { $PURPLE_NORMAL }

        $clr = if ($isMEDIA) {
            "OrangeRed"
        } elseif ($v -ge $purp_k) {
            "MediumOrchid"
        } elseif ($v -ge $meta_k) {
            "Lime"
        } elseif ($v -ge [int]($meta_k * 0.5)) {
            "Yellow"
        } else {
            "OrangeRed"
        }

        $label  = Formato-12h $k
        $isOT   = if ($log[$k].IsOT) { $log[$k].IsOT } else { $false }
        $sufijo = if ($isBreak) { " BREAK" } elseif ($isMEDIA) { " [!]" } elseif ($isOT) { " OT" } else { "" }

        $pad  = "{0,-7}" -f $label
        $lines.Add(@{ text = "  $pad $v$sufijo"; color = $clr; rgb = ($v -ge $RGB_UMBRAL) })
    }

    return $lines
}

function Show-Report {
    $now     = Get-Date
    $minutos = $now.Minute
    $hora    = $now.Hour

    $minsActivos, $esMedia = Redondear-AcuartO $minutos
    $breakStrsR = $BREAK_HOURS | ForEach-Object { "$_" }
    $lunchStrsR = $LUNCH_HOURS | ForEach-Object { "$_" }

    $horaEnTurno = ($hora -ge $SHIFT_START) -and ($hora -lt $SHIFT_END)
    $horaEsOT    = (-not $horaEnTurno) -and ($hora -notin $LUNCH_HOURS)

    if ($horaEnTurno) {

        if ($esMedia) {
            $clave = "MEDIA"
        } elseif ("$hora" -in $breakStrsR) {
            $clave       = "$hora"
            $minsActivos = 45
        } elseif ("$hora" -in $lunchStrsR) {
            $clave       = "$hora"
            $minsActivos = 0
        } else {
            $clave = "$hora"
        }
        $claveParaCheck = if ($esMedia) { "MEDIA" } else { "$hora" }
        if (-not (Is-HourClosed $claveParaCheck)) {
            Save-HourLog $clave $global:count $minsActivos
        }
    } elseif ($horaEsOT -and $global:count -gt 0) {

        if ($esMedia) {
            $clave = "MEDIA"
        } else {
            $clave       = "$hora"
            $minsActivos = $minsActivos
        }
        $claveParaCheck = if ($esMedia) { "MEDIA" } else { "$hora" }
        if (-not (Is-HourClosed $claveParaCheck)) {
            Save-HourLog $clave $global:count $minsActivos $true
        }
    }

    $log = Load-HourLog

    if ($horaEsOT -and $esMedia -and $global:count -gt 0 -and -not $log.ContainsKey("MEDIA")) {
        $log["MEDIA"] = @{ Bills = $global:count; Mins = 30; IsOT = $true }
    }

    if ($horaEnTurno -and $esMedia -and -not $log.ContainsKey("MEDIA")) {
        $log["MEDIA"] = @{ Bills = $global:count; Mins = 30; IsOT = $false }
    }

    $lines = Generar-Reporte $log

    $rForm                 = New-Object System.Windows.Forms.Form
    $rForm.TopMost         = $true
    $rForm.FormBorderStyle = 'None'
    $rForm.BackColor       = [System.Drawing.Color]::Black
    $rForm.Opacity         = 0.92
    $rForm.StartPosition   = 'Manual'
    $rForm.ShowInTaskbar   = $false
    $rForm.Width           = 340
    $rForm.Height          = 20 + ($lines.Count * 26)

    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $rForm.Location = New-Object System.Drawing.Point(
        ($screen.Width - $rForm.Width - 20),
        20
    )

    $rRtb                  = New-Object System.Windows.Forms.RichTextBox
    $rRtb.Dock             = 'Fill'
    $rRtb.BackColor        = [System.Drawing.Color]::Black
    $rRtb.Font             = New-Object System.Drawing.Font('Consolas', 12, [System.Drawing.FontStyle]::Bold)
    $rRtb.ReadOnly         = $true
    $rRtb.BorderStyle      = 'None'
    $rRtb.ScrollBars       = 'None'
    $rRtb.WordWrap         = $false
    $rRtb.ShortcutsEnabled = $false
    $rForm.Controls.Add($rRtb)

    $rgbRangos = @()
    foreach ($line in $lines) {
        $colorName = if ($line -is [hashtable]) { $line.color } else { "White" }
        $txt       = if ($line -is [hashtable]) { $line.text  } else { $line   }
        $color     = try { [System.Drawing.Color]::$colorName } catch { [System.Drawing.Color]::White }
        $rRtb.SelectionStart  = $rRtb.TextLength
        $rRtb.SelectionLength = 0
        $rRtb.SelectionColor  = $color
        $ini = $rRtb.TextLength
        $rRtb.AppendText("$txt`n")
        if ($line -is [hashtable] -and $line.rgb) { $rgbRangos += ,@($ini, "$txt".Length) }
    }

    if ($rgbRangos.Count -gt 0) {
        $rRtb.SelectionStart = 0; $rRtb.SelectionLength = 0
        Pintar-Arcoiris $rRtb $rgbRangos $global:rptHue
        $rTimer          = New-Object System.Windows.Forms.Timer
        $rTimer.Interval = 70
        $rTimer.Add_Tick({
            $global:rptHue = ($global:rptHue + 15) % 360
            Pintar-Arcoiris $rRtb $rgbRangos $global:rptHue
        })
        $rTimer.Start()
        $rForm.Add_FormClosed({ $rTimer.Stop(); $rTimer.Dispose() })
    }

    $closeAction = {
        $rForm.Close()
        $global:count    = 0
        $global:buffer   = 0
        $global:lastHour = (Get-Date).Hour
        $global:lastDay  = (Get-Date).Day
        Clear-HourLog
        Save-State 0 0 $global:lastDay $global:lastHour
        Update-Display
    }

    $rForm.Add_Click($closeAction)
    $rRtb.Add_Click($closeAction)

    $rForm.Add_KeyDown({
        param($s, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F11) {
            & $closeAction
        }
    })
    $rRtb.Add_KeyDown({
        param($s, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F11) {
            & $closeAction
        }
    })
    $rForm.KeyPreview = $true

    [void]$rForm.ShowDialog()
}

$timer          = New-Object System.Windows.Forms.Timer
$timer.Interval = 50

$timer.Add_Tick({
    $now     = Get-Date
    $nowHour = $now.Hour
    $nowDay  = $now.Day

    if ($nowHour -ge 4 -and $nowDay -ne $global:lastDay) {
        $global:count    = 0
        $global:buffer   = 0
        $global:lastHour = $nowHour
        $global:lastDay  = $nowDay
        Clear-HourLog
        Save-State 0 0 $nowDay $nowHour
        Update-Display
        return
    }

    if ($nowHour -ne $global:lastHour) {
        $esOT    = ($global:lastHour -lt $SHIFT_START) -or ($global:lastHour -ge $SHIFT_END)
        $esLunch = $global:lastHour -in $LUNCH_HOURS
        $esBreak = $global:lastHour -in $BREAK_HOURS

        if ($esLunch) {

        } elseif ($esOT) {

            if ($global:count -gt 0) {
                Save-HourLog $global:lastHour $global:count 60 $true
                Mark-HourClosed $global:lastHour
                $global:buffer += ($global:count - $GOAL)
            }

        } else {

            $mins = if ($esBreak) { 45 } else { 60 }
            Save-HourLog $global:lastHour $global:count $mins
            Mark-HourClosed $global:lastHour
            $meta           = if ($esBreak) { $GOAL_BREAK } else { $GOAL }
            $global:buffer += ($global:count - $meta)
        }

        $global:count    = 0
        $global:lastHour = $nowHour
        Save-State $global:buffer 0 $nowDay $nowHour
        Update-Display
    }

    $alt = [Win32]::GetAsyncKeyState(0x12)
    $s   = [Win32]::GetAsyncKeyState(0x53)
    if (($alt -ne 0) -and ($s -ne 0)) {
        if (-not $global:pressedAltS) {
            $ahora = Get-Date
            $segs  = ($ahora - $global:lastAltSTime).TotalSeconds
            if ($segs -ge $DEBOUNCE_SECS) {
                $global:count++
                $global:lastAltSTime = $ahora
                Save-State $global:buffer $global:count $nowDay $nowHour
                Update-Display
            }
            $global:pressedAltS = $true
        }
    } else { $global:pressedAltS = $false }

    $f12 = [Win32]::GetAsyncKeyState(0x7B)
    if ($f12 -ne 0) {
        if (-not $global:pressedF12) {
            if ($global:count -gt 0) { $global:count-- }
            $global:pressedF12 = $true
            Save-State $global:buffer $global:count $nowDay $nowHour
            Update-Display
        }
    } else { $global:pressedF12 = $false }

    $f11 = [Win32]::GetAsyncKeyState(0x7A)
    if ($f11 -ne 0) {
        if (-not $global:pressedF11) {
            $global:pressedF11 = $true
            $timer.Stop()
            $confirm = [System.Windows.Forms.MessageBox]::Show(
                "End shift and generate report?",
                "BPH Counter",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
                Show-Report

                $timer.Start()
            } else {
                $timer.Start()
            }
        }
    } else { $global:pressedF11 = $false }
})

$timer.Start()

$rgbTimer          = New-Object System.Windows.Forms.Timer
$rgbTimer.Interval = 70
$rgbTimer.Add_Tick({
    if ($global:count -ge $RGB_UMBRAL -or $global:buffer -ge $RGB_UMBRAL) {
        $global:rgbHue = ($global:rgbHue + 15) % 360
        Aplicar-RGBOverlay
    }
})
$rgbTimer.Start()

$form.Handle | Out-Null
$GWL_EXSTYLE      = -20
$WS_EX_TOOLWINDOW = 0x00000080
$WS_EX_APPWINDOW  = 0x00040000
$cur = [Win32]::GetWindowLong($form.Handle, $GWL_EXSTYLE)
[void][Win32]::SetWindowLong($form.Handle, $GWL_EXSTYLE, ($cur -bor $WS_EX_TOOLWINDOW) -band -bnot $WS_EX_APPWINDOW)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class PoBolWin32 {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
}
"@ -ErrorAction SilentlyContinue

$global:DEBUG_MODE = ($env:PO_BOL_DEBUG -eq '1')

function Minimize-Console {
    if ($global:DEBUG_MODE) { return }
    $hwnd = [PoBolWin32]::GetConsoleWindow()
    [PoBolWin32]::ShowWindow($hwnd, 0) | Out-Null
}

function Restore-Console {
    if ($global:DEBUG_MODE) { return }

}

function Show-Toast($title, $msg) {
    $n = New-Object System.Windows.Forms.NotifyIcon
    $n.Icon            = [System.Drawing.SystemIcons]::Application
    $n.Visible         = $true
    $n.BalloonTipTitle = $title
    $n.BalloonTipText  = $msg
    $n.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Info
    $n.ShowBalloonTip(2500)
    Start-Sleep -Milliseconds 100
    $n.Dispose()
}

function Get-Lista($rawText) {
    $t = $rawText -replace '[,/\r\n]', ' '
    $t = $t -replace '\s+', ' '
    $t = $t.Trim()
    $items = @($t -split ' ' | Where-Object { $_.Trim() -ne '' })

    $vistas = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $unicas = [System.Collections.Generic.List[string]]::new()
    foreach ($it in $items) {
        if ($vistas.Add($it)) { $unicas.Add($it) }
    }
    $global:repetidasQuitadas = $items.Count - $unicas.Count
    return $unicas.ToArray()
}

function Show-InputWindow {
    $inForm = New-Object System.Windows.Forms.Form
    $inForm.Text            = "PO / BOL Filler"
    $inForm.Size            = New-Object System.Drawing.Size(420, 250)
    $inForm.StartPosition   = "CenterScreen"
    $inForm.TopMost         = $true
    $inForm.BackColor       = [System.Drawing.Color]::FromArgb(12, 12, 28)
    $inForm.FormBorderStyle = "FixedDialog"
    $inForm.MaximizeBox     = $false
    $inForm.MinimizeBox     = $false

    $inLbl = New-Object System.Windows.Forms.Label
    $inLbl.Text      = "Pega aqui (Ctrl+V) - carga automatico:"
    $inLbl.ForeColor = [System.Drawing.Color]::FromArgb(0, 180, 216)
    $inLbl.Font      = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
    $inLbl.Location  = New-Object System.Drawing.Point(14, 14)
    $inLbl.Size      = New-Object System.Drawing.Size(380, 22)

    $inTxt = New-Object System.Windows.Forms.TextBox
    $inTxt.Multiline  = $true
    $inTxt.ScrollBars = "Vertical"
    $inTxt.Location   = New-Object System.Drawing.Point(14, 44)
    $inTxt.Size       = New-Object System.Drawing.Size(380, 160)
    $inTxt.BackColor  = [System.Drawing.Color]::FromArgb(22, 22, 45)
    $inTxt.ForeColor  = [System.Drawing.Color]::White
    $inTxt.Font       = New-Object System.Drawing.Font("Consolas", 11)

    $inTxt.Add_KeyDown({
        param($s, $e)
        if ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::V) {
            $inForm.BeginInvoke([System.Action]{
                Start-Sleep -Milliseconds 80
                $inForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
                $inForm.Close()
            })
        }
    })

    $inForm.Controls.AddRange(@($inLbl, $inTxt))

    $inForm.Add_Shown({ $inTxt.Focus() })

    $result = $inForm.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $inTxt.Text
    }
    return $null
}

$sizeCompactoKG  = New-Object System.Drawing.Size(26, 14)
$sizeExpandidoKG = New-Object System.Drawing.Size(115, 48)

$formKG                 = New-Object System.Windows.Forms.Form
$formKG.TopMost         = $true
$formKG.FormBorderStyle = 'None'
$formKG.BackColor       = [System.Drawing.Color]::FromArgb(45, 45, 45)
$formKG.Opacity         = 0.90
$formKG.StartPosition   = 'Manual'
$formKG.ShowInTaskbar   = $false
$formKG.MinimumSize     = $sizeCompactoKG
$formKG.MaximumSize     = $sizeCompactoKG
$formKG.Size            = $sizeCompactoKG

$screenKG = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$formKG.Location = New-Object System.Drawing.Point(($screenKG.Width - 115 - 315), 20)

$txtKG                  = New-Object System.Windows.Forms.TextBox
$txtKG.Location         = New-Object System.Drawing.Point(6, 22)
$txtKG.Width            = 103
$txtKG.Height           = 18
$txtKG.BackColor        = [System.Drawing.Color]::Black
$txtKG.ForeColor        = [System.Drawing.Color]::White
$txtKG.Font             = New-Object System.Drawing.Font('Consolas', 8, [System.Drawing.FontStyle]::Bold)
$txtKG.BorderStyle      = 'FixedSingle'
$txtKG.TextAlign        = 'Center'
$txtKG.Visible          = $false
$formKG.Controls.Add($txtKG)

$lblResultKG            = New-Object System.Windows.Forms.Label
$lblResultKG.Text       = "KG"
$lblResultKG.ForeColor  = [System.Drawing.Color]::Lime
$lblResultKG.BackColor  = [System.Drawing.Color]::Transparent
$lblResultKG.Font       = New-Object System.Drawing.Font('Arial', 6.5, [System.Drawing.FontStyle]::Bold)
$lblResultKG.TextAlign  = 'MiddleCenter'
$lblResultKG.Cursor     = [System.Windows.Forms.Cursors]::Hand
$lblResultKG.Dock       = 'Fill'
$formKG.Controls.Add($lblResultKG)

$script:timerEsperaKG = New-Object System.Windows.Forms.Timer
$script:timerEsperaKG.Interval = 15000
$script:timerEsperaKG.Add_Tick({ Encoger-FormularioKG })

$script:estaExpandidoKG = $false

function Expandir-FormularioKG {
    $script:estaExpandidoKG = $true

    $formKG.MinimumSize     = New-Object System.Drawing.Size(0, 0)
    $formKG.MaximumSize     = New-Object System.Drawing.Size(0, 0)
    $formKG.Size            = $sizeExpandidoKG
    $formKG.BackColor       = [System.Drawing.Color]::Black

    $lblResultKG.Dock       = 'None'
    $lblResultKG.Location   = New-Object System.Drawing.Point(0, 2)
    $lblResultKG.Width      = 115
    $lblResultKG.Height     = 18
    $lblResultKG.Font       = New-Object System.Drawing.Font('Consolas', 8, [System.Drawing.FontStyle]::Bold)
    $lblResultKG.Text       = "-- lbs"
    $lblResultKG.ForeColor  = [System.Drawing.Color]::Lime

    $txtKG.Visible          = $true
    $txtKG.Text             = ""
    $txtKG.Focus()
    $formKG.Refresh()
}

function Encoger-FormularioKG {
    $script:timerEsperaKG.Stop()
    $script:estaExpandidoKG = $false
    $txtKG.Visible          = $false

    $formKG.MinimumSize     = $sizeCompactoKG
    $formKG.MaximumSize     = $sizeCompactoKG
    $formKG.Size            = $sizeCompactoKG
    $formKG.BackColor       = [System.Drawing.Color]::FromArgb(45, 45, 45)

    $lblResultKG.Dock       = 'Fill'
    $lblResultKG.Font       = New-Object System.Drawing.Font('Arial', 6.5, [System.Drawing.FontStyle]::Bold)
    $lblResultKG.Text       = "KG"
    $lblResultKG.ForeColor  = [System.Drawing.Color]::Lime
    $formKG.Refresh()
}

$lblResultKG.Add_Click({
    if (-not $script:estaExpandidoKG) { Expandir-FormularioKG }
})

$formKG.Add_Click({
    if (-not $script:estaExpandidoKG) { Expandir-FormularioKG }
})

$txtKG.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq 'Return') {
        $inputKG = $txtKG.Text.Trim()
        if ([string]::IsNullOrEmpty($inputKG)) {
            Encoger-FormularioKG
            $e.SuppressKeyPress = $true
            return
        }
        try {
            $kg  = [int]$inputKG
            $lbs = [Math]::Ceiling($kg * 2.205)
            $lblResultKG.Text      = "$lbs lbs"
            $lblResultKG.ForeColor = [System.Drawing.Color]::Lime

            $formKG.Refresh()

            $script:timerEsperaKG.Start()
        } catch {
            $lblResultKG.Text      = "?"
            $lblResultKG.ForeColor = [System.Drawing.Color]::OrangeRed
            $formKG.Refresh()
            Start-Sleep -Milliseconds 800
            Encoger-FormularioKG
        }
        $e.SuppressKeyPress = $true
    }
    if ($e.KeyCode -eq 'Escape') {
        Encoger-FormularioKG
        $e.SuppressKeyPress = $true
    }
})

$txtKG.Add_KeyPress({
    param($s, $e)
    $allowed = '0123456789'
    if ($allowed.IndexOf($e.KeyChar) -lt 0 -and [int]$e.KeyChar -ne 8) {
        $e.Handled = $true
    }
})

$formKG.Add_Paint({
    param($sender, $e)
    if (-not $script:estaExpandidoKG) {
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::Lime, 1)
        $e.Graphics.DrawRectangle($pen, 0, 0, ($formKG.Width - 1), ($formKG.Height - 1))
        $pen.Dispose()
    }
})

function Ocultar-DeAltTab($f) {
    $f.Handle | Out-Null
    $estilo = [Win32]::GetWindowLong($f.Handle, $GWL_EXSTYLE)
    [void][Win32]::SetWindowLong($f.Handle, $GWL_EXSTYLE, ($estilo -bor $WS_EX_TOOLWINDOW) -band -bnot $WS_EX_APPWINDOW)
}
Ocultar-DeAltTab $formKG
$formKG.Show()

$formQueue                 = New-Object System.Windows.Forms.Form
$formQueue.TopMost         = $true
$formQueue.FormBorderStyle = 'None'
$formQueue.BackColor       = [System.Drawing.Color]::FromArgb(10, 10, 10)
$formQueue.Opacity         = 0.92
$formQueue.StartPosition   = 'Manual'
$formQueue.ShowInTaskbar   = $false
$formQueue.Size            = New-Object System.Drawing.Size(230, 54)
$formQueue.Location        = New-Object System.Drawing.Point(($screenKG.Width - 230 - 20), 20)
$formQueue.Visible         = $false

$lblQueue              = New-Object System.Windows.Forms.Label
$lblQueue.Dock         = 'Fill'
$lblQueue.ForeColor    = [System.Drawing.Color]::Lime
$lblQueue.BackColor    = [System.Drawing.Color]::Transparent
$lblQueue.Font         = New-Object System.Drawing.Font('Consolas', 8, [System.Drawing.FontStyle]::Bold)
$lblQueue.TextAlign    = 'MiddleLeft'
$lblQueue.Padding      = New-Object System.Windows.Forms.Padding(6, 0, 4, 0)
$formQueue.Controls.Add($lblQueue)
Ocultar-DeAltTab $formQueue

$formQueue.Add_Paint({
    param($sender, $e)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::Lime, 1)
    $e.Graphics.DrawRectangle($pen, 0, 0, ($formQueue.Width - 1), ($formQueue.Height - 1))
    $pen.Dispose()
})

$qHideTimer          = New-Object System.Windows.Forms.Timer
$qHideTimer.Interval = 2000
$qHideTimer.Add_Tick({ $qHideTimer.Stop(); Ocultar-PanelCola })

function Mostrar-PanelCola($texto) {
    $qHideTimer.Stop()
    $lblQueue.Text = $texto
    if (-not $formQueue.Visible) { $formQueue.Show() }
    $formQueue.Refresh()
}

function Ocultar-PanelCola {
    $formQueue.Hide()
}

$global:lista = @()
$global:index = 0

$global:pressedCtrlEnter    = $false
$global:pressedTab          = $false
$global:pressedCtrlV        = $false
$global:pressedLCtrlSpace   = $false
$global:lastCtrlVTime       = [DateTime]::MinValue
$global:CTRLV_DEBOUNCE_MS   = 200

function Cargar-Lista($lista) {
    $global:lista = $lista
    $global:index = 0

    Restore-Console
    Clear-Host
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "   PO / BOL FILLER - $($lista.Count) elementos" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    for ($i = 0; $i -lt $lista.Count; $i++) {
        Write-Host "  $($i+1).  $($lista[$i])" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "  Ctrl+V          -> pega el siguiente" -ForegroundColor Yellow
    Write-Host "  Ctrl+Shift derecho  -> nuevo lote" -ForegroundColor Yellow
    Write-Host ""

    [System.Windows.Forms.Clipboard]::SetText($lista[0])
    Write-Host "  Portapapeles -> " -NoNewline -ForegroundColor Cyan
    Write-Host "$($lista[0])  (1/$($lista.Count))" -ForegroundColor White
    Write-Host ""

    $msjRep = if ($global:repetidasQuitadas -gt 0) { "  ($($global:repetidasQuitadas) repetida(s) quitada(s))" } else { "" }
    Show-Toast "Cola lista ($($lista.Count))$msjRep" "Primero: $($lista[0])  - Ctrl+V para pegar"
    $panelRep = if ($global:repetidasQuitadas -gt 0) { "  (-$($global:repetidasQuitadas) rep)" } else { "" }
    Mostrar-PanelCola "ARMADO 1/$($lista.Count)$panelRep`n$($lista[0])"

    Minimize-Console
}

function Procesar-CtrlV {
    if ($global:lista.Count -eq 0) { return }

    $i     = $global:index
    $total = $global:lista.Count
    if ($i -ge $total) { return }

    $pegado       = $global:lista[$i]
    $global:index = $i + 1

    Start-Sleep -Milliseconds 300

    if ($global:index -lt $total) {

        [System.Windows.Forms.Clipboard]::SetText($global:lista[$global:index])
        $restantes = $total - $global:index
        Restore-Console
        Write-Host "  OK $pegado  ->  $($global:lista[$global:index])  ($restantes restantes)" -ForegroundColor Green
        Mostrar-PanelCola "PEGASTE: $pegado`nARMADO $($global:index+1)/$total : $($global:lista[$global:index])"
        Minimize-Console
    } else {

        [System.Windows.Forms.Clipboard]::Clear()
        $global:lista  = @()
        $global:index  = 0
        Show-Toast "OK Cola terminada" "Todos los $total elementos pegados. Ctrl+Shift derecho para nuevo lote."
        Mostrar-PanelCola "PEGASTE: $pegado`nCOLA TERMINADA ($total/$total)"

        $qHideTimer.Stop(); $qHideTimer.Start()
        Restore-Console
        Write-Host "  OK $pegado  ->  ULTIMO" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Cola terminada. Ctrl+Shift derecho para nuevo lote." -ForegroundColor Cyan
        Write-Host ""
        Minimize-Console
    }
}

function Procesar-TabExtra {
    for ($t = 0; $t -lt 7; $t++) {
        [System.Windows.Forms.SendKeys]::SendWait("{TAB}")
    }
}

function Abrir-VentanaInput {

    $global:lista  = @()
    $global:index  = 0
    Ocultar-PanelCola

    $raw = Show-InputWindow

    if (-not [string]::IsNullOrWhiteSpace($raw)) {

        $nuevaLista = @(Get-Lista $raw)
        if ($nuevaLista.Count -gt 0) {
            Cargar-Lista $nuevaLista
        } else {
            Show-Toast "Sin elementos" "No se encontraron POs o BOLs en el texto."
            Ocultar-PanelCola
            Minimize-Console
        }
    } else {

        Minimize-Console
    }
}

$qTimer          = New-Object System.Windows.Forms.Timer
$qTimer.Interval = 40

function Drenar-AcumuladorTeclas {

    [void][PoBolWin32]::GetAsyncKeyState(0x11)
    [void][PoBolWin32]::GetAsyncKeyState(0x56)
    [void][PoBolWin32]::GetAsyncKeyState(0xA1)
    [void][PoBolWin32]::GetAsyncKeyState(0xC0)
    [void][PoBolWin32]::GetAsyncKeyState(0xA2)
    [void][PoBolWin32]::GetAsyncKeyState(0x20)
}

function Vaciar-Cola {
    $global:lista  = @()
    $global:index  = 0
    [System.Windows.Forms.Clipboard]::Clear()
    Ocultar-PanelCola
    Show-Toast "Cola vaciada" "Lista limpia. Ctrl+Shift derecho para nuevo lote."
}

$qTimer.Add_Tick({
    try {

        $ctrlRaw   = [PoBolWin32]::GetAsyncKeyState(0x11)
        $rshiftRaw = [PoBolWin32]::GetAsyncKeyState(0xA1)
        $vRaw      = [PoBolWin32]::GetAsyncKeyState(0x56)
        $backtickRaw = [PoBolWin32]::GetAsyncKeyState(0xC0)

        $ctrlDown     = ($ctrlRaw     -band 0x8000) -ne 0
        $ctrlTapped   = ($ctrlRaw     -band 0x0001) -ne 0

        $ctrlActive   = $ctrlDown -or $ctrlTapped
        $rshiftTapped = ($rshiftRaw   -band 0x0001) -ne 0
        $vDown        = ($vRaw        -band 0x8000) -ne 0
        $vTapped      = ($vRaw        -band 0x0001) -ne 0
        $backtickDown   = ($backtickRaw -band 0x8000) -ne 0
        $backtickTapped = ($backtickRaw -band 0x0001) -ne 0

        if ($ctrlActive -and $rshiftTapped -and -not $global:pressedCtrlEnter) {
            $global:pressedCtrlEnter = $true
            $qTimer.Stop()
            Abrir-VentanaInput
            Drenar-AcumuladorTeclas
            $qTimer.Start()
        }
        if (-not $ctrlActive) { $global:pressedCtrlEnter = $false }

        if ($ctrlActive -and $vTapped -and -not $global:pressedCtrlV) {
            $ahora  = Get-Date
            $transcurrido = ($ahora - $global:lastCtrlVTime).TotalMilliseconds
            if ($transcurrido -ge $global:CTRLV_DEBOUNCE_MS) {
                $global:pressedCtrlV  = $true
                $global:lastCtrlVTime = $ahora
                Procesar-CtrlV
            }
        }

        if (-not $vDown) { $global:pressedCtrlV = $false }

        $lctrlRaw   = [PoBolWin32]::GetAsyncKeyState(0xA2)
        $spaceRaw   = [PoBolWin32]::GetAsyncKeyState(0x20)
        $lctrlActive = (($lctrlRaw -band 0x8000) -ne 0) -or (($lctrlRaw -band 0x0001) -ne 0)
        $spaceTapped = ($spaceRaw -band 0x0001) -ne 0
        $spaceDown   = ($spaceRaw -band 0x8000) -ne 0
        if ($lctrlActive -and $spaceTapped -and -not $global:pressedLCtrlSpace) {
            $global:pressedLCtrlSpace = $true
            Vaciar-Cola
        }
        if (-not $spaceDown) { $global:pressedLCtrlSpace = $false }

        if ($backtickTapped -and -not $global:pressedTab) {
            $global:pressedTab = $true
            Procesar-TabExtra
        }
        if (-not $backtickDown) { $global:pressedTab = $false }
    } catch {

        $qTimer.Stop()
        Show-Toast "PO/BOL se detuvo por un error" "$($_.Exception.Message)"
    }
})

Minimize-Console

[System.Windows.Forms.Application]::add_ThreadException({
    param($s, $e)
    Show-Toast "Contador / PO-BOL: error" "$($e.Exception.Message)"
})

Drenar-AcumuladorTeclas

foreach ($vk in 0x12, 0x53, 0x7A, 0x7B) { [void][Win32]::GetAsyncKeyState($vk) }
$qTimer.Start()

try {
    [System.Windows.Forms.Application]::Run($form)
} finally {
    try { [System.Windows.Forms.Clipboard]::Clear() } catch {}
    Remove-Item $lockFile -ErrorAction SilentlyContinue
    if ($script:timerEsperaKG) { $script:timerEsperaKG.Dispose() }
    if ($formKG -and -not $formKG.IsDisposed) { $formKG.Close() }
    if ($formQueue -and -not $formQueue.IsDisposed) { $formQueue.Close() }
}
