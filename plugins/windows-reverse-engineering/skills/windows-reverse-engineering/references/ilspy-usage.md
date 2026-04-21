# ilspycmd CLI Reference

## Overview

`ilspycmd` is the command-line interface for ILSpy, the open-source .NET assembly decompiler. It decompiles .NET assemblies (EXE, DLL) to C# source code, including full project reconstruction with `.csproj` files.

## Installation

```powershell
# Requires .NET SDK 6.0+
dotnet tool install -g ilspycmd

# Update to latest
dotnet tool update -g ilspycmd
```

## When to Use ilspycmd vs Ghidra

| Scenario | Recommended |
|---|---|
| .NET Framework (4.x) assembly | ilspycmd |
| .NET Core / .NET 5+ assembly | ilspycmd |
| .NET assembly with WPF/WinForms | ilspycmd |
| Native C/C++ EXE/DLL | Ghidra |
| Mixed-mode assembly (native + managed) | Both — Ghidra for native, ilspycmd for managed |
| Obfuscated .NET (Dotfuscator, ConfuserEx) | de4dot first, then ilspycmd |
| .NET Native / AOT compiled | Ghidra (compiled to native code) |

## Basic Usage

```powershell
ilspycmd [OPTIONS] <assembly>
```

Input can be an `.exe` or `.dll` file containing .NET metadata.

## Key Options

| Option | Description |
|---|---|
| `-p` / `--project` | Decompile to a full C# project (with .csproj file) |
| `-o <dir>` | Output directory for decompiled files |
| `-t <type>` | Decompile a specific type (e.g., `MyApp.MainForm`) |
| `-l` / `--list` | List all types and members in the assembly |
| `--no-dead-code` | Remove unreachable code from output |
| `-r <dir>` | Reference assembly search directory (improves type resolution) |
| `--nested-directories` | Create nested directories matching namespace structure |
| `-lv <version>` | Set the target language version (e.g., `CSharp10_0`) |

## Decompiling Different Targets

### Full project decompilation (recommended)

```powershell
ilspycmd -p -o output_dir MyApp.exe
```

Produces:
- `output_dir/*.cs` — Decompiled C# source files
- `output_dir/*.csproj` — Reconstructed project file
- `output_dir/Properties/` — Assembly info and resources

### Decompile to individual files

```powershell
ilspycmd -o output_dir MyApp.dll
```

Produces C# files without a project structure.

### List all types

```powershell
ilspycmd -l MyApp.exe
```

Useful for identifying namespaces and classes before targeted decompilation.

### Decompile a specific type

```powershell
ilspycmd -t "MyApp.Services.AuthService" MyApp.exe
```

### Decompile with reference resolution

```powershell
ilspycmd -p -o output_dir -r "C:\refs\" MyApp.exe
```

When the assembly references other DLLs, put them in a directory and use `-r` for better type resolution.

## Handling Obfuscated .NET

.NET obfuscators (Dotfuscator, ConfuserEx, Eziriz .NET Reactor, etc.) rename types and members, encrypt strings, add control flow obfuscation, and may add anti-tamper checks.

### Preprocessing with de4dot

```powershell
# Clean the obfuscated assembly first
de4dot ObfuscatedApp.exe -o CleanApp.exe

# Then decompile the cleaned version
ilspycmd -p -o output_dir CleanApp.exe
```

### What de4dot handles
- Renamed types/methods → restored to readable names
- Encrypted strings → decrypted inline
- Proxy delegates → resolved to direct calls
- Dead code from obfuscation → removed

### What remains obfuscated
- Control flow patterns (may still be convoluted)
- Custom protection schemes de4dot doesn't recognize
- Native stub protectors (e.g., .NET Reactor with native mode)

### Manual strategies for obfuscated .NET
1. **String search**: string literals in resources and constants are often preserved
2. **Framework types**: `HttpClient`, `WebRequest`, `SqlConnection` keep their names
3. **Interface names**: public interface names are often preserved for serialization
4. **Attribute values**: `[Route]`, `[HttpGet]`, `[Serializable]` annotations remain readable

## Common Patterns in Decompiled Output

### Dependency Injection (ASP.NET Core)

Look in `Startup.cs` or `Program.cs`:
```csharp
services.AddHttpClient<IApiService, ApiService>(client => {
    client.BaseAddress = new Uri("https://api.example.com/v1/");
});
services.AddScoped<IAuthService, AuthService>();
```

### HTTP Clients

```csharp
// HttpClient (modern)
var response = await httpClient.PostAsync("/auth/login", content);

// WebRequest (legacy)
var request = WebRequest.Create("https://api.example.com/data");

// RestSharp
var request = new RestRequest("/users/{id}", Method.Get);
```

### Configuration

```csharp
// appsettings.json values
var apiUrl = Configuration["ApiSettings:BaseUrl"];
var apiKey = Configuration.GetSection("ApiKeys")["Primary"];
```

## Output Structure

When using `-p` (project mode), the output mirrors the original project:

```
output_dir/
├── MyApp.csproj           # Reconstructed project file
├── Program.cs             # Entry point
├── Properties/
│   └── AssemblyInfo.cs    # Assembly metadata
├── Models/
│   ├── User.cs
│   └── LoginRequest.cs
├── Services/
│   ├── AuthService.cs
│   └── ApiService.cs
└── ...
```

## Troubleshooting

| Problem | Solution |
|---|---|
| `ilspycmd: command not found` | Run `dotnet tool install -g ilspycmd` and restart terminal |
| Assembly references not resolved | Use `-r <dir>` to point to referenced DLLs |
| Output has `/* Error */` comments | Assembly may be obfuscated — try de4dot first |
| `BadImageFormatException` | File is not a .NET assembly — use Ghidra instead |
| `FileNotFoundException` for deps | Copy dependency DLLs next to the target assembly |
| Decompiled code won't compile | Expected — decompiled code is for reading, not building |
