# find-api-calls.ps1 — Search decompiled source for API calls, network endpoints, and secrets
#
# Usage: find-api-calls.ps1 <source-dir> [OPTIONS]
#
# Options:
#   --network      Search only for network/HTTP patterns
#   --registry     Search only for registry operations
#   --filesystem   Search only for file system operations
#   --process      Search only for process manipulation (injection indicators)
#   --crypto       Search only for cryptography patterns
#   --com          Search only for COM/WMI patterns
#   --services     Search only for Windows service patterns
#   --urls         Search only for hardcoded URLs and IPs
#   --auth         Search only for authentication/API key patterns
#   --persistence  Search only for persistence mechanisms
#   --all          Search all patterns (default)
#   --help         Show help message

param(
    [Parameter(Position=0)]
    [string]$SourceDir,

    [switch]$Network,
    [switch]$Registry,
    [switch]$FileSystem,
    [switch]$Process,
    [switch]$Crypto,
    [switch]$Com,
    [switch]$Services,
    [switch]$Urls,
    [switch]$Auth,
    [switch]$Persistence,
    [switch]$All,

    [Alias('h')]
    [switch]$Help
)

$ErrorActionPreference = 'SilentlyContinue'

function Show-Usage {
    @"
Usage: find-api-calls.ps1 <source-dir> [OPTIONS]

Search decompiled source (C pseudocode or C# files) for API calls and patterns.

Arguments:
  <source-dir>    Path to the decompiled sources directory

Options:
  --Network       Search only for network/HTTP patterns
  --Registry      Search only for registry operations
  --FileSystem    Search only for file system operations
  --Process       Search only for process manipulation (injection indicators)
  --Crypto        Search only for cryptography patterns
  --Com           Search only for COM/WMI patterns
  --Services      Search only for Windows service patterns
  --Urls          Search only for hardcoded URLs, IPs, and secrets
  --Auth          Search only for authentication/API key patterns
  --Persistence   Search only for persistence mechanisms
  --All           Search all patterns (default)
  --Help          Show this help message

Output:
  Results are printed as file:line:match for easy navigation.
"@
    exit 0
}

if ($Help) { Show-Usage }

if (-not $SourceDir) {
    Write-Host "Error: No source directory specified." -ForegroundColor Red
    Show-Usage
}

if (-not (Test-Path $SourceDir)) {
    Write-Host "Error: Directory not found: $SourceDir" -ForegroundColor Red
    exit 1
}

# Determine if any specific flag is set
$specificSearch = $Network -or $Registry -or $FileSystem -or $Process -or $Crypto -or $Com -or $Services -or $Urls -or $Auth -or $Persistence
$searchAll = $All -or (-not $specificSearch)

# File extensions to search
$includes = @("*.c", "*.cs", "*.h", "*.cpp", "*.txt")

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "==== $Title ====" -ForegroundColor Cyan
    Write-Host ""
}

function Search-Pattern {
    param(
        [string]$Pattern,
        [switch]$CaseInsensitive
    )

    $params = @{
        Path = $SourceDir
        Pattern = $Pattern
        Include = $includes
        Recurse = $true
    }

    if ($CaseInsensitive) {
        $params.CaseSensitive = $false
    }

    $results = Select-String @params 2>$null

    if ($results) {
        foreach ($r in $results) {
            $relPath = $r.Path
            try {
                $relPath = [System.IO.Path]::GetRelativePath($SourceDir, $r.Path)
            } catch { }
            Write-Host "${relPath}:$($r.LineNumber):$($r.Line.Trim())"
        }
    }
}

# =====================================================================
# Search categories
# =====================================================================

# --- Network (Native Win32) ---
if ($searchAll -or $Network) {
    Write-Section "WinHTTP"
    Search-Pattern 'WinHttpOpen|WinHttpConnect|WinHttpOpenRequest|WinHttpSendRequest|WinHttpReceiveResponse|WinHttpReadData|WinHttpSetOption|WinHttpQueryHeaders'

    Write-Section "WinINet"
    Search-Pattern 'InternetOpen[AW]?|InternetConnect[AW]?|HttpOpenRequest[AW]?|HttpSendRequest[AW]?|InternetReadFile|InternetCloseHandle|InternetSetOption[AW]?|HttpQueryInfo[AW]?'

    Write-Section "Winsock"
    Search-Pattern 'WSAStartup|socket\s*\(|connect\s*\(|send\s*\(|recv\s*\(|bind\s*\(|listen\s*\(|accept\s*\(|closesocket|getaddrinfo|gethostbyname|WSASocket|WSASend|WSARecv'

    Write-Section ".NET HttpClient"
    Search-Pattern 'HttpClient|GetAsync|PostAsync|PutAsync|DeleteAsync|SendAsync|GetStringAsync|GetStreamAsync|IHttpClientFactory|AddHttpClient|CreateClient'

    Write-Section ".NET WebRequest (legacy)"
    Search-Pattern 'WebRequest|HttpWebRequest|WebClient|DownloadString|DownloadFile|UploadString|UploadFile'

    Write-Section ".NET HTTP Request Construction"
    Search-Pattern 'HttpRequestMessage|StringContent|JsonContent|FormUrlEncodedContent|MultipartFormDataContent|BaseAddress'

    Write-Section "RestSharp / Refit"
    Search-Pattern 'RestClient|RestRequest|RestResponse|IRestClient|\[Get\(|\[Post\(|\[Put\(|\[Delete\(|\[Patch\('
}

# --- Registry ---
if ($searchAll -or $Registry) {
    Write-Section "Registry (Native)"
    Search-Pattern 'RegOpenKey[AW]?(Ex)?|RegCreateKey[AW]?(Ex)?|RegSetValue[AW]?(Ex)?|RegQueryValue[AW]?(Ex)?|RegDeleteKey[AW]?(Ex)?|RegDeleteValue[AW]?|RegEnumKey[AW]?(Ex)?|RegEnumValue[AW]?|RegCloseKey'

    Write-Section "Registry (.NET)"
    Search-Pattern 'Microsoft\.Win32\.Registry|RegistryKey|OpenSubKey|SetValue|GetValue|CreateSubKey|DeleteSubKey|RegistryHive'
}

# --- File System ---
if ($searchAll -or $FileSystem) {
    Write-Section "File System (Native)"
    Search-Pattern 'CreateFile[AW]?|ReadFile|WriteFile|DeleteFile[AW]?|CopyFile[AW]?|MoveFile[AW]?(Ex)?|FindFirstFile[AW]?|FindNextFile[AW]?|GetFileAttributes[AW]?|SetFileAttributes[AW]?|CreateDirectory[AW]?|RemoveDirectory[AW]?|GetTempPath|GetTempFileName'

    Write-Section "File System (.NET)"
    Search-Pattern 'File\.(Read|Write|Append|Copy|Move|Delete|Exists|Open|Create)|Directory\.(Create|Delete|Exists|GetFiles|GetDirectories)|FileStream|StreamReader|StreamWriter|BinaryReader|BinaryWriter|Path\.Combine|Path\.GetTempPath'
}

# --- Process and Thread Manipulation ---
if ($searchAll -or $Process) {
    Write-Section "Process Creation"
    Search-Pattern 'CreateProcess[AW]?|ShellExecute[AW]?(Ex)?|WinExec|system\s*\('

    Write-Section "Process Injection Indicators"
    Search-Pattern 'VirtualAlloc(Ex)?|VirtualProtect(Ex)?|WriteProcessMemory|ReadProcessMemory|CreateRemoteThread(Ex)?|NtCreateThreadEx|QueueUserAPC|SetThreadContext|GetThreadContext|SuspendThread|ResumeThread'

    Write-Section "DLL Loading"
    Search-Pattern 'LoadLibrary[AW]?(Ex)?|GetProcAddress|FreeLibrary|GetModuleHandle[AW]?|GetModuleFileName[AW]?'

    Write-Section "Process (.NET)"
    Search-Pattern 'Process\.Start|ProcessStartInfo|Process\.GetProcesses|Process\.GetCurrentProcess'

    Write-Section "Memory Mapping"
    Search-Pattern 'CreateFileMapping[AW]?|MapViewOfFile(Ex)?|OpenFileMapping[AW]?|UnmapViewOfFile'
}

# --- Cryptography ---
if ($searchAll -or $Crypto) {
    Write-Section "CryptoAPI (Native)"
    Search-Pattern 'CryptAcquireContext|CryptEncrypt|CryptDecrypt|CryptHashData|CryptDeriveKey|CryptGenKey|CryptImportKey|CryptExportKey|CryptGenRandom|CryptCreateHash|CryptSetKeyParam'

    Write-Section "BCrypt (Native)"
    Search-Pattern 'BCryptOpenAlgorithmProvider|BCryptEncrypt|BCryptDecrypt|BCryptGenerateSymmetricKey|BCryptHash|BCryptCreateHash|BCryptFinishHash|BCryptDeriveKey|BCryptGenerateKeyPair'

    Write-Section "Cryptography (.NET)"
    Search-Pattern 'System\.Security\.Cryptography|Aes\.|AesManaged|AesCryptoServiceProvider|RSA\.|RSACryptoServiceProvider|SHA256|SHA512|MD5|HMAC|RijndaelManaged|X509Certificate|ProtectedData|DataProtection'
}

# --- COM and WMI ---
if ($searchAll -or $Com) {
    Write-Section "COM"
    Search-Pattern 'CoCreateInstance|CoInitialize(Ex)?|CoUninitialize|IDispatch|IUnknown|CLSIDFromProgID|ProgIDFromCLSID|CoGetClassObject'

    Write-Section "WMI (Native)"
    Search-Pattern 'IWbemLocator|IWbemServices|ConnectServer|ExecQuery|ExecMethod'

    Write-Section "WMI (.NET)"
    Search-Pattern 'ManagementObjectSearcher|ManagementObject|ManagementScope|ObjectQuery|WqlObjectQuery|SelectQuery|ManagementClass'
}

# --- Windows Services ---
if ($searchAll -or $Services) {
    Write-Section "Services (Native)"
    Search-Pattern 'OpenSCManager[AW]?|CreateService[AW]?|OpenService[AW]?|StartService|ControlService|DeleteService|ChangeServiceConfig[AW]?|QueryServiceStatus(Ex)?|RegisterServiceCtrlHandler(Ex)?|SetServiceStatus|StartServiceCtrlDispatcher'

    Write-Section "Services (.NET)"
    Search-Pattern 'ServiceBase|ServiceController|ServiceInstaller|ServiceProcessInstaller|OnStart|OnStop|ServiceName|RunAsService'
}

# --- Hardcoded URLs, IPs, and Secrets ---
if ($searchAll -or $Urls) {
    Write-Section "Hardcoded URLs (http:// and https://)"
    Search-Pattern '"https?://[^"]+'

    Write-Section "IP Addresses"
    Search-Pattern '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'

    Write-Section "Connection Strings"
    Search-Pattern 'Data Source=|Server=|Initial Catalog=|connectionString|ConnectionStrings|Provider=' -CaseInsensitive

    Write-Section "File Paths"
    Search-Pattern '"[A-Za-z]:\\[^"]+"|"\\\\[^"]+'
}

# --- Authentication and API Keys ---
if ($searchAll -or $Auth) {
    Write-Section "Authentication and API Keys"
    Search-Pattern 'api[_\-]?key|api[_\-]?secret|auth[_\-]?token|bearer|authorization|x-api-key|client[_\-]?secret|access[_\-]?token|refresh[_\-]?token' -CaseInsensitive

    Write-Section "Base URLs and Constants"
    Search-Pattern 'BASE_URL|API_URL|SERVER_URL|ENDPOINT|API_BASE|HOST_NAME|ServiceUrl|BaseAddress|ApiEndpoint' -CaseInsensitive

    Write-Section "Credentials"
    Search-Pattern 'password|passwd|pwd|credential|username|login|authenticate' -CaseInsensitive
}

# --- Persistence Mechanisms ---
if ($searchAll -or $Persistence) {
    Write-Section "Registry Run Keys"
    Search-Pattern 'CurrentVersion\\Run|CurrentVersion\\RunOnce|CurrentVersion\\RunServices|CurrentVersion\\Policies\\Explorer\\Run'

    Write-Section "Scheduled Tasks"
    Search-Pattern 'schtasks|ITaskService|ITaskDefinition|TaskScheduler|Register-ScheduledTask|New-ScheduledTask'

    Write-Section "Startup Folder"
    Search-Pattern 'Startup|shell:startup|Programs\\Startup|Environment\.GetFolderPath.*Startup'

    Write-Section "Service Installation"
    Search-Pattern 'CreateService|sc\.exe\s+(create|config)|New-Service|Install-Service|RegisterServiceCtrlHandler'
}

Write-Host ""
Write-Host "=== Search complete ===" -ForegroundColor Green
