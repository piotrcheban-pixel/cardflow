# UI-харнесс аудитора CardFlow: поиск окна, ресайз, скриншот, клики, клавиши.
# Только чтение состояния приложения и ввод; файлы проекта не изменяются.

Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public struct RECT { public int Left, Top, Right, Bottom; }
public struct POINT { public int X, Y; }

public class Ui {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool repaint);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint data, IntPtr extra);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();

  [StructLayout(LayoutKind.Sequential)]
  public struct KEYBDINPUT {
    public ushort wVk; public ushort wScan; public uint dwFlags;
    public uint time; public IntPtr dwExtraInfo;
  }

  [StructLayout(LayoutKind.Explicit, Size = 40)]
  public struct INPUT {
    [FieldOffset(0)] public uint type;
    [FieldOffset(8)] public KEYBDINPUT ki;
  }

  [DllImport("user32.dll", SetLastError = true)]
  public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

  public static uint SendUnicode(string s) {
    INPUT[] arr = new INPUT[s.Length * 2];
    int i = 0;
    foreach (char c in s) {
      arr[i].type = 1; arr[i].ki.wVk = 0; arr[i].ki.wScan = (ushort)c; arr[i].ki.dwFlags = 0x0004; i++;
      arr[i].type = 1; arr[i].ki.wVk = 0; arr[i].ki.wScan = (ushort)c; arr[i].ki.dwFlags = 0x0006; i++;
    }
    return SendInput((uint)arr.Length, arr, Marshal.SizeOf(typeof(INPUT)));
  }

  public static IntPtr Found = IntPtr.Zero;
  public static string Needle = "";  public static bool Callback(IntPtr h, IntPtr l) {
    if (!IsWindowVisible(h)) return true;
    int len = GetWindowTextLength(h);
    if (len == 0) return true;
    StringBuilder sb = new StringBuilder(len + 4);
    GetWindowText(h, sb, sb.Capacity);
    string t = sb.ToString();
    if (t.IndexOf(Needle, StringComparison.OrdinalIgnoreCase) >= 0) { Found = h; return false; }
    return true;
  }
  public static IntPtr Find(string needle) {
    Needle = needle; Found = IntPtr.Zero;
    EnumWindows(new EnumWindowsProc(Callback), IntPtr.Zero);
    return Found;
  }
  public static string Title(IntPtr h) {
    int len = GetWindowTextLength(h);
    StringBuilder sb = new StringBuilder(len + 4);
    GetWindowText(h, sb, sb.Capacity);
    return sb.ToString();
  }
}
'@

[Ui]::SetProcessDPIAware() | Out-Null

function Get-AppWindow {
  param([string]$Title = "cardflow")
  # Надёжнее всего — главное окно процесса cardflow (в системе есть и другие
  # окна, в заголовке которых встречается «cardflow», например Chrome).
  $proc = Get-Process cardflow -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if ($proc) { return $proc.MainWindowHandle }
  $h = [Ui]::Find($Title)
  if ($h -eq [IntPtr]::Zero) { throw "Окно '$Title' не найдено" }
  return $h
}

function Get-AppGeometry {
  param([IntPtr]$Handle)
  $wr = New-Object RECT; [Ui]::GetWindowRect($Handle, [ref]$wr) | Out-Null
  $cr = New-Object RECT; [Ui]::GetClientRect($Handle, [ref]$cr) | Out-Null
  [PSCustomObject]@{
    OuterW = $wr.Right - $wr.Left
    OuterH = $wr.Bottom - $wr.Top
    ClientW = $cr.Right - $cr.Left
    ClientH = $cr.Bottom - $cr.Top
    Left = $wr.Left
    Top = $wr.Top
    Dpi = [Ui]::GetDpiForWindow($Handle)
    Maximized = [Ui]::IsZoomed($Handle)
  }
}

# Задать РАЗМЕР КЛИЕНТСКОЙ области (то, что реально видит пользователь).
function Set-AppClientSize {
  param([IntPtr]$Handle, [int]$Width, [int]$Height, [switch]$Center)
  for ($i = 0; $i -lt 3; $i++) {
    $g = Get-AppGeometry -Handle $Handle
    $dw = $Width - $g.ClientW
    $dh = $Height - $g.ClientH
    if ($dw -eq 0 -and $dh -eq 0) { break }
    $newW = $g.OuterW + $dw
    $newH = $g.OuterH + $dh
    $x = $g.Left; $y = $g.Top
    if ($Center) { $x = 0; $y = 0 }
    [Ui]::MoveWindow($Handle, $x, $y, $newW, $newH, $true) | Out-Null
    Start-Sleep -Milliseconds 250
  }
  return Get-AppGeometry -Handle $Handle
}

function Save-AppShot {
  param([IntPtr]$Handle, [string]$Path, [switch]$ScreenFallback)
  $cr = New-Object RECT; [Ui]::GetClientRect($Handle, [ref]$cr) | Out-Null
  $w = $cr.Right - $cr.Left; $h = $cr.Bottom - $cr.Top
  if ($w -le 0 -or $h -le 0) { throw "Пустая клиентская область" }
  $bmp = New-Object System.Drawing.Bitmap($w, $h)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $hdc = $g.GetHdc()
  $ok = [Ui]::PrintWindow($Handle, $hdc, 3)  # PW_CLIENTONLY|PW_RENDERFULLCONTENT
  $g.ReleaseHdc($hdc)
  $g.Dispose()
  $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  return [PSCustomObject]@{ Path = $Path; Width = $w; Height = $h; PrintWindow = $ok }
}

function Save-AppShotScreen {
  param([IntPtr]$Handle, [string]$Path)
  [Ui]::SetForegroundWindow($Handle) | Out-Null
  Start-Sleep -Milliseconds 400
  $cr = New-Object RECT; [Ui]::GetClientRect($Handle, [ref]$cr) | Out-Null
  $pt = New-Object POINT; $pt.X = 0; $pt.Y = 0
  [Ui]::ClientToScreen($Handle, [ref]$pt) | Out-Null
  $w = $cr.Right - $cr.Left; $h = $cr.Bottom - $cr.Top
  $bmp = New-Object System.Drawing.Bitmap($w, $h)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($pt.X, $pt.Y, 0, 0, (New-Object System.Drawing.Size($w, $h)))
  $g.Dispose()
  $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  return [PSCustomObject]@{ Path = $Path; Width = $w; Height = $h; OriginX = $pt.X; OriginY = $pt.Y }
}

# Клик по координатам КЛИЕНТСКОЙ области.
function Invoke-AppClick {
  param([IntPtr]$Handle, [int]$X, [int]$Y, [switch]$Double, [int]$DelayMs = 500)
  [Ui]::SetForegroundWindow($Handle) | Out-Null
  Start-Sleep -Milliseconds 120
  $pt = New-Object POINT; $pt.X = $X; $pt.Y = $Y
  [Ui]::ClientToScreen($Handle, [ref]$pt) | Out-Null
  [Ui]::SetCursorPos($pt.X, $pt.Y) | Out-Null
  Start-Sleep -Milliseconds 80
  [Ui]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
  [Ui]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
  if ($Double) {
    Start-Sleep -Milliseconds 60
    [Ui]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
    [Ui]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
  }
  Start-Sleep -Milliseconds $DelayMs
}

function Send-AppKey {
  param([IntPtr]$Handle, [string]$Key = "ESC", [int]$DelayMs = 600)
  [Ui]::SetForegroundWindow($Handle) | Out-Null
  Start-Sleep -Milliseconds 150
  $vk = switch ($Key.ToUpper()) {
    "ESC" { 0x1B }
    "ENTER" { 0x0D }
    "TAB" { 0x09 }
    "SPACE" { 0x20 }
    "BACKSPACE" { 0x08 }
    "DELETE" { 0x2E }
    "UP" { 0x26 }
    "DOWN" { 0x28 }
    "LEFT" { 0x25 }
    "RIGHT" { 0x27 }
    "HOME" { 0x24 }
    "END" { 0x23 }
    "PGDN" { 0x22 }
    "PGUP" { 0x21 }
    "F5" { 0x74 }
    "ALT" { 0x12 }
    "CTRL" { 0x11 }
    "SHIFT" { 0x10 }
    "A" { 0x41 } "B" { 0x42 } "C" { 0x43 } "D" { 0x44 } "E" { 0x45 }
    "F" { 0x46 } "G" { 0x47 } "H" { 0x48 } "I" { 0x49 } "J" { 0x4A }
    "K" { 0x4B } "L" { 0x4C } "M" { 0x4D } "N" { 0x4E } "O" { 0x4F }
    "P" { 0x50 } "Q" { 0x51 } "R" { 0x52 } "S" { 0x53 } "T" { 0x54 }
    "U" { 0x55 } "V" { 0x56 } "W" { 0x57 } "X" { 0x58 } "Y" { 0x59 }
    "Z" { 0x5A }
    "1" { 0x31 } "2" { 0x32 } "3" { 0x33 } "4" { 0x34 } "5" { 0x35 }
    "6" { 0x36 } "7" { 0x37 } "8" { 0x38 } "9" { 0x39 } "0" { 0x30 }
    default { throw "Неизвестная клавиша: $Key" }
  }
  [Ui]::keybd_event([byte]$vk, 0, 0, [IntPtr]::Zero)
  [Ui]::keybd_event([byte]$vk, 0, 2, [IntPtr]::Zero)
  Start-Sleep -Milliseconds $DelayMs
}

function Send-AppText {
  param([IntPtr]$Handle, [string]$Text, [int]$DelayMs = 400)
  # KEYEVENTF_UNICODE через SendInput: работает с кириллицей (SendKeys — нет).
  [Ui]::SetForegroundWindow($Handle) | Out-Null
  Start-Sleep -Milliseconds 150
  [Ui]::SendUnicode($Text)
  Start-Sleep -Milliseconds $DelayMs
}

# Принудительный вывод окна на передний план (SetForegroundWindow часто
# отказывает фоновому процессу — обходим через AttachThreadInput).
function Set-AppForeground {
  param([IntPtr]$Handle)
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class Fg {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  public static void Force(IntPtr h) {
    IntPtr fg = GetForegroundWindow();
    uint tidFg = GetWindowThreadProcessId(fg, IntPtr.Zero);
    uint tid = GetCurrentThreadId();
    if (tidFg != 0 && tidFg != tid) { AttachThreadInput(tid, tidFg, true); }
    ShowWindow(h, 9);  // SW_RESTORE
    BringWindowToTop(h);
    SetForegroundWindow(h);
    if (tidFg != 0 && tidFg != tid) { AttachThreadInput(tid, tidFg, false); }
  }
}
'@ -ErrorAction SilentlyContinue
  [Fg]::Force($Handle)
  Start-Sleep -Milliseconds 250
}

# Аккорд: клавиша-модификатор удерживается во время второй клавиши.
function Send-AppCombo {
  param([IntPtr]$Handle, [string]$Key = "A", [string]$Modifier = "CTRL", [int]$DelayMs = 500)
  [Ui]::SetForegroundWindow($Handle) | Out-Null
  Start-Sleep -Milliseconds 150
  $modVk = if ($Modifier.ToUpper() -eq "CTRL") { 0x11 } elseif ($Modifier.ToUpper() -eq "SHIFT") { 0x10 } else { 0x12 }
  $keyVk = switch ($Key.ToUpper()) {
    "A" { 0x41 } "C" { 0x43 } "V" { 0x56 } "X" { 0x58 } "Z" { 0x5A } "F" { 0x46 } "S" { 0x53 } "N" { 0x4E } "O" { 0x4F }
    default { throw "Неизвестная клавиша аккорда: $Key" }
  }
  [Ui]::keybd_event([byte]$modVk, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 60
  [Ui]::keybd_event([byte]$keyVk, 0, 0, [IntPtr]::Zero)
  [Ui]::keybd_event([byte]$keyVk, 0, 2, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 60
  [Ui]::keybd_event([byte]$modVk, 0, 2, [IntPtr]::Zero)
  Start-Sleep -Milliseconds $DelayMs
}

function Send-AppWheel {  param([IntPtr]$Handle, [int]$Delta = -360, [int]$AtX = 0, [int]$AtY = 0, [int]$DelayMs = 500)
  [Ui]::SetForegroundWindow($Handle) | Out-Null
  if ($AtX -ne 0 -or $AtY -ne 0) {
    $pt = New-Object POINT; $pt.X = $AtX; $pt.Y = $AtY
    [Ui]::ClientToScreen($Handle, [ref]$pt) | Out-Null
    [Ui]::SetCursorPos($pt.X, $pt.Y) | Out-Null
    Start-Sleep -Milliseconds 120
  }
  [Ui]::mouse_event(0x0800, 0, 0, [uint32]([int64]$Delta -band 4294967295L), [IntPtr]::Zero)
  Start-Sleep -Milliseconds $DelayMs
}

function Get-AppProcess { Get-Process cardflow -ErrorAction SilentlyContinue | Select-Object Id, MainWindowTitle, StartTime }

# Рабочий размер для взаимодействия (окно целиком помещается на экран 1707x960).
$script:WorkClient = @(1660, 900)

function Set-WorkSize {
  param([IntPtr]$Handle)
  return Set-AppClientSize -Handle $Handle -Width $script:WorkClient[0] -Height $script:WorkClient[1]
}

# Снимает текущий экран во всех требуемых разрешениях + рабочий размер.
function Capture-Set {
  param(
    [IntPtr]$Handle,
    [string]$Name,
    [string]$Dir = "review\screenshots"
  )
  New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  $sizes = @(@(1920,1080), @(1366,768), @(1024,768), @(800,600))
  $made = @()
  foreach ($s in $sizes) {
    Set-AppClientSize -Handle $Handle -Width $s[0] -Height $s[1] | Out-Null
    Start-Sleep -Milliseconds 850
    $p = Join-Path $Dir "${Name}_$($s[0])x$($s[1]).png"
    Save-AppShot -Handle $Handle -Path $p | Out-Null
    $made += $p
  }
  Set-WorkSize -Handle $Handle | Out-Null
  Start-Sleep -Milliseconds 850
  $p = Join-Path $Dir "${Name}_work.png"
  Save-AppShot -Handle $Handle -Path $p | Out-Null
  $made += $p
  return $made
}
