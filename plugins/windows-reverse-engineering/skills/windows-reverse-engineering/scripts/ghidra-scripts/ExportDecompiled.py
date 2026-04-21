# @category Export
# @description Export decompiled C pseudocode, imports, exports, and strings from a Windows PE binary
# @author Windows Reverse Engineering Skill
#
# This Jython script is designed to be run by Ghidra's Headless Analyzer.
# It decompiles all functions to C pseudocode and exports metadata.
#
# Usage via analyzeHeadless:
#   analyzeHeadless.bat <projectDir> <projectName> -import <binary> \
#       -scriptPath <this_dir> -postScript ExportDecompiled.py <outputDir>

import os
import sys
from ghidra.app.decompiler import DecompInterface
from ghidra.util.task import ConsoleTaskMonitor
from ghidra.program.model.symbol import SymbolType

# Get output directory from script arguments or use default
args = getScriptArgs()
if args and len(args) > 0:
    output_dir = args[0]
else:
    # Default: create output next to the analyzed file
    prog_name = currentProgram.getName()
    base_name = prog_name.rsplit('.', 1)[0] if '.' in prog_name else prog_name
    output_dir = os.path.join(os.getcwd(), base_name + "-decompiled")

# Create output subdirectories
decompiled_dir = os.path.join(output_dir, "decompiled")
if not os.path.exists(decompiled_dir):
    os.makedirs(decompiled_dir)

print("=== Ghidra Export Script ===")
print("Program: {}".format(currentProgram.getName()))
print("Output directory: {}".format(output_dir))
print("")

# =====================================================================
# 1. Export decompiled C pseudocode for all functions
# =====================================================================
print("--- Decompiling functions ---")

monitor = ConsoleTaskMonitor()
decomp = DecompInterface()
decomp.openProgram(currentProgram)

# Set decompiler options for better output
options = decomp.getOptions()
# Increase timeout for complex functions (60 seconds)
decomp.setSimplificationStyle("decompile")

fm = currentProgram.getFunctionManager()
functions = fm.getFunctions(True)  # Forward iteration

func_count = 0
error_count = 0
decompiled_count = 0

for func in functions:
    func_count += 1
    func_name = func.getName()
    entry = func.getEntryPoint()

    # Skip thunks and external functions for cleaner output
    if func.isThunk():
        continue

    try:
        results = decomp.decompileFunction(func, 60, monitor)
        if results and results.decompileCompleted():
            decomp_func = results.getDecompiledFunction()
            if decomp_func:
                c_code = decomp_func.getC()
                if c_code:
                    # Sanitize function name for filename
                    safe_name = func_name.replace('<', '_').replace('>', '_').replace(':', '_').replace('*', '_').replace('?', '_').replace('"', '_').replace('/', '_').replace('\\', '_').replace('|', '_')
                    # Add address to avoid name collisions
                    file_name = "{}_{}.c".format(safe_name, entry.toString())
                    file_path = os.path.join(decompiled_dir, file_name)

                    with open(file_path, 'w') as f:
                        f.write("// Function: {}\n".format(func_name))
                        f.write("// Address: {}\n".format(entry.toString()))
                        f.write("// Calling Convention: {}\n".format(func.getCallingConventionName()))
                        f.write("//\n\n")
                        f.write(c_code)

                    decompiled_count += 1
        else:
            error_count += 1
    except Exception as e:
        error_count += 1
        # Continue on error — don't stop for individual function failures

decomp.dispose()

print("Functions found: {}".format(func_count))
print("Functions decompiled: {}".format(decompiled_count))
print("Errors/timeouts: {}".format(error_count))
print("")

# =====================================================================
# 2. Export import table
# =====================================================================
print("--- Exporting imports ---")

imports_path = os.path.join(output_dir, "imports.txt")
import_count = 0

with open(imports_path, 'w') as f:
    f.write("# Import Table for {}\n".format(currentProgram.getName()))
    f.write("# Format: DLL :: FunctionName @ Address\n\n")

    sym_table = currentProgram.getSymbolTable()
    ext_symbols = sym_table.getExternalSymbols()

    current_dll = None
    for sym in ext_symbols:
        if sym.getSymbolType() == SymbolType.FUNCTION:
            parent = sym.getParentNamespace()
            dll_name = parent.getName() if parent else "UNKNOWN"
            func_name = sym.getName()
            addr = sym.getAddress()

            if dll_name != current_dll:
                f.write("\n[{}]\n".format(dll_name))
                current_dll = dll_name

            f.write("  {} @ {}\n".format(func_name, addr.toString()))
            import_count += 1

print("Imports exported: {} functions".format(import_count))
print("")

# =====================================================================
# 3. Export export table (for DLLs)
# =====================================================================
print("--- Exporting exports ---")

exports_path = os.path.join(output_dir, "exports.txt")
export_count = 0

with open(exports_path, 'w') as f:
    f.write("# Export Table for {}\n".format(currentProgram.getName()))
    f.write("# Format: FunctionName @ Address\n\n")

    sym_table = currentProgram.getSymbolTable()
    for sym in sym_table.getAllSymbols(True):
        if sym.isExternalEntryPoint():
            f.write("{} @ {}\n".format(sym.getName(), sym.getAddress().toString()))
            export_count += 1

if export_count == 0:
    with open(exports_path, 'w') as f:
        f.write("# No exports found (this is expected for EXE files)\n")

print("Exports found: {}".format(export_count))
print("")

# =====================================================================
# 4. Export string references
# =====================================================================
print("--- Exporting strings ---")

strings_path = os.path.join(output_dir, "strings.txt")
string_count = 0

with open(strings_path, 'w') as f:
    f.write("# String References for {}\n".format(currentProgram.getName()))
    f.write("# Format: Address | String\n\n")

    listing = currentProgram.getListing()
    data_iter = listing.getDefinedData(True)

    for data in data_iter:
        if monitor.isCancelled():
            break

        data_type = data.getDataType()
        type_name = data_type.getName() if data_type else ""

        if "string" in type_name.lower() or "unicode" in type_name.lower():
            value = data.getValue()
            if value:
                val_str = str(value)
                # Filter out very short or empty strings
                if len(val_str) >= 3:
                    f.write("{} | {}\n".format(data.getAddress().toString(), val_str))
                    string_count += 1

print("Strings exported: {}".format(string_count))
print("")

# =====================================================================
# 5. Export summary
# =====================================================================
print("--- Generating summary ---")

summary_path = os.path.join(output_dir, "summary.txt")

with open(summary_path, 'w') as f:
    f.write("=== Analysis Summary ===\n\n")
    f.write("Program: {}\n".format(currentProgram.getName()))
    f.write("Language: {}\n".format(currentProgram.getLanguage().getLanguageDescription().getDescription()))
    f.write("Compiler: {}\n".format(currentProgram.getCompilerSpec().getCompilerSpecDescription().getCompilerSpecName()))
    f.write("Image Base: {}\n".format(currentProgram.getImageBase().toString()))
    f.write("Min Address: {}\n".format(currentProgram.getMinAddress().toString()))
    f.write("Max Address: {}\n".format(currentProgram.getMaxAddress().toString()))

    f.write("\nFunctions: {}\n".format(func_count))
    f.write("Decompiled: {}\n".format(decompiled_count))
    f.write("Decompile errors: {}\n".format(error_count))
    f.write("Imports: {}\n".format(import_count))
    f.write("Exports: {}\n".format(export_count))
    f.write("Strings: {}\n".format(string_count))

    # List memory blocks / sections
    f.write("\n--- Sections ---\n")
    memory = currentProgram.getMemory()
    for block in memory.getBlocks():
        f.write("  {} | Start: {} | Size: {} | Permissions: {}{}{}\n".format(
            block.getName(),
            block.getStart().toString(),
            block.getSize(),
            "R" if block.isRead() else "-",
            "W" if block.isWrite() else "-",
            "X" if block.isExecute() else "-"
        ))

print("Summary written to {}".format(summary_path))
print("")
print("=== Export complete ===")
print("Output: {}".format(output_dir))
