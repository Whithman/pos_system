# ==============================================================================
# POS Native Print Agent (Windows Background Service)
# Automatically receives print jobs via local HTTP (port 9100) and sends raw 
# ESC/POS commands directly to Xprinter XP-58 via winspool.drv.
# Completely eliminates the browser print preview modal!
# ==============================================================================

param(
    [int]$Port = 9100,
    [string]$PrinterName = "Xprinter XP-58"
)

$ErrorActionPreference = 'Continue'

# Compile C# RawPrinterHelper
Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;

public class RawPrinterHelper {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public class DOCINFOA {
        [MarshalAs(UnmanagedType.LPStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPStr)] public string pOutputFile;
        [MarshalAs(UnmanagedType.LPStr)] public string pDataType;
    }
    [DllImport("winspool.drv", EntryPoint = "OpenPrinterA", SetLastError = true, CharSet = CharSet.Ansi, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool OpenPrinter([MarshalAs(UnmanagedType.LPStr)] string szPrinter, out IntPtr hPrinter, IntPtr pd);

    [DllImport("winspool.drv", EntryPoint = "ClosePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool ClosePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", EntryPoint = "StartDocPrinterA", SetLastError = true, CharSet = CharSet.Ansi, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool StartDocPrinter(IntPtr hPrinter, int level, [In, MarshalAs(UnmanagedType.LPStruct)] DOCINFOA di);

    [DllImport("winspool.drv", EntryPoint = "EndDocPrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool EndDocPrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", EntryPoint = "StartPagePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool StartPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", EntryPoint = "EndPagePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool EndPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", EntryPoint = "WritePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwWritten);

    public static bool SendBytesToPrinter(string szPrinterName, byte[] pBytes) {
        IntPtr hPrinter = IntPtr.Zero;
        DOCINFOA di = new DOCINFOA();
        di.pDocName = "POS Auto Receipt";
        di.pDataType = "RAW";
        if (OpenPrinter(szPrinterName.Normalize(), out hPrinter, IntPtr.Zero)) {
            if (StartDocPrinter(hPrinter, 1, di)) {
                if (StartPagePrinter(hPrinter)) {
                    IntPtr pUnmanagedBytes = Marshal.AllocCoTaskMem(pBytes.Length);
                    Marshal.Copy(pBytes, 0, pUnmanagedBytes, pBytes.Length);
                    int dwWritten = 0;
                    bool success = WritePrinter(hPrinter, pUnmanagedBytes, pBytes.Length, out dwWritten);
                    Marshal.FreeCoTaskMem(pUnmanagedBytes);
                    EndPagePrinter(hPrinter);
                    EndDocPrinter(hPrinter);
                    ClosePrinter(hPrinter);
                    return success;
                }
                EndDocPrinter(hPrinter);
            }
            ClosePrinter(hPrinter);
        }
        return false;
    }
}
"@

# Helper to find default printer if specified printer is not found
function Get-TargetPrinterName {
    param([string]$Preferred)
    $printers = Get-CimInstance Win32_Printer
    $match = $printers | Where-Object { $_.Name -like "*$Preferred*" } | Select-Object -First 1
    if ($match) { return $match.Name }
    $default = $printers | Where-Object { $_.Default -eq $true } | Select-Object -First 1
    if ($default) { return $default.Name }
    return "Xprinter XP-58"
}

# Helper to format a 2-column receipt line (e.g. "SUBTOTAL:" and "P25.00") with exact 32-character width
function Format-ReceiptLine {
    param([string]$Left, [string]$Right, [int]$Width = 32)
    $leftClean = if ($Left) { $Left.Trim() } else { "" }
    $rightClean = if ($Right) { $Right.Trim() } else { "" }
    $spaces = $Width - $leftClean.Length - $rightClean.Length
    if ($spaces -lt 1) { $spaces = 1 }
    return $leftClean + (' ' * $spaces) + $rightClean + "`n"
}

# Helper to build ESC/POS binary data for a receipt
function Build-EscPosReceipt {
    param([PSCustomObject]$data)
    
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $enc = [System.Text.Encoding]::GetEncoding("ISO-8859-1")

    # 1. Initialize printer: ESC @
    $bw.Write([byte[]]@(0x1B, 0x40))

    # 2. Cash drawer kick pulse: ESC p 0 25 250 (pin 2) + ESC p 1 25 250 (pin 5) + BEL
    $bw.Write([byte[]]@(0x1B, 0x70, 0x00, 0x19, 0xFA, 0x1B, 0x70, 0x01, 0x19, 0xFA, 0x07))

    # 3. Store Name (Centered, Bold, Double-Height/Width): ESC a 1, ESC E 1, GS ! 0x11
    $bw.Write([byte[]]@(0x1B, 0x61, 0x01)) # Center
    $bw.Write([byte[]]@(0x1B, 0x45, 0x01)) # Bold on
    $bw.Write([byte[]]@(0x1D, 0x21, 0x11)) # Double size
    $shopName = if ($data.shop_name) { $data.shop_name } else { "RE M STORE" }
    $bw.Write($enc.GetBytes("$shopName`n"))
    
    # Normal size & font: GS ! 0x00, ESC E 0
    $bw.Write([byte[]]@(0x1D, 0x21, 0x00))
    $bw.Write([byte[]]@(0x1B, 0x45, 0x00))

    if ($data.shop_address) {
        $bw.Write($enc.GetBytes("$($data.shop_address)`n"))
    }
    if ($data.shop_tin) {
        $bw.Write($enc.GetBytes("TIN: $($data.shop_tin)`n"))
    }

    # Left align: ESC a 0
    $bw.Write([byte[]]@(0x1B, 0x61, 0x00))
    $bw.Write($enc.GetBytes("OR#: $($data.ref)`n"))
    $bw.Write($enc.GetBytes("--------------------------------`n"))
    $bw.Write($enc.GetBytes("CASHIER: $($data.cashier)`n"))
    $bw.Write($enc.GetBytes("TERM: $($data.terminal_id)  $($data.date_time)`n"))
    $bw.Write($enc.GetBytes("--------------------------------`n"))
    $bw.Write($enc.GetBytes("QTY  ITEM DESCRIPTION   PRICE    TOTAL`n"))
    $bw.Write($enc.GetBytes("--------------------------------`n"))

    # Items
    if ($data.items) {
        foreach ($it in $data.items) {
            $qtyVal = if ($it.qty) { [double]$it.qty } else { 1.0 }
            $priceVal = if ($it.price) { [double]$it.price } else { 0.0 }
            $qtyStr = "$qtyVal x"
            $nameStr = "$($it.name)"
            if ($nameStr.Length -gt 16) { $nameStr = $nameStr.Substring(0, 16) }
            $priceStr = [string]::Format("{0:N2}", $priceVal)
            $totalStr = [string]::Format("{0:N2}", ($qtyVal * $priceVal))
            
            # Format: "1 x  Item Name       25.00  25.00"
            $line = "{0,-4} {1,-14} {2,6} {3,6}`n" -f $qtyStr, $nameStr, $priceStr, $totalStr
            $bw.Write($enc.GetBytes($line))
        }
    }

    $bw.Write($enc.GetBytes("--------------------------------`n"))

    # Safe double converter
    $toNum = {
        param($v)
        if ($null -eq $v -or "$v".Trim() -eq "") { return 0.0 }
        $d = 0.0
        if ([double]::TryParse("$v", [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
        if ([double]::TryParse("$v", [ref]$d)) { return $d }
        return 0.0
    }

    # Subtotals
    $cur = if ($data.currency) { $data.currency } else { "P" }
    $subtotal = [string]::Format("{0}{1:N2}", $cur, (& $toNum $data.subtotal))
    $vatVal = & $toNum $data.vat
    $taxVal = & $toNum $data.tax
    $vatRate = & $toNum $data.vat_rate
    $taxRate = & $toNum $data.tax_rate
    $vat = [string]::Format("{0}{1:N2}", $cur, $vatVal)
    $tax = [string]::Format("{0}{1:N2}", $cur, $taxVal)
    $total = [string]::Format("{0}{1:N2}", $cur, (& $toNum $data.total))
    $cash = [string]::Format("{0}{1:N2}", $cur, (& $toNum $data.cash))
    $change = [string]::Format("{0}{1:N2}", $cur, (& $toNum $data.change))
    $itemCount = if ($data.item_count) { "$($data.item_count)" } else { "1" }

    $bw.Write($enc.GetBytes((Format-ReceiptLine "SUBTOTAL:" $subtotal)))
    $bw.Write($enc.GetBytes((Format-ReceiptLine "VAT ($vatRate%):" $vat)))
    $bw.Write($enc.GetBytes((Format-ReceiptLine "TAX ($taxRate%):" $tax)))
    
    # TOTAL DUE (Bold, double height)
    $bw.Write([byte[]]@(0x1B, 0x45, 0x01)) # Bold on
    $bw.Write([byte[]]@(0x1D, 0x21, 0x01)) # Double height
    $bw.Write($enc.GetBytes((Format-ReceiptLine "TOTAL DUE:" $total 32)))
    $bw.Write([byte[]]@(0x1D, 0x21, 0x00)) # Normal height
    $bw.Write([byte[]]@(0x1B, 0x45, 0x00)) # Bold off

    $bw.Write($enc.GetBytes("--------------------------------`n"))
    $bw.Write($enc.GetBytes("PAYMENT: CASH`n"))
    $bw.Write($enc.GetBytes((Format-ReceiptLine "CASH TENDERED:" $cash)))
    $bw.Write($enc.GetBytes((Format-ReceiptLine "CHANGE DUE:" $change)))
    $bw.Write($enc.GetBytes((Format-ReceiptLine "ITEMS:" $itemCount)))
    $bw.Write($enc.GetBytes("--------------------------------`n"))

    # Center align footer: ESC a 1
    $bw.Write([byte[]]@(0x1B, 0x61, 0x01))
    $bw.Write($enc.GetBytes("Thank You for Shopping!`n"))
    $bw.Write($enc.GetBytes("Please keep receipt for returns.`n`n"))

    # CODE128 Barcode for clean order ref
    $cleanRef = if ($data.ref) { ($data.ref -split ' \(')[0] } else { "" }
    if ($cleanRef -ne "") {
        # Barcode dimensions: GS h 48 (height), GS w 2 (width)
        $bw.Write([byte[]]@(0x1D, 0x68, 48))
        $bw.Write([byte[]]@(0x1D, 0x77, 2))
        $bw.Write([byte[]]@(0x1D, 0x48, 2)) # Text below barcode
        
        # GS k 73 len {B cleanRef (CODE128)
        $codeBytes = $enc.GetBytes($cleanRef)
        $barcodeData = [System.Collections.Generic.List[byte]]::new()
        $barcodeData.Add(0x7B) # Code Set B
        $barcodeData.Add(0x42) # 'B'
        foreach ($b in $codeBytes) { $barcodeData.Add($b) }
        
        $bw.Write([byte[]]@(0x1D, 0x6B, 73, [byte]$barcodeData.Count))
        $bw.Write($barcodeData.ToArray())
        $bw.Write($enc.GetBytes("`nScan to void this order`n"))
    }

    # Feed 4 lines and partial cut: ESC d 4, GS V 66 0
    $bw.Write([byte[]]@(0x1B, 0x64, 4))
    $bw.Write([byte[]]@(0x1D, 0x56, 66, 0))

    $bw.Flush()
    $result = $ms.ToArray()
    $bw.Close()
    $ms.Close()
    return $result
}

# Start HTTP Listener
$listener = New-Object System.Net.HttpListener
$prefix = "http://127.0.0.1:$Port/"
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " POS Native Print Agent Running on $prefix" -ForegroundColor Green
    Write-Host " Direct silent printing to $PrinterName" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
} catch {
    Write-Host "ERROR: Could not start listener on port $Port : $_" -ForegroundColor Red
    exit 1
}

$actualPrinter = Get-TargetPrinterName -Preferred $PrinterName
Write-Host "Target Printer: $actualPrinter" -ForegroundColor Green

while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $req = $context.Request
        $res = $context.Response

        # Enable CORS for POS app (works for localhost and cloud https://pos-system-9f0n.onrender.com)
        $origin = $req.Headers["Origin"]
        if (-not $origin) { $origin = "*" }
        $res.AddHeader("Access-Control-Allow-Origin", $origin)
        $res.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        $res.AddHeader("Access-Control-Allow-Headers", "Content-Type, X-Requested-With")
        $res.AddHeader("Access-Control-Allow-Credentials", "true")
        $res.AddHeader("Access-Control-Allow-Private-Network", "true")

        if ($req.HttpMethod -eq "OPTIONS") {
            $res.StatusCode = 204
            $res.Close()
            continue
        }

        if ($req.Url.AbsolutePath -eq "/status") {
            $statusObj = @{
                status = "online"
                printer = $actualPrinter
                time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
            $json = ConvertTo-Json $statusObj
            $buf = [System.Text.Encoding]::UTF8.GetBytes($json)
            $res.ContentType = "application/json"
            $res.ContentLength64 = $buf.Length
            $res.OutputStream.Write($buf, 0, $buf.Length)
            $res.Close()
            continue
        }

        if ($req.HttpMethod -eq "POST" -and $req.Url.AbsolutePath -eq "/print") {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $body = $reader.ReadToEnd()
            $reader.Close()

            $data = ConvertFrom-Json $body
            $actualPrinter = Get-TargetPrinterName -Preferred $PrinterName

            Write-Host "[PRINT] Received order print request: $($data.ref) -> Printer: $actualPrinter" -ForegroundColor Green
            $escPosBytes = Build-EscPosReceipt -data $data
            $printSuccess = [RawPrinterHelper]::SendBytesToPrinter($actualPrinter, $escPosBytes)

            $respObj = @{
                success = $printSuccess
                printer = $actualPrinter
                order_ref = $data.ref
            }
            $json = ConvertTo-Json $respObj
            $buf = [System.Text.Encoding]::UTF8.GetBytes($json)
            $res.ContentType = "application/json"
            $res.ContentLength64 = $buf.Length
            $res.OutputStream.Write($buf, 0, $buf.Length)
            $res.Close()
            continue
        }

        # Drawer kick endpoint
        if ($req.HttpMethod -eq "POST" -and $req.Url.AbsolutePath -eq "/drawer") {
            $drawerPulse = [byte[]]@(0x1B, 0x70, 0x00, 0x19, 0xFA, 0x1B, 0x70, 0x01, 0x19, 0xFA, 0x07)
            $actualPrinter = Get-TargetPrinterName -Preferred $PrinterName
            $printSuccess = [RawPrinterHelper]::SendBytesToPrinter($actualPrinter, $drawerPulse)
            $respObj = @{ success = $printSuccess; printer = $actualPrinter }
            $json = ConvertTo-Json $respObj
            $buf = [System.Text.Encoding]::UTF8.GetBytes($json)
            $res.ContentType = "application/json"
            $res.ContentLength64 = $buf.Length
            $res.OutputStream.Write($buf, 0, $buf.Length)
            $res.Close()
            continue
        }

        $res.StatusCode = 404
    } catch {
        Write-Host "Error processing request: $_" -ForegroundColor Red
        if ($res) {
            try {
                $res.StatusCode = 500
                $errObj = @{ success = $false; error = "$_" }
                $buf = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $errObj))
                $res.ContentType = "application/json"
                $res.ContentLength64 = $buf.Length
                $res.OutputStream.Write($buf, 0, $buf.Length)
                $res.Close()
            } catch {}
        }
    }
}
