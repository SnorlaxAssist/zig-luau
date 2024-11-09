const std = @import("std");

const Build = std.Build;
const Step = std.Build.Step;

const LUAU_VERSION = std.SemanticVersion{ .major = 0, .minor = 651, .patch = 0 };
const VERSION_HASH = "1220bcd384152421ac7bfd492b3398c5d36a6699a64de431e817e0555f0df69f16e4";

pub fn build(b: *Build) !void {
    // Remove the default install and uninstall steps
    b.top_level_steps = .{};

    const luau_dep = b.lazyDependency("luau", .{}) orelse unreachable;

    std.debug.assert(std.mem.eql(u8, luau_dep.builder.pkg_hash, VERSION_HASH));

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_4_vector = b.option(bool, "use_4_vector", "Build Luau to use 4-vectors instead of the default 3-vector.") orelse false;

    // Expose build configuration to the zig-luau module
    const config = b.addOptions();
    config.addOption(bool, "use_4_vector", use_4_vector);
    config.addOption(std.SemanticVersion, "luau_version", LUAU_VERSION);

    // Luau C Headers
    const headers = b.addTranslateC(.{
        .root_source_file = b.path("src/luau.h"),
        .target = target,
        .optimize = optimize,
    });
    headers.addIncludePath(luau_dep.path("Compiler/include"));
    headers.addIncludePath(luau_dep.path("VM/include"));
    if (!target.result.isWasm())
        headers.addIncludePath(luau_dep.path("CodeGen/include"));

    const c_module = headers.createModule();

    const lib = try buildLuau(b, target, luau_dep, optimize, use_4_vector);
    b.installArtifact(lib);

    // Zig module
    const luauModule = b.addModule("zig-luau", .{
        .root_source_file = b.path("src/lib.zig"),
    });

    try buildAndLinkModule(b, target, luau_dep, luauModule, config, c_module, lib, use_4_vector);

    // Tests
    const lib_tests = b.addTest(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    try buildAndLinkModule(b, target, luau_dep, &lib_tests.root_module, config, c_module, lib, use_4_vector);

    // Tests
    const tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("luau", luauModule);

    const run_lib_tests = b.addRunArtifact(lib_tests);
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run zig-luau tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_tests.step);

    // Examples
    const examples = [_]struct { []const u8, []const u8 }{
        .{ "luau-bytecode", "examples/luau-bytecode.zig" },
        .{ "repl", "examples/repl.zig" },
        .{ "zig-fn", "examples/zig-fn.zig" },
    };

    for (examples) |example| {
        const exe = b.addExecutable(.{
            .name = example[0],
            .root_source_file = b.path(example[1]),
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("luau", luauModule);

        const artifact = b.addInstallArtifact(exe, .{});
        const exe_step = b.step(b.fmt("install-example-{s}", .{example[0]}), b.fmt("Install {s} example", .{example[0]}));
        exe_step.dependOn(&artifact.step);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args|
            run_cmd.addArgs(args);

        const run_step = b.step(b.fmt("run-example-{s}", .{example[0]}), b.fmt("Run {s} example", .{example[0]}));
        run_step.dependOn(&run_cmd.step);
    }

    const docs = b.addStaticLibrary(.{
        .name = "zig-luau",
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    docs.root_module.addOptions("config", config);
    docs.root_module.addImport("luau", luauModule);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Build and install the documentation");
    docs_step.dependOn(&install_docs.step);
}

fn buildAndLinkModule(
    b: *Build,
    target: Build.ResolvedTarget,
    dependency: *Build.Dependency,
    module: anytype,
    config: *Step.Options,
    c_module: *Build.Module,
    lib: *Step.Compile,
    use_4_vector: bool,
) !void {
    module.addImport("c", c_module);

    module.addOptions("config", config);

    const vector_size: usize = if (use_4_vector) 4 else 3;
    module.addCMacro("LUA_VECTOR_SIZE", b.fmt("{}", .{vector_size}));

    module.addIncludePath(dependency.path("Compiler/include"));
    module.addIncludePath(dependency.path("VM/include"));
    if (!target.result.isWasm())
        module.addIncludePath(dependency.path("CodeGen/include"));

    module.linkLibrary(lib);
}

/// Luau has diverged enough from Lua (C++, project structure, ...) that it is easier to separate the build logic
fn buildLuau(
    b: *Build,
    target: Build.ResolvedTarget,
    dependency: *Build.Dependency,
    optimize: std.builtin.OptimizeMode,
    use_4_vector: bool,
) !*Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "luau",
        .target = target,
        .optimize = optimize,
        .version = LUAU_VERSION,
    });

    for (LUAU_Ast_HEADERS_DIRS) |dir|
        lib.addIncludePath(dependency.path(dir));
    for (LUAU_Common_HEADERS_DIRS) |dir|
        lib.addIncludePath(dependency.path(dir));
    for (LUAU_Compiler_HEADERS_DIRS) |dir|
        lib.addIncludePath(dependency.path(dir));
    // CodeGen is not supported on WASM
    if (!target.result.isWasm())
        for (LUAU_CodeGen_HEADERS_DIRS) |dir|
            lib.addIncludePath(dependency.path(dir));
    for (LUAU_VM_HEADERS_DIRS) |dir|
        lib.addIncludePath(dependency.path(dir));

    const FLAGS = [_][]const u8{
        // setjmp.h compile error in Wasm
        "-DLUA_USE_LONGJMP=" ++ if (!target.result.isWasm()) "1" else "0",
        "-DLUA_API=extern\"C\"",
        "-DLUACODE_API=extern\"C\"",
        "-DLUACODEGEN_API=extern\"C\"",
        if (use_4_vector) "-DLUA_VECTOR_SIZE=4" else "",
    };

    lib.linkLibCpp();

    for (LUAU_Ast_SOURCE_FILES) |file|
        lib.addCSourceFile(.{ .file = dependency.path(file), .flags = &FLAGS });
    for (LUAU_Compiler_SOURCE_FILES) |file|
        lib.addCSourceFile(.{ .file = dependency.path(file), .flags = &FLAGS });
    // CodeGen is not supported on WASM
    if (!target.result.isWasm())
        for (LUAU_CodeGen_SOURCE_FILES) |file|
            lib.addCSourceFile(.{ .file = dependency.path(file), .flags = &FLAGS });
    for (LUAU_VM_SOURCE_FILES) |file|
        lib.addCSourceFile(.{ .file = dependency.path(file), .flags = &FLAGS });

    lib.addCSourceFile(.{ .file = b.path("src/luau.cpp"), .flags = &FLAGS });

    // Modules
    lib.addCSourceFile(.{ .file = b.path("src/Ast/Allocator.cpp"), .flags = &FLAGS });
    lib.addCSourceFile(.{ .file = b.path("src/Ast/Lexer.cpp"), .flags = &FLAGS });
    lib.addCSourceFile(.{ .file = b.path("src/Ast/Parser.cpp"), .flags = &FLAGS });

    // It may not be as likely that other software links against Luau, but might as well expose these anyway
    lib.installHeader(dependency.path("VM/include/lua.h"), "lua.h");
    lib.installHeader(dependency.path("VM/include/lualib.h"), "lualib.h");
    lib.installHeader(dependency.path("VM/include/luaconf.h"), "luaconf.h");
    if (!target.result.isWasm())
        lib.installHeader(dependency.path("CodeGen/include/luacodegen.h"), "luacodegen.h");

    return lib;
}

const LUAU_Ast_HEADERS_DIRS = [_][]const u8{
    "Ast/include/",
};
const LUAU_Ast_SOURCE_FILES = [_][]const u8{
    "Ast/src/Ast.cpp",
    "Ast/src/Allocator.cpp",
    "Ast/src/Confusables.cpp",
    "Ast/src/Lexer.cpp",
    "Ast/src/Location.cpp",
    "Ast/src/Parser.cpp",
    "Ast/src/StringUtils.cpp",
    "Ast/src/TimeTrace.cpp",
};

const LUAU_Common_HEADERS_DIRS = [_][]const u8{
    "Common/include/",
};

const LUAU_Compiler_HEADERS_DIRS = [_][]const u8{
    "Compiler/include/",
    "Compiler/src/",
};
const LUAU_Compiler_SOURCE_FILES = [_][]const u8{
    "Compiler/src/BuiltinFolding.cpp",
    "Compiler/src/Builtins.cpp",
    "Compiler/src/BytecodeBuilder.cpp",
    "Compiler/src/Compiler.cpp",
    "Compiler/src/ConstantFolding.cpp",
    "Compiler/src/CostModel.cpp",
    "Compiler/src/TableShape.cpp",
    "Compiler/src/Types.cpp",
    "Compiler/src/ValueTracking.cpp",
    "Compiler/src/lcode.cpp",
};

const LUAU_CodeGen_HEADERS_DIRS = [_][]const u8{
    "CodeGen/include/",
    "CodeGen/src/",
};
const LUAU_CodeGen_SOURCE_FILES = [_][]const u8{
    "CodeGen/src/AssemblyBuilderA64.cpp",
    "CodeGen/src/AssemblyBuilderX64.cpp",
    "CodeGen/src/CodeAllocator.cpp",
    "CodeGen/src/CodeBlockUnwind.cpp",
    "CodeGen/src/CodeGen.cpp",
    "CodeGen/src/CodeGenAssembly.cpp",
    "CodeGen/src/CodeGenContext.cpp",
    "CodeGen/src/CodeGenUtils.cpp",
    "CodeGen/src/CodeGenA64.cpp",
    "CodeGen/src/CodeGenX64.cpp",
    "CodeGen/src/EmitBuiltinsX64.cpp",
    "CodeGen/src/EmitCommonX64.cpp",
    "CodeGen/src/EmitInstructionX64.cpp",
    "CodeGen/src/IrAnalysis.cpp",
    "CodeGen/src/IrBuilder.cpp",
    "CodeGen/src/IrCallWrapperX64.cpp",
    "CodeGen/src/IrDump.cpp",
    "CodeGen/src/IrLoweringA64.cpp",
    "CodeGen/src/IrLoweringX64.cpp",
    "CodeGen/src/IrRegAllocA64.cpp",
    "CodeGen/src/IrRegAllocX64.cpp",
    "CodeGen/src/IrTranslateBuiltins.cpp",
    "CodeGen/src/IrTranslation.cpp",
    "CodeGen/src/IrUtils.cpp",
    "CodeGen/src/IrValueLocationTracking.cpp",
    "CodeGen/src/lcodegen.cpp",
    "CodeGen/src/NativeProtoExecData.cpp",
    "CodeGen/src/NativeState.cpp",
    "CodeGen/src/OptimizeConstProp.cpp",
    "CodeGen/src/OptimizeDeadStore.cpp",
    "CodeGen/src/OptimizeFinalX64.cpp",
    "CodeGen/src/UnwindBuilderDwarf2.cpp",
    "CodeGen/src/UnwindBuilderWin.cpp",
    "CodeGen/src/BytecodeAnalysis.cpp",
    "CodeGen/src/BytecodeSummary.cpp",
    "CodeGen/src/SharedCodeAllocator.cpp",
};

const LUAU_VM_HEADERS_DIRS = [_][]const u8{
    "VM/include/",
    "VM/src/",
};

const LUAU_VM_SOURCE_FILES = [_][]const u8{
    "VM/src/lapi.cpp",
    "VM/src/laux.cpp",
    "VM/src/lbaselib.cpp",
    "VM/src/lbitlib.cpp",
    "VM/src/lbuffer.cpp",
    "VM/src/lbuflib.cpp",
    "VM/src/lbuiltins.cpp",
    "VM/src/lcorolib.cpp",
    "VM/src/ldblib.cpp",
    "VM/src/ldebug.cpp",
    "VM/src/ldo.cpp",
    "VM/src/lfunc.cpp",
    "VM/src/lgc.cpp",
    "VM/src/lgcdebug.cpp",
    "VM/src/linit.cpp",
    "VM/src/lmathlib.cpp",
    "VM/src/lmem.cpp",
    "VM/src/lnumprint.cpp",
    "VM/src/lobject.cpp",
    "VM/src/loslib.cpp",
    "VM/src/lperf.cpp",
    "VM/src/lstate.cpp",
    "VM/src/lstring.cpp",
    "VM/src/lstrlib.cpp",
    "VM/src/ltable.cpp",
    "VM/src/ltablib.cpp",
    "VM/src/ltm.cpp",
    "VM/src/ludata.cpp",
    "VM/src/lutf8lib.cpp",
    "VM/src/lvmexecute.cpp",
    "VM/src/lveclib.cpp",
    "VM/src/lvmload.cpp",
    "VM/src/lvmutils.cpp",
};
