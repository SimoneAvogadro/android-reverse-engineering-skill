# API Extraction Patterns

Patterns and Select-String commands for finding API calls, network endpoints, and secrets in decompiled Windows source code. Works on both Ghidra C pseudocode output and ILSpy C# output.

## Network — Win32 API (Native)

### WinHTTP

```powershell
# WinHTTP functions
Select-String -Path "sources\*" -Pattern 'WinHttpOpen|WinHttpConnect|WinHttpOpenRequest|WinHttpSendRequest|WinHttpReceiveResponse|WinHttpReadData|WinHttpSetOption' -Recurse

# WinHTTP URL construction
Select-String -Path "sources\*" -Pattern 'WinHttpCrackUrl|WinHttpCreateUrl' -Recurse
```

### WinINet

```powershell
# WinINet functions
Select-String -Path "sources\*" -Pattern 'InternetOpen|InternetConnect|HttpOpenRequest|HttpSendRequest|InternetReadFile|InternetCloseHandle|InternetSetOption' -Recurse

# FTP via WinINet
Select-String -Path "sources\*" -Pattern 'FtpOpenFile|FtpGetFile|FtpPutFile|FtpFindFirstFile' -Recurse
```

### Winsock

```powershell
# Socket operations
Select-String -Path "sources\*" -Pattern 'WSAStartup|socket\(|connect\(|send\(|recv\(|bind\(|listen\(|accept\(|closesocket|getaddrinfo|gethostbyname' -Recurse

# Higher-level winsock
Select-String -Path "sources\*" -Pattern 'WSASocket|WSASend|WSARecv|WSAConnect|WSAAsyncSelect' -Recurse
```

## Network — .NET

### HttpClient (modern)

```powershell
# HttpClient usage
Select-String -Path "sources\*" -Pattern 'HttpClient|GetAsync|PostAsync|PutAsync|DeleteAsync|SendAsync|GetStringAsync|GetStreamAsync' -Recurse

# HttpClientFactory
Select-String -Path "sources\*" -Pattern 'IHttpClientFactory|AddHttpClient|CreateClient' -Recurse

# Request construction
Select-String -Path "sources\*" -Pattern 'HttpRequestMessage|StringContent|JsonContent|FormUrlEncodedContent|MultipartFormDataContent' -Recurse
```

### WebRequest (legacy)

```powershell
Select-String -Path "sources\*" -Pattern 'WebRequest|HttpWebRequest|WebClient|DownloadString|DownloadFile|UploadString|UploadFile' -Recurse
```

### RestSharp / Refit

```powershell
Select-String -Path "sources\*" -Pattern 'RestClient|RestRequest|RestResponse|IRestClient' -Recurse
Select-String -Path "sources\*" -Pattern '\[Get\(|Post\(|Put\(|Delete\(|Patch\(' -Recurse
```

## Registry Operations

### Native

```powershell
Select-String -Path "sources\*" -Pattern 'RegOpenKey|RegCreateKey|RegSetValue|RegQueryValue|RegDeleteKey|RegDeleteValue|RegEnumKey|RegEnumValue|RegCloseKey|RegNotifyChangeKeyValue' -Recurse
```

### .NET

```powershell
Select-String -Path "sources\*" -Pattern 'Microsoft\.Win32\.Registry|RegistryKey|OpenSubKey|SetValue|GetValue|CreateSubKey|DeleteSubKey' -Recurse
```

## File System Operations

### Native

```powershell
Select-String -Path "sources\*" -Pattern 'CreateFile[AW]?|ReadFile|WriteFile|DeleteFile[AW]?|CopyFile[AW]?|MoveFile[AW]?|FindFirstFile[AW]?|FindNextFile[AW]?|GetFileAttributes|SetFileAttributes|CreateDirectory[AW]?' -Recurse
```

### .NET

```powershell
Select-String -Path "sources\*" -Pattern 'File\.(Read|Write|Append|Copy|Move|Delete|Exists|Open|Create)|Directory\.(Create|Delete|Exists|GetFiles|GetDirectories)|FileStream|StreamReader|StreamWriter|BinaryReader|BinaryWriter' -Recurse
```

## Process and Thread Manipulation

```powershell
# Process creation
Select-String -Path "sources\*" -Pattern 'CreateProcess[AW]?|ShellExecute[AW]?|WinExec|system\(' -Recurse

# Process injection indicators
Select-String -Path "sources\*" -Pattern 'VirtualAlloc|VirtualAllocEx|VirtualProtect|WriteProcessMemory|ReadProcessMemory|CreateRemoteThread|NtCreateThreadEx|QueueUserAPC|SetThreadContext' -Recurse

# DLL injection
Select-String -Path "sources\*" -Pattern 'LoadLibrary[AW]?|GetProcAddress|FreeLibrary|GetModuleHandle[AW]?' -Recurse

# .NET process
Select-String -Path "sources\*" -Pattern 'Process\.Start|ProcessStartInfo|Process\.GetProcesses' -Recurse
```

## Cryptography

### Native (CryptoAPI / BCrypt)

```powershell
Select-String -Path "sources\*" -Pattern 'CryptAcquireContext|CryptEncrypt|CryptDecrypt|CryptHashData|CryptDeriveKey|CryptGenKey|CryptImportKey|CryptExportKey|CryptGenRandom' -Recurse
Select-String -Path "sources\*" -Pattern 'BCryptOpenAlgorithmProvider|BCryptEncrypt|BCryptDecrypt|BCryptGenerateSymmetricKey|BCryptHash|BCryptCreateHash|BCryptFinishHash' -Recurse
```

### .NET

```powershell
Select-String -Path "sources\*" -Pattern 'System\.Security\.Cryptography|Aes\.|RSA\.|SHA256|SHA512|MD5|HMAC|RijndaelManaged|AesManaged|RSACryptoServiceProvider|X509Certificate' -Recurse
```

## COM and WMI

```powershell
# COM
Select-String -Path "sources\*" -Pattern 'CoCreateInstance|CoInitialize|CoUninitialize|IDispatch|IUnknown|CLSIDFromProgID|ProgIDFromCLSID' -Recurse

# WMI (native)
Select-String -Path "sources\*" -Pattern 'IWbemLocator|IWbemServices|ConnectServer|ExecQuery' -Recurse

# WMI (.NET)
Select-String -Path "sources\*" -Pattern 'ManagementObjectSearcher|ManagementObject|ManagementScope|ObjectQuery|WqlObjectQuery|SelectQuery' -Recurse
```

## Windows Services

```powershell
# Native
Select-String -Path "sources\*" -Pattern 'OpenSCManager|CreateService[AW]?|OpenService[AW]?|StartService|ControlService|DeleteService|ChangeServiceConfig|QueryServiceStatus|RegisterServiceCtrlHandler' -Recurse

# .NET
Select-String -Path "sources\*" -Pattern 'ServiceBase|ServiceController|ServiceInstaller|ServiceProcessInstaller|OnStart|OnStop|ServiceName' -Recurse
```

## Persistence Mechanisms

```powershell
# Run keys
Select-String -Path "sources\*" -Pattern 'SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run|SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\RunOnce' -Recurse

# Scheduled tasks
Select-String -Path "sources\*" -Pattern 'schtasks|ITaskService|ITaskDefinition|TaskScheduler|ScheduledTask' -Recurse

# Startup folder
Select-String -Path "sources\*" -Pattern 'Startup|shell:startup|Programs\\Startup' -Recurse

# Windows service registration
Select-String -Path "sources\*" -Pattern 'CreateService|sc\.exe|New-Service|Install-Service' -Recurse
```

## Hardcoded URLs, IPs, and Secrets

```powershell
# HTTP/HTTPS URLs
Select-String -Path "sources\*" -Pattern '"https?://[^"]+' -Recurse

# IP addresses
Select-String -Path "sources\*" -Pattern '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b' -Recurse

# API keys and tokens
Select-String -Path "sources\*" -Pattern 'api[_\-]?key|api[_\-]?secret|auth[_\-]?token|bearer|access[_\-]?token|client[_\-]?secret|app[_\-]?secret' -CaseSensitive:$false -Recurse

# Base URL constants
Select-String -Path "sources\*" -Pattern 'BASE_URL|API_URL|SERVER_URL|ENDPOINT|API_BASE|HOST_NAME|ServiceUrl|BaseAddress' -CaseSensitive:$false -Recurse

# Connection strings
Select-String -Path "sources\*" -Pattern 'Data Source=|Server=|Initial Catalog=|connectionString|ConnectionStrings' -Recurse

# Passwords
Select-String -Path "sources\*" -Pattern 'password|passwd|pwd|credential' -CaseSensitive:$false -Recurse
```

## Documentation Template

For each discovered API call, document it using this template:

### Win32 API Template

```markdown
### `FunctionName` (DLL: source.dll)

- **Source**: `filename.c:42` or `Namespace.ClassName` (file:line)
- **Category**: Network / Registry / File I/O / Process / Crypto / COM / Service
- **Parameters**:
  - `param1`: value or source description
  - `param2`: value or source description
- **Return handling**: checked / ignored / stored in `variable`
- **Called from**: `Main → InitNetwork → SendData → WinHttpSendRequest`
- **Purpose**: Brief description of what this call accomplishes
```

### Network Endpoint Template

```markdown
### `METHOD https://api.example.com/v1/endpoint`

- **Source**: `NetworkManager.cs:87` or `sub_401234.c:15`
- **Method**: GET / POST / PUT / DELETE
- **Transport**: HttpClient / WinHTTP / WinINet / Winsock
- **Headers**:
  - `Authorization: Bearer <token>`
  - `Content-Type: application/json`
- **Request body**: `{ "username": "string", "password": "string" }`
- **Response handling**: parsed as JSON / written to file / displayed in UI
- **Called from**: `LoginForm.btnLogin_Click → AuthService.Login → HttpClient.PostAsync`
```

## Search Strategy

1. Start with **import table analysis** — see what DLLs the binary imports (ws2_32.dll = networking, advapi32.dll = registry/services, etc.)
2. Search for **hardcoded URLs and IPs** — find where the app communicates externally
3. Search for **HTTP client construction** — HttpClient, WinHTTP, WinINet setup reveals base URLs and auth config
4. Check for **authentication patterns** — tokens, credentials, API keys
5. Look for **persistence mechanisms** — registry Run keys, scheduled tasks, services
6. Search for **crypto operations** — may reveal how data is encrypted/decrypted before transmission
7. Check for **process manipulation** — indicates potential injection or privilege escalation
