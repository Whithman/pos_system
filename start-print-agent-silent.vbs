Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""c:\xampp\htdocs\pos_system\pos-print-agent.ps1""", 0, False
