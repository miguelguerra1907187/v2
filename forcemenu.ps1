if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {

    Start-Process -FilePath 'conhost.exe' -ArgumentList @(
        '--headless', 'powershell.exe', '-NoProfile', '-STA', '-File', "`"$PSCommandPath`""
    ) -WindowStyle Hidden
    exit
}

$script:SingleInstanceMutex = New-Object System.Threading.Mutex($false, 'Local\ForceMenu_Miguel_SingleInstance')
if (-not $script:SingleInstanceMutex.WaitOne(0)) {
    exit
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class LocalKeyState {
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")]
    private static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("user32.dll")]
    private static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    private static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")]
    private static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetConsoleWindow();

    public static void HideConsole() {
        IntPtr h = GetConsoleWindow();
        if (h != IntPtr.Zero) { ShowWindow(h, 0); }
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    private const int GWL_EXSTYLE      = -20;
    private const int WS_EX_TOOLWINDOW = 0x00000080;
    private const int WS_EX_APPWINDOW  = 0x00040000;

    public static void HideFromAltTab(IntPtr hWnd) {
        int exStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
        exStyle |= WS_EX_TOOLWINDOW;
        exStyle &= ~WS_EX_APPWINDOW;
        SetWindowLong(hWnd, GWL_EXSTYLE, exStyle);
    }

    public static bool IsForeground(IntPtr hWnd) { return GetForegroundWindow() == hWnd; }

    public static void ClickAt(IntPtr hWnd, int x, int y) {
        IntPtr lParam = (IntPtr)((y << 16) | (x & 0xFFFF));
        PostMessage(hWnd, 0x0201, (IntPtr)1, lParam);
        PostMessage(hWnd, 0x0202, IntPtr.Zero, lParam);
    }

    private const byte VK_MENU = 0x12;
    private const uint KEYEVENTF_KEYUP = 0x2;

    public static void ForceForeground(IntPtr hWnd) {

        keybd_event(VK_MENU, 0, 0, UIntPtr.Zero);
        keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);

        IntPtr fg = GetForegroundWindow();
        uint dummyProcId;
        uint fgThread = GetWindowThreadProcessId(fg, out dummyProcId);
        uint curThread = GetCurrentThreadId();
        bool attached = false;
        if (fgThread != curThread) {
            attached = AttachThreadInput(curThread, fgThread, true);
        }
        ShowWindow(hWnd, IsIconic(hWnd) ? 9 : 5);
        BringWindowToTop(hWnd);
        SetForegroundWindow(hWnd);
        if (attached) {
            AttachThreadInput(curThread, fgThread, false);
        }
    }
}
"@

[LocalKeyState]::HideConsole()

$HoldText   = 'Hold at term xxx DUE TO'

$ScriptVersion = 'build 2026-09-25g (campos pro sticker corregidos)'

$UsarMacros = $false

$usarTrabajo    = $false
$carpetaCasa    = "C:\Users\Mike1\OneDrive\Escritorio\Nueva carpeta"
$carpetaTrabajo = "C:\Users\mguerrasifuentes\Desktop\New folder\prueba"
$carpetaMacros  = if ($usarTrabajo) { $carpetaTrabajo } else { $carpetaCasa }
$tinyTaskProc   = 'tinytask-1-77'
$playBtnX       = 152
$playBtnY       = 23
$esperaAbrir    = 3
$esperaFocoMs   = 300

$Ventanas = @{
    ERP   = ''
    INTRA = ''
}

$SecuenciaBase = @(
    @{ Tipo='macro'; Rec='copiar_pro.rec';       Foco='ERP';   DuracionSeg=3; PausaDespuesSeg=1 }
    @{ Tipo='macro'; Rec='pegar_pro_intra.rec';  Foco='INTRA'; DuracionSeg=3; PausaDespuesSeg=1 }
    @{ Tipo='clip';  Texto='{INTRA}' }
    @{ Tipo='macro'; Rec='pegar_nota_intra.rec'; Foco='INTRA'; DuracionSeg=2; PausaDespuesSeg=1 }
    @{ Tipo='clip';  Texto='{ERP}' }
    @{ Tipo='macro'; Rec='pegar_nota_erp.rec';   Foco='ERP';   DuracionSeg=2; PausaDespuesSeg=0 }
)
$Recetas = @{ f1 = $SecuenciaBase; haz = $SecuenciaBase }

$Campos       = @('bol','po','quote','weight','reference num')
$ConsShprList = @('city/zip dont route','address','name','zip','city','state','name,add,city,state,zip')

$Force1Issues = @(
    [PSCustomObject]@{ Label='cons';         Tag='cons';         Sub='multi'; SubList=$ConsShprList }
    [PSCustomObject]@{ Label='shpr';         Tag='shpr';         Sub='multi'; SubList=$ConsShprList }
    [PSCustomObject]@{ Label='missing page'; Tag='missing page'; Sub='none' }
    [PSCustomObject]@{ Label='pro sticker';  Tag='pro sticker';  Sub='pro' }
)

$Force2Issues = @(
    [PSCustomObject]@{ Label='improper shipping name';    Tag='improper shipping name';    Sub='none' }
    [PSCustomObject]@{ Label='no hazmat info';            Tag='no hazmat info';            Sub='none' }
    [PSCustomObject]@{ Label='missing chemical const.';   Tag='missing chemical const for'; Sub='text'; Prompt='Item que falta'; Sep=' ' }
    [PSCustomObject]@{ Label='weight breakdown';          Tag='weight breakdown';          Sub='none' }
    [PSCustomObject]@{ Label='missing emergency contact'; Tag='missing emergency contact'; Sub='none' }
    [PSCustomObject]@{ Label='shipper cert not signed';   Tag='shipper cert not signed';   Sub='none' }
    [PSCustomObject]@{ Label='prohibited freight';        Tag='prohibited';                Sub='text'; Prompt='Nombre de la carga' }
    [PSCustomObject]@{ Label='missing page';              Tag='missing page';              Sub='none' }
)

$C = @{
    Bg        = '#16191D'
    Panel     = '#1F242A'
    Key       = '#2A3038'
    KeyBorder = '#3A424C'
    Text      = '#E6EAEE'
    Dim       = '#7E8893'
    F1        = '#4C8DF6'
    HAZ       = '#F29F05'
    HOLD      = '#A7B0BA'
}
$SEP   = ' ' + [char]0x203A + ' '
$CHECK = [string][char]0x2713

$script:State        = 'hidden'
$script:Basket       = New-Object System.Collections.Generic.List[string]
$script:CurrentForce = $null
$script:CurrentIssue = $null
$script:ListCtx      = ''
$script:LM_Options   = @()
$script:LM_Multi     = $false
$script:LM_Highlight = 0
$script:LM_Selected  = New-Object System.Collections.Generic.HashSet[int]
$script:TermDigits   = ''
$script:FreeText      = ''
$script:FreeTextIssue = $null
$script:FreeTextBox   = $null
$script:NotaERP      = ''
$script:LastCopied   = ''
$script:NotePair     = @()
$script:NoteIdx      = 0
$script:History      = New-Object System.Collections.Generic.List[object]

$Win = New-Object System.Windows.Window
$Win.WindowStyle           = 'None'
$Win.AllowsTransparency    = $true
$Win.Background            = 'Transparent'
$Win.Topmost               = $true
$Win.ShowInTaskbar         = $false
$Win.SizeToContent         = 'WidthAndHeight'
$Win.WindowStartupLocation = 'CenterScreen'
$Win.Visibility            = 'Hidden'

$RootGrid = New-Object System.Windows.Controls.Grid
$Win.Content = $RootGrid

$Win.Add_SourceInitialized({
    param($s, $e)
    $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($Win)).Handle
    [LocalKeyState]::HideFromAltTab($hwnd)
})

function B([string]$hex) { return [System.Windows.Media.BrushConverter]::new().ConvertFromString($hex) }
function Get-Soft([string]$hex) { return '#33' + $hex.Substring(1) }
function Clear-Root { $RootGrid.Children.Clear() }
function Trunc([string]$s, [int]$max) {
    if ($s.Length -le $max) { return $s }
    return $s.Substring(0, $max - 1) + [char]0x2026
}

function Get-Accent {
    switch ($script:CurrentForce) {
        'f1'   { return $C.F1 }
        'haz'  { return $C.HAZ }
        'hold' { return $C.HOLD }
    }
    return $C.Dim
}
function Get-Prefix     { if ($script:CurrentForce -eq 'f1') { 'f1' } else { 'haz' } }
function Get-ForceLabel {
    switch ($script:CurrentForce) {
        'f1'   { return 'FORCE 1' }
        'haz'  { return 'FORCE 2  HAZ' }
        'hold' { return 'HOLD' }
    }
    return ''
}
function Get-Issues { if ($script:CurrentForce -eq 'f1') { $Force1Issues } else { $Force2Issues } }
function Get-NotaERP {

    if ($script:Basket.Count -eq 1 -and $script:Basket[0] -like 'prohibited-*') {
        return $script:Basket[0]
    }
    return "$(Get-Prefix)-" + ($script:Basket -join ',')
}

function New-Text([string]$t, [double]$size = 14, [string]$color = '', [string]$weight = 'Normal') {
    if (-not $color) { $color = $C.Text }
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $t.ToUpper()
    $tb.FontSize = $size
    $tb.FontFamily = 'Segoe UI'
    $tb.Foreground = B $color
    $tb.FontWeight = $weight
    $tb.TextWrapping = 'Wrap'
    $tb.VerticalAlignment = 'Center'
    return $tb
}

function New-Keycap([string]$label, [string]$accent = '', [double]$size = 12) {
    $b = New-Object System.Windows.Controls.Border
    $b.Background = B $C.Key
    $b.BorderBrush = B $(if ($accent) { $accent } else { $C.KeyBorder })
    $b.BorderThickness = '1,1,1,2'
    $b.CornerRadius = '4'
    $b.Padding = '6,1,6,1'
    $b.MinWidth = 24
    $b.VerticalAlignment = 'Center'
    $t = New-Text $label $size $C.Text 'SemiBold'
    $t.TextWrapping = 'NoWrap'
    $t.HorizontalAlignment = 'Center'
    $b.Child = $t
    return $b
}

function Show-Frame {
    param([string]$crumb, $body, [string[]]$preview, [string[]]$keys, [string]$accent)
    Clear-Root

    $outer = New-Object System.Windows.Controls.Border
    $outer.Width = 440
    $outer.Background = B $C.Bg
    $outer.BorderBrush = B $accent
    $outer.BorderThickness = '1'
    $outer.CornerRadius = '12'
    $stack = New-Object System.Windows.Controls.StackPanel
    $outer.Child = $stack

    $head = New-Object System.Windows.Controls.Border
    $head.Background = B (Get-Soft $accent)
    $head.CornerRadius = '11,11,0,0'
    $head.Padding = '16,9,16,9'
    $head.Child = (New-Text $crumb 13 $accent 'SemiBold')
    [void]$stack.Children.Add($head)

    $bodyWrap = New-Object System.Windows.Controls.Border
    $bodyWrap.Padding = '16,12,16,10'
    $bodyWrap.Child = $body
    [void]$stack.Children.Add($bodyWrap)

    if ($preview -and $preview.Count -ge 2) {
        $pv = New-Object System.Windows.Controls.Border
        $pv.Background = B $C.Panel
        $pv.CornerRadius = '6'
        $pv.Padding = '10,8,10,8'
        $pv.Margin = '16,0,16,12'
        $pvs = New-Object System.Windows.Controls.StackPanel
        for ($i = 0; $i -lt $preview.Count - 1; $i += 2) {
            $lab = New-Text $preview[$i] 11 $C.Dim
            if ($i -gt 0) { $lab.Margin = '0,6,0,0' }

            $txt = New-Object System.Windows.Controls.TextBox
            $txt.Text = $preview[$i + 1].ToUpper()
            $txt.IsReadOnly = $true
            $txt.IsUndoEnabled = $false
            $txt.BorderThickness = '0'
            $txt.Background = [System.Windows.Media.Brushes]::Transparent
            $txt.Foreground = B $C.Text
            $txt.CaretBrush = B $C.Text
            $txt.SelectionBrush = B (Get-Soft $accent)
            $txt.Padding = '0'
            $txt.Margin = '0'
            $txt.FontSize = 13
            $txt.TextWrapping = 'Wrap'
            $txt.Cursor = [System.Windows.Input.Cursors]::IBeam
            $txt.FocusVisualStyle = $null
            $txt.FontFamily = 'Consolas'
            [void]$pvs.Children.Add($lab)
            [void]$pvs.Children.Add($txt)
        }
        $pv.Child = $pvs
        [void]$stack.Children.Add($pv)
    }

    if ($keys -and $keys.Count -ge 2) {
        $foot = New-Object System.Windows.Controls.WrapPanel
        $foot.Margin = '16,0,16,14'
        for ($i = 0; $i -lt $keys.Count - 1; $i += 2) {
            $sp = New-Object System.Windows.Controls.StackPanel
            $sp.Orientation = 'Horizontal'
            $sp.Margin = '0,0,14,4'
            [void]$sp.Children.Add((New-Keycap $keys[$i] '' 11))
            $lt = New-Text $keys[$i + 1] 11 $C.Dim
            $lt.Margin = '6,0,0,0'
            [void]$sp.Children.Add($lt)
            [void]$foot.Children.Add($sp)
        }
        [void]$stack.Children.Add($foot)
    }

    [void]$RootGrid.Children.Add($outer)
}

function New-Tile([string]$tag, [string]$key, [string]$title, [string]$sub, [string]$accent, [double]$width = 128) {
    $b = New-Object System.Windows.Controls.Border
    $b.Width = $width
    $b.Height = 118
    $b.Margin = '0,0,16,0'
    $b.CornerRadius = '10'
    $b.Background = B $C.Panel
    $b.BorderBrush = B $accent
    $b.BorderThickness = '2'
    $b.Cursor = [System.Windows.Input.Cursors]::Hand
    $b.Tag = $tag

    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.VerticalAlignment = 'Center'
    $kc = New-Keycap $key $accent 12
    $kc.HorizontalAlignment = 'Center'
    $kc.Margin = '0,0,0,8'
    $tt = New-Text $title 28 $accent 'Bold'
    $tt.HorizontalAlignment = 'Center'
    $st = New-Text $sub 11 $C.Dim
    $st.HorizontalAlignment = 'Center'
    $st.TextAlignment = 'Center'
    [void]$sp.Children.Add($kc)
    [void]$sp.Children.Add($tt)
    [void]$sp.Children.Add($st)
    $b.Child = $sp

    $b.Add_MouseLeftButtonUp({ param($s, $e) Select-Nivel1 $s.Tag })
    return $b
}

function New-HistRow([int]$idx, $item) {
    $b = New-Object System.Windows.Controls.Border
    $b.CornerRadius = '6'
    $b.Padding = '6,4,8,4'
    $b.Margin = '0,1,0,1'
    $b.Background = B $C.Panel
    $b.Cursor = [System.Windows.Input.Cursors]::Hand
    $b.Tag = $idx

    $line = New-Object System.Windows.Controls.StackPanel
    $line.Orientation = 'Horizontal'
    [void]$line.Children.Add((New-Keycap ([string]($idx + 3)) '' 12))

    $labelText = Trunc $item.Label 30
    if ($item.Terminal) { $labelText = "$labelText$SEP" + "term $($item.Terminal)" }
    $lbl = New-Text $labelText 13 $C.Text
    $lbl.FontFamily = 'Consolas'
    $lbl.Margin = '10,0,0,0'
    [void]$line.Children.Add($lbl)
    $b.Child = $line

    $b.Add_MouseLeftButtonUp({ param($s, $e) Copy-FromHistory $s.Tag })
    return $b
}

function Show-Nivel1 {
    $script:Basket.Clear()
    $script:CurrentForce = $null
    $script:CurrentIssue = $null
    $script:State = 'nivel1'

    $body = New-Object System.Windows.Controls.StackPanel
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    $row.HorizontalAlignment = 'Center'
    [void]$row.Children.Add((New-Tile 'f1'  '1' 'F1' 'nota f1'       $C.F1  186))
    [void]$row.Children.Add((New-Tile 'haz' '2' 'F2' 'hazmat + hold' $C.HAZ 186))
    [void]$body.Children.Add($row)
    $alt = New-Text 'Tambien flechas Izq / Der' 11 $C.Dim
    $alt.Margin = '0,10,0,0'
    $alt.HorizontalAlignment = 'Center'
    $alt.TextAlignment = 'Center'
    [void]$body.Children.Add($alt)

    if ($script:History.Count -gt 0) {
        $histTitle = New-Text 'Historial (repetir nota)' 11 $C.Dim
        $histTitle.Margin = '0,14,0,4'
        [void]$body.Children.Add($histTitle)
        for ($i = 0; $i -lt $script:History.Count; $i++) {
            [void]$body.Children.Add((New-HistRow $i $script:History[$i]))
        }
    }

    $ver = New-Text $ScriptVersion 9 $C.Dim
    $ver.Margin = '0,14,0,0'
    $ver.HorizontalAlignment = 'Center'
    $ver.Opacity = 0.55
    [void]$body.Children.Add($ver)

    Show-Frame -crumb 'Elige tipo' -body $body -preview $null -keys @('Supr','cerrar') -accent $C.Dim
}

function Select-Nivel1([string]$which) {
    $script:CurrentForce = $which
    Enter-IssueMenu
}

function Enter-IssueMenu {
    $script:CurrentIssue = $null
    $labels = @(Get-Issues | ForEach-Object { $_.Label })
    Enter-List $labels $false 'issue'
}

function Enter-List([string[]]$options, [bool]$multi, [string]$ctx) {
    $script:LM_Options   = $options
    $script:LM_Multi     = $multi
    $script:LM_Highlight = 0
    $script:LM_Selected  = New-Object System.Collections.Generic.HashSet[int]
    $script:ListCtx      = $ctx
    $script:State        = 'list'
    Draw-List
}

function Get-Crumb {
    $c = Get-ForceLabel
    if ($script:ListCtx -ne 'issue' -and $script:CurrentIssue) { $c += $SEP + $script:CurrentIssue.Label }
    if ($script:ListCtx -eq 'pro-fields') { $c += $SEP + 'covering info' }
    return $c
}

function Get-PreviewNote {
    if ($script:Basket.Count -eq 0) { return "$(Get-Prefix)-..." }
    return Get-NotaERP
}

function Draw-List {
    $accent = Get-Accent
    $stack = New-Object System.Windows.Controls.StackPanel

    for ($i = 0; $i -lt $script:LM_Options.Count; $i++) {
        $hl  = ($i -eq $script:LM_Highlight)
        $sel = $script:LM_Multi -and $script:LM_Selected.Contains($i)

        $row = New-Object System.Windows.Controls.Border
        $row.CornerRadius = '6'
        $row.Padding = '6,4,8,4'
        $row.Margin = '0,1,0,1'
        $row.Background = if ($hl) { B (Get-Soft $accent) } else { B '#00000000' }

        $line = New-Object System.Windows.Controls.StackPanel
        $line.Orientation = 'Horizontal'
        $num = if ($i -lt 9) { [string]($i + 1) } else { ' ' }
        [void]$line.Children.Add((New-Keycap $num $(if ($hl) { $accent } else { '' }) 12))

        if ($script:LM_Multi) {
            $mk = New-Text $(if ($sel) { $CHECK } else { '' }) 15 $accent 'Bold'
            $mk.Width = 22
            $mk.TextAlignment = 'Center'
            [void]$line.Children.Add($mk)
        }

        $lbl = New-Text $script:LM_Options[$i] 15 $(if ($sel) { $accent } else { $C.Text }) $(if ($hl) { 'SemiBold' } else { 'Normal' })
        $lbl.Margin = '10,0,0,0'
        [void]$line.Children.Add($lbl)

        $row.Child = $line
        [void]$stack.Children.Add($row)
    }

    $keys = if ($script:LM_Multi) {
        @('1-9','marcar','Enter','listo','Esc','atras','Supr','cerrar')
    } else {
        @('1-9','elegir','Enter','elegir','Esc','atras','Supr','cerrar')
    }
    Show-Frame -crumb (Get-Crumb) -body $stack -preview @('Nota', (Get-PreviewNote)) -keys $keys -accent $accent
}

function Process-ListKey([string]$k) {
    $count = $script:LM_Options.Count
    if ($count -eq 0) { return $null }
    $shift = ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift) -ne 0

    if ($k -eq 'Down' -or ($k -eq 'Tab' -and -not $shift)) {
        $script:LM_Highlight = ($script:LM_Highlight + 1) % $count; Draw-List; return $null
    }
    if ($k -eq 'Up' -or ($k -eq 'Tab' -and $shift)) {
        $script:LM_Highlight = ($script:LM_Highlight - 1 + $count) % $count; Draw-List; return $null
    }
    if ($k -eq 'Space') {
        if ($script:LM_Multi) {
            if ($script:LM_Selected.Contains($script:LM_Highlight)) { [void]$script:LM_Selected.Remove($script:LM_Highlight) }
            else { [void]$script:LM_Selected.Add($script:LM_Highlight) }
            Draw-List
        }
        return $null
    }
    if ($k -eq 'Return' -or $k -eq 'Enter') {
        if ($script:LM_Multi) {

            if ($script:LM_Selected.Count -eq 0) { [void]$script:LM_Selected.Add($script:LM_Highlight) }
            return ,@($script:LM_Selected | Sort-Object | ForEach-Object { $script:LM_Options[$_] })
        }
        return $script:LM_Options[$script:LM_Highlight]
    }
    if ($k -eq 'Escape' -or $k -eq 'Home') { return 'BACK' }
    if ($k -match '^(D|NumPad)([1-9])$') {
        $n = [int]$Matches[2] - 1
        if ($n -lt $count) {
            if ($script:LM_Multi) {
                $script:LM_Highlight = $n
                if ($script:LM_Selected.Contains($n)) { [void]$script:LM_Selected.Remove($n) } else { [void]$script:LM_Selected.Add($n) }
                Draw-List
                return $null
            }
            return $script:LM_Options[$n]
        }
    }
    return $null
}

function Key-List([string]$k) {
    $result = Process-ListKey $k
    if ($null -eq $result) { return }

    if ($result -is [string] -and $result -eq 'BACK') {
        if ($script:ListCtx -eq 'issue') { Show-Nivel1 } else { Enter-IssueMenu }
        return
    }

    switch ($script:ListCtx) {
        'issue' {
            $script:CurrentIssue = Get-Issues | Where-Object { $_.Label -eq $result } | Select-Object -First 1
            switch ($script:CurrentIssue.Sub) {
                'none'  { $script:Basket.Add($script:CurrentIssue.Tag); Enter-Confirm }
                'multi' { Enter-List $script:CurrentIssue.SubList $true 'multi-tag' }
                'pro'   { Enter-List $Campos $true 'pro-fields' }
                'text'  { Enter-FreeText $script:CurrentIssue }
            }
        }
        'multi-tag' {
            $script:Basket.Add($script:CurrentIssue.Tag + '-' + ($result -join ','))
            Enter-Confirm
        }
        'pro-fields' {
            $script:Basket.Add('pro sticker-' + ($result -join ','))
            Enter-Confirm
        }
    }
}

function Test-NeedsHold {
    if ($script:CurrentForce -ne 'f1') { return $true }
    return [bool]($script:Basket | Where-Object { $_ -match '^cons' })
}

function Enter-Confirm {
    $script:State = 'confirm'
    $accent = Get-Accent
    $hold = Test-NeedsHold

    $body = New-Object System.Windows.Controls.StackPanel
    if ($script:Basket.Count -eq 0) {
        [void]$body.Children.Add((New-Text '(sin issues)' 14 $C.Dim))
    }
    for ($i = 0; $i -lt $script:Basket.Count; $i++) {
        $line = New-Object System.Windows.Controls.StackPanel
        $line.Orientation = 'Horizontal'
        $line.Margin = '0,1,0,1'
        $n = New-Text "$($i + 1)." 14 $C.Dim
        $n.Width = 22
        [void]$line.Children.Add($n)
        [void]$line.Children.Add((New-Text $script:Basket[$i] 15))
        [void]$body.Children.Add($line)
    }
    $hl = if ($hold) { New-Text 'Lleva hold: Enter copia la nota ERP (Insert luego pide terminal)' 12 $accent 'SemiBold' }
          else       { New-Text 'Sin hold: Enter copia la nota' 12 $C.Dim }
    $hl.Margin = '0,10,0,0'
    [void]$body.Children.Add($hl)

    $keys = @('Enter', 'copiar ERP', 'Insert','agregar otro','Esc','quitar ultimo','Supr','cerrar')
    Show-Frame -crumb ((Get-ForceLabel) + $SEP + 'revisar') -body $body -preview @('Nota ERP', (Get-PreviewNote)) -keys $keys -accent $accent
}

function Key-Confirm([string]$k) {
    if ($k -eq 'Return' -or $k -eq 'Enter') {
        if ($script:Basket.Count -eq 0) { Enter-IssueMenu; return }
        $n = Get-NotaERP
        if (Test-NeedsHold) { Finish-Notes $n $n $false '' $true }
        else { Finish-Notes $n $n }
        return
    }
    if ($k -match '^(Insert|A|Add)$') { Enter-IssueMenu; return }
    if ($k -eq 'Escape' -or $k -eq 'Home') {
        if ($script:Basket.Count -gt 0) { $script:Basket.RemoveAt($script:Basket.Count - 1) }
        Enter-IssueMenu
    }
}

function Enter-Terminal {
    $script:TermDigits = ''
    $script:NotaERP = if ($script:CurrentForce -eq 'hold') { '' } else { Get-NotaERP }
    $script:State = 'terminal'
    Draw-Terminal
}

function Get-NotaIntra([string]$term) {
    $base = $HoldText -replace 'xxx', $term
    if ($script:NotaERP) { return "$base $($script:NotaERP)" }
    return "$base "
}

function Draw-Terminal {
    $accent = Get-Accent
    $body = New-Object System.Windows.Controls.StackPanel
    [void]$body.Children.Add((New-Text 'Terminal' 11 $C.Dim))

    $boxes = New-Object System.Windows.Controls.StackPanel
    $boxes.Orientation = 'Horizontal'
    $boxes.Margin = '0,6,0,0'
    for ($i = 0; $i -lt 3; $i++) {
        $d = if ($i -lt $script:TermDigits.Length) { [string]$script:TermDigits[$i] } else { '' }
        $cur = ($i -eq $script:TermDigits.Length)
        $bx = New-Object System.Windows.Controls.Border
        $bx.Width = 52; $bx.Height = 60
        $bx.Margin = '0,0,8,0'
        $bx.CornerRadius = '8'
        $bx.Background = B $C.Panel
        $bx.BorderThickness = '2'
        $bx.BorderBrush = B $(if ($cur -or $d) { $accent } else { $C.KeyBorder })
        $tx = New-Text $d 28 $accent 'Bold'
        $tx.HorizontalAlignment = 'Center'
        $bx.Child = $tx
        [void]$boxes.Children.Add($bx)
    }
    [void]$body.Children.Add($boxes)

    $t = if ($script:TermDigits) { $script:TermDigits } else { '___' }
    $preview = if ($script:NotaERP) { @('Intra', (Get-NotaIntra $t), 'ERP', $script:NotaERP) }
               else                 { @('Intra', (Get-NotaIntra $t)) }

    Show-Frame -crumb ((Get-ForceLabel) + $SEP + 'terminal') -body $body -preview $preview `
        -keys @('0-9','terminal','Retroceso','borrar','Enter','copiar','Esc','atras','Supr','cerrar') -accent $accent
}

function Key-Terminal([string]$k) {
    if ($k -match '^(D|NumPad)([0-9])$') {
        if ($script:TermDigits.Length -lt 3) { $script:TermDigits += $Matches[2] }
        Draw-Terminal; return
    }
    if ($k -eq 'Back') {
        if ($script:TermDigits.Length -gt 0) { $script:TermDigits = $script:TermDigits.Substring(0, $script:TermDigits.Length - 1) }
        Draw-Terminal; return
    }
    if ($k -eq 'Return' -or $k -eq 'Enter') {
        if ($script:TermDigits.Length -gt 0) { Finish-Notes (Get-NotaIntra $script:TermDigits) $script:NotaERP $true $script:TermDigits }
        return
    }
    if ($k -eq 'Escape' -or $k -eq 'Home') {
        if ($script:CurrentForce -eq 'hold') { Show-Nivel1 } else { Enter-Confirm }
    }
}

function Enter-FreeText($issue) {
    $script:FreeTextIssue = $issue
    $script:FreeText = ''
    $script:FreeTextBox = $null
    $script:State = 'freetext'
    Draw-FreeText
}

function Draw-FreeText {
    $accent = Get-Accent
    $body = New-Object System.Windows.Controls.StackPanel
    [void]$body.Children.Add((New-Text $script:FreeTextIssue.Prompt 11 $C.Dim))

    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Margin = '0,8,0,0'
    $tb.FontSize = 18
    $tb.FontFamily = 'Consolas'
    $tb.Background = B $C.Panel
    $tb.Foreground = B $C.Text
    $tb.CaretBrush = B $C.Text
    $tb.BorderBrush = B $accent
    $tb.BorderThickness = '2'
    $tb.Padding = '8,6,8,6'
    $tb.CharacterCasing = 'Upper'
    $tb.Text = $script:FreeText
    $tb.MaxLength = 60
    [void]$body.Children.Add($tb)
    $script:FreeTextBox = $tb

    $previewLbl = New-Text '' 12 $C.Dim
    $previewLbl.Margin = '0,10,0,0'
    $previewLbl.FontFamily = 'Consolas'
    [void]$body.Children.Add($previewLbl)

    $tag = $script:FreeTextIssue.Tag
    $sep = if ($script:FreeTextIssue.Sep) { $script:FreeTextIssue.Sep } else { '-' }
    $refreshPreview = {
        $texto = if ($tb.Text) { $tb.Text } else { '...' }
        $previewLbl.Text = ("Nota: $tag$sep$texto").ToUpper()
    }.GetNewClosure()
    & $refreshPreview

    $tb.Add_TextChanged({
        $script:FreeText = $tb.Text
        & $refreshPreview
    }.GetNewClosure())

    Show-Frame -crumb ((Get-ForceLabel) + $SEP + $script:FreeTextIssue.Label) -body $body -preview $null `
        -keys @('Enter','confirmar','Esc','cancelar') -accent $accent

    $tb.Focus() | Out-Null
    [System.Windows.Input.Keyboard]::Focus($tb) | Out-Null
}

function Key-FreeText([string]$k) {
    if ($k -eq 'Return' -or $k -eq 'Enter') {
        $raw = if ($script:FreeTextBox) { $script:FreeTextBox.Text } else { $script:FreeText }
        $texto = ('' + $raw).Trim()
        $sep = if ($script:FreeTextIssue.Sep) { $script:FreeTextIssue.Sep } else { '-' }
        if ($texto) { $script:Basket.Add($script:FreeTextIssue.Tag + $sep + $texto) }
        Enter-Confirm
        return
    }
    if ($k -eq 'Escape' -or $k -eq 'Home') {
        Enter-IssueMenu
    }
}

function Enter-UpperTool {
    $script:State = 'upper'
    Draw-UpperTool
}

function Draw-UpperTool {
    $accent = $C.Dim
    $body = New-Object System.Windows.Controls.StackPanel
    [void]$body.Children.Add((New-Text 'Pega el texto (Ctrl+V). Se convierte solo a mayusculas. Copia lo que necesites (Ctrl+C).' 11 $C.Dim))

    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Margin = '0,8,0,0'
    $tb.FontSize = 14
    $tb.FontFamily = 'Consolas'
    $tb.Background = B $C.Panel
    $tb.Foreground = B $C.Text
    $tb.CaretBrush = B $C.Text
    $tb.BorderBrush = B $accent
    $tb.BorderThickness = '2'
    $tb.Padding = '8,6,8,6'
    $tb.CharacterCasing = 'Upper'
    $tb.AcceptsReturn = $true
    $tb.AcceptsTab = $true
    $tb.TextWrapping = 'Wrap'
    $tb.VerticalScrollBarVisibility = 'Auto'
    $tb.Height = 220
    [void]$body.Children.Add($tb)

    Show-Frame -crumb 'Mayusculas' -body $body -preview $null `
        -keys @('Ctrl+V','pegar','Ctrl+C','copiar','Esc','regresar') -accent $accent

    $tb.Focus() | Out-Null
    [System.Windows.Input.Keyboard]::Focus($tb) | Out-Null
}

$script:SeqActions = New-Object System.Collections.Generic.List[object]
$script:SeqIdx     = 0
$script:SeqRunning = $false
$script:SeqFocusH  = [IntPtr]::Zero
$script:SeqTimer   = New-Object System.Windows.Threading.DispatcherTimer
$script:SeqTimer.Add_Tick({ param($s, $e) $s.Stop(); Step-Seq })

function Strip-Formato([string]$s) {

    -join ($s.ToCharArray() | Where-Object {
        [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne [System.Globalization.UnicodeCategory]::Format
    })
}

function Find-Ventana([string]$clave) {
    $titulo = $Ventanas[$clave]
    $p = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and (Strip-Formato $_.MainWindowTitle) -like "*$titulo*" } |
        Select-Object -First 1
    if (-not $p) { throw "No encontre la ventana '$titulo' ($clave)." }
    return $p.MainWindowHandle
}

function Add-Act([string]$kind, $data, [int]$delayMs) {
    $script:SeqActions.Add(@{ Kind = $kind; Data = $data; Delay = $delayMs })
}

function Invoke-Act($a) {
    switch ($a.Kind) {
        'clip' { Set-Clip $a.Data }
        'open' {
            Get-Process -ErrorAction SilentlyContinue |
                Where-Object { $_.ProcessName -match 'tinytask' } |
                Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 300
            Start-Process -FilePath (Join-Path $carpetaMacros $a.Data)
        }
        'focus' {

            $script:SeqFocusH = [IntPtr]::Zero
            if ($a.Data -and $Ventanas[$a.Data]) {
                $script:SeqFocusH = Find-Ventana $a.Data
                [LocalKeyState]::ForceForeground($script:SeqFocusH)
                if ($a.Data -eq 'INTRA') {

                    Start-Sleep -Milliseconds 100
                    [System.Windows.Forms.SendKeys]::SendWait('^1')
                }
            }
        }
        'play' {
            if ($script:SeqFocusH -ne [IntPtr]::Zero -and -not [LocalKeyState]::IsForeground($script:SeqFocusH)) {
                [LocalKeyState]::ForceForeground($script:SeqFocusH)
                Start-Sleep -Milliseconds 250
                if (-not [LocalKeyState]::IsForeground($script:SeqFocusH)) { throw 'No pude enfocar la ventana destino.' }
            }
            $tt = Get-Process -Name $tinyTaskProc -ErrorAction SilentlyContinue |
                Sort-Object StartTime -Descending | Select-Object -First 1
            if (-not $tt -or $tt.MainWindowHandle -eq [IntPtr]::Zero) { throw 'No encontre la ventana de TinyTask.' }
            [LocalKeyState]::ClickAt($tt.MainWindowHandle, $playBtnX, $playBtnY)
        }
    }
}

function Step-Seq {
    if (-not $script:SeqRunning) { return }
    if ($script:SeqIdx -ge $script:SeqActions.Count) { Stop-Seq ''; return }
    $a = $script:SeqActions[$script:SeqIdx]
    $script:SeqIdx++
    try { Invoke-Act $a } catch { Stop-Seq $_.Exception.Message; return }
    $script:SeqTimer.Interval = [TimeSpan]::FromMilliseconds([Math]::Max(50, $a.Delay))
    $script:SeqTimer.Start()
}

function Stop-Seq([string]$err) {
    $script:SeqTimer.Stop()
    $script:SeqRunning = $false
    $circle.Fill = B $C.F1
    if ($err) {
        [System.Windows.MessageBox]::Show("$err`n`nRevisa ERP e intra antes de guardar.", 'Secuencia detenida',
            'OK', 'Warning') | Out-Null
    }
}

function Start-Seq([string]$intra, [string]$erp) {
    if ($script:SeqRunning) { return 'Ya hay una secuencia corriendo' }
    $receta = $Recetas[$script:CurrentForce]
    if (-not $receta) { return "No hay receta para $($script:CurrentForce)" }

    $faltan = @($receta | Where-Object { $_.Tipo -eq 'macro' -and -not (Test-Path (Join-Path $carpetaMacros $_.Rec)) } | ForEach-Object { $_.Rec })
    if ($faltan.Count -gt 0) { return 'Faltan macros: ' + ($faltan -join ', ') }
    try {
        foreach ($k in @($receta | ForEach-Object { $_.Foco } | Where-Object { $_ -and $Ventanas[$_] } | Select-Object -Unique)) {
            Find-Ventana $k | Out-Null
        }
    } catch { return $_.Exception.Message }

    $script:SeqActions.Clear()
    foreach ($p in $receta) {
        if ($p.Tipo -eq 'clip') {
            Add-Act 'clip' ($p.Texto.Replace('{INTRA}', $intra).Replace('{ERP}', $erp)) 150
        } else {
            Add-Act 'open'  $p.Rec  ([int]($esperaAbrir * 1000))
            Add-Act 'focus' $p.Foco $esperaFocoMs
            Add-Act 'play'  $null   ([int](($p.DuracionSeg + $p.PausaDespuesSeg) * 1000))
        }
    }
    $script:SeqIdx = 0
    $script:SeqRunning = $true
    $circle.Fill = B '#3FB950'

    $script:SeqTimer.Interval = [TimeSpan]::FromMilliseconds(1600)
    $script:SeqTimer.Start()
    return 'Macros en curso. Pausa (Pause/Break) = abortar'
}

function Set-Clip([string]$t) {
    $t = $t.ToUpper()
    for ($i = 0; $i -lt 6; $i++) {
        try {
            [System.Windows.Clipboard]::SetText($t)
            return $true
        } catch {
            Start-Sleep -Milliseconds 50
        }
    }
    return $false
}

function Add-History([string]$intra, [string]$erp, [string]$forceType, [string]$terminal) {
    $label = if ($erp -and $intra -ne $erp) { $erp } else { $intra }
    $item = [PSCustomObject]@{ Intra = $intra; Erp = $erp; Label = $label; Force = $forceType; Terminal = $terminal }
    $script:History.Insert(0, $item)
    while ($script:History.Count -gt 3) { $script:History.RemoveAt($script:History.Count - 1) }
}

$script:DoneIntra   = ''
$script:DoneErp     = ''
$script:DoneMsg     = ''

$script:PendingHold = $false

function Draw-Done {
    $accent = Get-Accent
    $body = New-Object System.Windows.Controls.StackPanel
    [void]$body.Children.Add((New-Text 'Copiado' 18 $accent 'Bold'))

    if ($script:NotePair.Count -eq 2) {
        $activo = if ($script:NoteIdx -eq 0) { 'Intra / Hold' } else { 'ERP' }
        $h = New-Text "En el portapapeles: $activo  (Insert alterna)" 12 $accent 'SemiBold'
        $h.Margin = '0,4,0,0'
        [void]$body.Children.Add($h)
    } elseif ($script:PendingHold) {
        $h = New-Text 'En el portapapeles: ERP  (Insert = dar terminal y copiar hold)' 12 $accent 'SemiBold'
        $h.Margin = '0,4,0,0'
        [void]$body.Children.Add($h)
    }
    if ($script:DoneMsg) {
        $m = New-Text $script:DoneMsg 12 $accent 'SemiBold'
        $m.Margin = '0,4,0,0'
        [void]$body.Children.Add($m)
    }

    $preview =
        if ($script:NotePair.Count -eq 2) {
            if ($script:NoteIdx -eq 0) { @("$([char]0x25B8) Intra / Hold", $script:DoneIntra, 'ERP', $script:DoneErp) }
            else                       { @('Intra / Hold', $script:DoneIntra, "$([char]0x25B8) ERP", $script:DoneErp) }
        } elseif ($script:DoneErp) { @('Nota intra y ERP', $script:DoneIntra) }
        else                       { @('Intra (completa la razon)', $script:DoneIntra) }

    $doneKeys = New-Object System.Collections.Generic.List[string]
    $doneKeys.Add('1'); $doneKeys.Add($(if ($script:PendingHold) { 'copiar erp' } else { 'copiar intra/hold' }))
    if ($script:NotePair.Count -eq 2) {
        $doneKeys.Add('2'); $doneKeys.Add('copiar erp')
        $doneKeys.Add('Insert'); $doneKeys.Add('alternar')
    } elseif ($script:PendingHold) {
        $doneKeys.Add('Insert'); $doneKeys.Add('terminal / hold')
    }
    $doneKeys.Add('Supr'); $doneKeys.Add('cerrar')

    Show-Frame -crumb ((Get-ForceLabel) + $SEP + 'listo') -body $body -preview $preview -keys $doneKeys.ToArray() -accent $accent
}

function Finish-Notes([string]$intra, [string]$erp, [bool]$addToHistory = $true, [string]$terminal = '', [bool]$pendingHold = $false) {
    $script:LastCopied  = $intra
    $script:PendingHold = $pendingHold
    if ($erp -and $intra -ne $erp) {
        $script:NotePair = @($intra, $erp)
        $script:NoteIdx  = 0
    } else {
        $script:NotePair = @()
    }
    $copiado = Set-Clip $intra
    if ($addToHistory) { Add-History $intra $erp $script:CurrentForce $terminal }

    $msg = ''
    if (-not $copiado) { $msg = 'No se pudo copiar (portapapeles ocupado) -- dale 1 para reintentar' }
    elseif ($UsarMacros -and $erp -and $addToHistory) { $msg = Start-Seq $intra $erp }

    $script:DoneIntra = $intra
    $script:DoneErp   = $erp
    $script:DoneMsg   = $msg
    $script:State     = 'done'
    Draw-Done

    if ($pendingHold) { return }

    $t = New-Object System.Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromMilliseconds(30000)
    $t.Add_Tick({
        param($s, $e)
        $s.Stop()
        if ($script:State -eq 'done') { Close-Menu }
    })
    $t.Start()
}

function Copy-FromHistory([int]$idx) {
    if ($idx -lt 0 -or $idx -ge $script:History.Count) { return }
    $item = $script:History[$idx]
    $script:CurrentForce = $item.Force
    Finish-Notes $item.Intra $item.Erp $false $item.Terminal
}

function Close-Menu {
    $script:Basket.Clear()
    $script:CurrentForce = $null
    $script:PendingHold  = $false
    $script:State = 'hidden'
    $Win.Visibility = 'Hidden'
}

function Set-MenuFocus {
    $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($Win)).Handle

    [LocalKeyState]::HideFromAltTab($hwnd)
    [LocalKeyState]::ForceForeground($hwnd)
    $Win.Activate() | Out-Null
    $Win.Focus() | Out-Null
    [System.Windows.Input.Keyboard]::Focus($Win) | Out-Null
}

function Open-Menu {
    if ($script:SeqRunning) { return }
    if ($Win.Visibility -eq 'Visible') { return }
    $Win.Visibility = 'Visible'
    Set-MenuFocus
    Show-Nivel1

    $retry = New-Object System.Windows.Threading.DispatcherTimer
    $retry.Interval = [TimeSpan]::FromMilliseconds(120)
    $retry.Add_Tick({
        param($s, $e)
        $s.Stop()
        if ($Win.Visibility -eq 'Visible') { Set-MenuFocus }
    })
    $retry.Start()
}

function Key-Nivel1([string]$k) {
    if ($k -match '^(Left|D1|NumPad1)$')  { Select-Nivel1 'f1';  return }
    if ($k -match '^(Right|D2|NumPad2)$') { Select-Nivel1 'haz'; return }
    if ($k -match '^(D3|NumPad3)$' -and $script:History.Count -ge 1) { Copy-FromHistory 0; return }
    if ($k -match '^(D4|NumPad4)$' -and $script:History.Count -ge 2) { Copy-FromHistory 1; return }
    if ($k -match '^(D5|NumPad5)$' -and $script:History.Count -ge 3) { Copy-FromHistory 2; return }
    if ($k -eq 'M') { Enter-UpperTool; return }
    if ($k -eq 'Escape') { Close-Menu }
}

function Key-Done([string]$k) {
    if ($k -match '^(D1|NumPad1)$') {
        $script:NoteIdx = 0
        Set-Clip $script:LastCopied
        if ($script:NotePair.Count -eq 2) { Draw-Done }
        return
    }
    if ($k -match '^(D2|NumPad2)$' -and $script:NotePair.Count -eq 2) {
        $script:NoteIdx = 1
        Set-Clip $script:NotePair[1]
        Draw-Done
        return
    }

}

function Handle-KeyDown {
    param($s, $e)
    if ($script:State -eq 'hidden') { return }
    $k = $e.Key.ToString()

    if ($script:State -eq 'freetext') {
        if ($k -eq 'Return' -or $k -eq 'Enter' -or $k -eq 'Escape' -or $k -eq 'Home') {
            $e.Handled = $true
            try { Key-FreeText $k } catch { }
        }
        return
    }

    if ($script:State -eq 'upper') {
        if ($k -eq 'Escape' -or $k -eq 'Home') {
            $e.Handled = $true
            try { Show-Nivel1 } catch { }
        }
        return
    }

    $e.Handled = $true

    try {
        switch ($script:State) {
            'nivel1'   { Key-Nivel1 $k }
            'list'     { Key-List $k }
            'confirm'  { Key-Confirm $k }
            'terminal' { Key-Terminal $k }
            'done'     { Key-Done $k }
        }
    } catch { }
}

$Win.Add_KeyDown({ param($s, $e) Handle-KeyDown $s $e })

$Widget = New-Object System.Windows.Window
$Widget.WindowStyle = 'None'
$Widget.AllowsTransparency = $true
$Widget.Background = 'Transparent'
$Widget.Topmost = $true
$Widget.ShowInTaskbar = $false
$Widget.Width = 42
$Widget.Height = 42
$Widget.ResizeMode = 'NoResize'

$screen = [System.Windows.SystemParameters]::WorkArea
$Widget.Left = $screen.Right - 60
$Widget.Top  = $screen.Bottom - 60

$circle = New-Object System.Windows.Shapes.Ellipse
$circle.Width = 42
$circle.Height = 42
$circle.Fill = B $C.F1
$circle.Opacity = 0.85
$Widget.Content = $circle

$VK_DELETE = 0x2E
$VK_INSERT = 0x2D
$VK_PAUSE  = 0x13

$script:DelArmed = $true
$script:InsArmed = $true
$hotkeyTimer = New-Object System.Windows.Threading.DispatcherTimer
$hotkeyTimer.Interval = [TimeSpan]::FromMilliseconds(60)
$hotkeyTimer.Add_Tick({
    if ($script:SeqRunning -and (([LocalKeyState]::GetAsyncKeyState($VK_PAUSE) -band 0x8000) -ne 0)) {
        Stop-Seq 'Abortado con Pausa.'
    }
    $del = ([LocalKeyState]::GetAsyncKeyState($VK_DELETE) -band 0x8000) -ne 0
    $ins = ([LocalKeyState]::GetAsyncKeyState($VK_INSERT) -band 0x8000) -ne 0
    $delEdge = $del -and $script:DelArmed
    $insEdge = $ins -and $script:InsArmed
    $script:DelArmed = -not $del
    $script:InsArmed = -not $ins
    if ($script:State -eq 'upper') { return }
    if (-not ($delEdge -or $insEdge)) { return }
    if ($script:SeqRunning) { return }

    if ($delEdge) {
        if ($script:State -eq 'hidden') { Open-Menu } else { Close-Menu }
    }
    if ($insEdge -and $script:State -eq 'done' -and $script:PendingHold) {

        Enter-Terminal
    } elseif ($insEdge -and ($script:State -eq 'hidden' -or $script:State -eq 'done')) {
        if ($script:NotePair.Count -eq 2) {
            $script:NoteIdx = 1 - $script:NoteIdx
            Set-Clip $script:NotePair[$script:NoteIdx]
            if ($script:State -eq 'done') { Draw-Done }
        } elseif ($script:LastCopied) {
            Set-Clip $script:LastCopied
        }
    }
})
$hotkeyTimer.Start()

$Widget.Add_Closed({ [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown() })

[System.Windows.Threading.Dispatcher]::Run()
