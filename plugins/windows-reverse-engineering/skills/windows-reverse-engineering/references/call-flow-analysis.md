# Call Flow Analysis

Techniques for tracing execution flows in decompiled Windows applications, from entry points down to API calls.

## 1. Start from the PE Import Table

The import table is the single most revealing artifact in static analysis. It lists every DLL and function the binary uses at load time.

### What imports reveal

| Imported DLL | Indicates |
|---|---|
| `ws2_32.dll` | Network communication (sockets) |
| `winhttp.dll` | HTTP/HTTPS requests |
| `wininet.dll` | Internet/HTTP (legacy) |
| `advapi32.dll` | Registry, services, security |
| `crypt32.dll` / `bcrypt.dll` | Cryptography |
| `user32.dll` | GUI, windows, message handling |
| `ole32.dll` / `oleaut32.dll` | COM/OLE automation |
| `mscoree.dll` | .NET runtime (managed binary) |
| `ntdll.dll` (direct) | Low-level / possible evasion |
| `kernel32.dll` | File I/O, process management, memory |

### Extracting imports

```powershell
# Via dumpbin (if Visual Studio C++ Build Tools installed)
dumpbin /imports target.exe

# Via Ghidra (see ExportDecompiled.py output)
# Check <output>/imports.txt

# Via PowerShell (basic PE parsing)
# The decompile.ps1 script includes PE header reading
```

## 2. Entry Points

### Native executables

| Entry Point | Context |
|---|---|
| `WinMain` / `wWinMain` | GUI application |
| `main` / `wmain` | Console application |
| `DllMain` | DLL initialization/cleanup |
| `ServiceMain` | Windows service |
| `DriverEntry` | Kernel driver |
| CRT `mainCRTStartup` | C runtime initialization → calls `main` |

Search in decompiled output:

```powershell
# Find main entry points (Ghidra output)
Select-String -Path "decompiled\*" -Pattern 'WinMain|wWinMain|main\(|DllMain|ServiceMain|DriverEntry' -Recurse

# Find the PE entry point function
Select-String -Path "decompiled\*" -Pattern 'entry|_start|mainCRTStartup' -Recurse
```

### .NET applications

| Entry Point | Context |
|---|---|
| `static void Main()` | Console / WinForms / WPF |
| `Program.cs` | ASP.NET Core / Generic Host |
| `Startup.cs` | ASP.NET Core (older pattern) |
| `App.xaml.cs` | WPF application startup |
| `Global.asax.cs` | ASP.NET Framework |

```powershell
# Find .NET entry points
Select-String -Path "sources\*" -Pattern 'static\s+(void|async\s+Task)\s+Main|class\s+Program|class\s+Startup|class\s+App\s*:' -Recurse
```

## 3. Follow the Initialization Chain

### Native C/C++ application

```
CRT mainCRTStartup()
  → main() / WinMain()
    → Initialize global singletons (COM, Winsock, etc.)
    → Parse command line
    → Create main window (RegisterClassEx → CreateWindowEx)
    → Enter message loop (GetMessage → DispatchMessage)
      → WndProc handles messages
        → WM_COMMAND → menu/button handlers
        → Business logic functions
        → API calls (network, registry, file I/O)
```

Key initialization to search:

```powershell
# COM initialization
Select-String -Path "decompiled\*" -Pattern 'CoInitialize|OleInitialize' -Recurse

# Winsock initialization
Select-String -Path "decompiled\*" -Pattern 'WSAStartup' -Recurse

# Window creation
Select-String -Path "decompiled\*" -Pattern 'CreateWindowEx|RegisterClassEx|RegisterClass\(' -Recurse

# Message loop
Select-String -Path "decompiled\*" -Pattern 'GetMessage|PeekMessage|DispatchMessage|TranslateMessage' -Recurse
```

### .NET application

```
Program.Main()
  → Host.CreateDefaultBuilder()
    → ConfigureServices()
      → Register DI services
      → Configure HttpClient / API clients
      → Configure authentication
    → Configure()
      → Set up middleware pipeline
      → Map routes / endpoints
```

```powershell
# DI registration
Select-String -Path "sources\*" -Pattern 'AddScoped|AddSingleton|AddTransient|AddHttpClient|AddDbContext' -Recurse

# Configuration
Select-String -Path "sources\*" -Pattern 'Configuration\[|GetSection|GetValue|IOptions|appsettings' -Recurse

# Middleware
Select-String -Path "sources\*" -Pattern 'UseAuthentication|UseAuthorization|UseRouting|MapControllers|MapGet|MapPost' -Recurse
```

## 4. Identify User Action Handlers

### Native GUI (Win32)

```
User clicks button
  → WM_COMMAND message sent
  → WndProc receives with LOWORD(wParam) = button ID
  → Switch/if on button IDs
  → Calls handler function
  → Handler calls business logic → API calls
```

```powershell
# Window procedure
Select-String -Path "decompiled\*" -Pattern 'WndProc|WNDPROC|WM_COMMAND|WM_NOTIFY|WM_CREATE' -Recurse

# Dialog procedures
Select-String -Path "decompiled\*" -Pattern 'DialogBox|CreateDialog|DlgProc|DLGPROC|EndDialog' -Recurse

# Common control notifications
Select-String -Path "decompiled\*" -Pattern 'BN_CLICKED|LVN_ITEMCHANGED|TVN_SELCHANGED' -Recurse
```

### WinForms (.NET)

```powershell
# Event handlers
Select-String -Path "sources\*" -Pattern 'Click\s*\+=|_Click\(|button.*Click|EventHandler' -Recurse

# Form lifecycle
Select-String -Path "sources\*" -Pattern 'InitializeComponent|Form_Load|Form_Shown|Form_Closing' -Recurse
```

### WPF (.NET)

```powershell
# Commands and bindings
Select-String -Path "sources\*" -Pattern 'ICommand|RelayCommand|DelegateCommand|Command\s*{' -Recurse

# MVVM ViewModels
Select-String -Path "sources\*" -Pattern 'ViewModel|INotifyPropertyChanged|ObservableCollection|BindingContext' -Recurse
```

## 5. Dependency Injection (.NET)

Modern .NET apps use DI extensively. Trace bindings to find implementations:

```powershell
# Service registration
Select-String -Path "sources\*" -Pattern 'services\.Add(Scoped|Singleton|Transient)\s*<' -Recurse

# HTTP client configuration
Select-String -Path "sources\*" -Pattern 'AddHttpClient|BaseAddress|DefaultRequestHeaders' -Recurse

# Interface → implementation
Select-String -Path "sources\*" -Pattern 'services\.Add.*<I\w+,\s*\w+>' -Recurse

# Constructor injection
Select-String -Path "sources\*" -Pattern 'public\s+\w+\(I\w+' -Recurse
```

To trace a call flow through DI:
1. Find where an interface is used (e.g., `IApiService` in a controller)
2. Find the `AddScoped<IApiService, ApiService>` registration
3. Follow `ApiService` to the actual HTTP/API call

## 6. Find Constants and Configuration

### Native

```powershell
# String constants — often reveal URLs, paths, keys
Select-String -Path "decompiled\*" -Pattern '"https?://|"\\\\|"C:\\' -Recurse

# Error messages — useful for understanding control flow
Select-String -Path "strings.txt" -Pattern 'error|failed|invalid|unauthorized|denied' -CaseSensitive:$false
```

### .NET

```powershell
# Configuration access
Select-String -Path "sources\*" -Pattern 'Configuration\[|ConfigurationManager|AppSettings|ConnectionStrings' -Recurse

# Constants
Select-String -Path "sources\*" -Pattern 'const\s+string|static\s+readonly\s+string|BASE_URL|API_KEY|SECRET' -Recurse

# Resource strings
Select-String -Path "sources\*" -Pattern 'Resources\.\w+|ResourceManager' -Recurse
```

## 7. Navigating Stripped/Obfuscated Code

### Native (no debug symbols)

When symbols are stripped, Ghidra generates names like `FUN_00401000`, `DAT_00405000`:

**What you can still use:**
- **Import table** — DLL function names are always readable
- **String literals** — embedded strings survive stripping
- **API call patterns** — sequences of Win32 calls reveal intent
- **Constants** — magic numbers, sizes, flags are preserved

**Strategy:**
1. Start from imports — find calls to network/registry/crypto APIs
2. Cross-reference callers — Ghidra's output shows who calls what
3. Use strings — grep `strings.txt` for URLs, error messages, paths
4. Rename functions — once you understand a function's purpose, rename it in your analysis notes

### .NET obfuscated

**What gets obfuscated:**
- Class names → `a`, `b`, `\u0001`
- Method names → `a()`, `b()`, `\u0002()`
- Field names → random characters

**What does NOT get obfuscated:**
- **.NET framework types** — `HttpClient`, `FileStream`, `Process` keep their names
- **Method signatures** — parameter types from framework classes are preserved
- **String literals** (unless string encryption is used)
- **NuGet package public APIs** — `Newtonsoft.Json`, `RestSharp` calls are readable
- **Attributes** — `[Serializable]`, `[Route]`, `[HttpGet]` remain

## 8. Tracing a Complete Call Flow: Example

### Example: Finding how an app authenticates

**Native app:**
```
1. dumpbin /imports → finds winhttp.dll imported
2. grep "WinHttpSendRequest" → found in sub_401A00
3. Read sub_401A00 → builds POST request to "/api/auth/login"
4. grep for callers of sub_401A00 → called from sub_401500
5. Read sub_401500 → reads username/password from dialog fields
6. grep for callers of sub_401500 → called from WndProc on WM_COMMAND
7. WM_COMMAND handler checks button ID → "Login" button
```

Result: `Login button → WndProc(WM_COMMAND) → sub_401500 → sub_401A00 → WinHttpSendRequest POST /api/auth/login`

**.NET app:**
```
1. grep for "HttpClient" → found in AuthService.cs
2. Read AuthService.cs → PostAsync("auth/login", credentials)
3. grep for IAuthService usage → injected into LoginViewModel
4. Read LoginViewModel → LoginCommand calls AuthService.LoginAsync()
5. LoginCommand bound to Login button in LoginView.xaml
```

Result: `Login button → LoginViewModel.LoginCommand → AuthService.LoginAsync → HttpClient.PostAsync("auth/login")`

## 9. Tools and Commands Summary

| Goal | Command |
|---|---|
| Find entry points | `Select-String -Path "decompiled\*" -Pattern 'WinMain\|main\|DllMain' -Recurse` |
| Find window procedures | `Select-String -Path "decompiled\*" -Pattern 'WndProc\|WM_COMMAND' -Recurse` |
| Find .NET DI bindings | `Select-String -Path "sources\*" -Pattern 'AddScoped\|AddSingleton\|AddTransient' -Recurse` |
| Find click handlers | `Select-String -Path "sources\*" -Pattern '_Click\|EventHandler\|ICommand' -Recurse` |
| Find constants | `Select-String -Path "sources\*" -Pattern 'const\|BASE_URL\|API_KEY' -CaseSensitive:$false -Recurse` |
| Find usages of a class | `Select-String -Path "sources\*" -Pattern 'ClassName' -Recurse` |
| Find strings containing text | `Select-String -Path "strings.txt" -Pattern '"search text"'` |
| Find network imports | `Select-String -Path "imports.txt" -Pattern 'ws2_32\|winhttp\|wininet'` |
