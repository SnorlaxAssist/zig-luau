const std = @import("std");

const Build = std.Build;
const Step = std.Build.Step;

pub fn build(b: *Build) !void {
    // Remove the default install and uninstall steps
    b.top_level_steps = .{};

    const luau_dep = b.lazyDependency("luau", .{}) orelse unreachable;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_4_vector = b.option(bool, "use_4_vector", "Build Luau to use 4-vectors instead of the default 3-vector.") orelse false;

    // Zig module
    const luauModule = b.addModule("zig-luau", .{
        .root_source_file = b.path("src/lib.zig"),
    });

    // Expose build configuration to the zig-luau module
    const config = b.addOptions();
    config.addOption(bool, "use_4_vector", use_4_vector);
    luauModule.addOptions("config", config);

    const vector_size: usize = if (use_4_vector) 4 else 3;
    luauModule.addCMacro("LUA_VECTOR_SIZE", b.fmt("{}", .{vector_size}));

    const lib = try buildLuau(b, target, luau_dep, optimize, use_4_vector);
    b.installArtifact(lib);

    luauModule.addIncludePath(luau_dep.path("Compiler/include"));
    luauModule.addIncludePath(luau_dep.path("VM/include"));
    luauModule.addIncludePath(luau_dep.path("CodeGen/include"));

    luauModule.linkLibrary(lib);

    // Tests
    const tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("luau", luauModule);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run zigluau tests");
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
        if (b.args) |args| run_cmd.addArgs(args);

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

/// Luau has diverged enough from Lua (C++, project structure, ...) that it is easier to separate the build logic
fn buildLuau(b: *Build, target: Build.ResolvedTarget, dependency: *Build.Dependency, optimize: std.builtin.OptimizeMode, use_4_vector: bool) !*Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "luau",
        .target = target,
        .optimize = optimize,
        .version = std.SemanticVersion{ .major = 0, .minor = 634, .patch = 0 },
    });

    for (LUAU_HEADER_DIRS) |dir| {
        lib.addIncludePath(dependency.path(dir));
    }

    const FLAGS = [_][]const u8{
        "-DLUA_USE_LONGJMP=1",
        "-DLUA_API=extern\"C\"",
        "-DLUACODE_API=extern\"C\"",
        "-DLUACODEGEN_API=extern\"C\"",
        if (use_4_vector) "-DLUA_VECTOR_SIZE=4" else "",
    };

    lib.linkLibCpp();
    for (LUAU_SOURCE_FILES) |file| {
        lib.addCSourceFile(.{ .file = dependency.path(file), .flags = &FLAGS });
    }
    lib.addCSourceFile(.{ .file = b.path("src/luau.cpp"), .flags = &FLAGS });

    // It may not be as likely that other software links against Luau, but might as well expose these anyway
    lib.installHeader(dependency.path("VM/include/lua.h"), "lua.h");
    lib.installHeader(dependency.path("VM/include/lualib.h"), "lualib.h");
    lib.installHeader(dependency.path("VM/include/luaconf.h"), "luaconf.h");
    lib.installHeader(dependency.path("CodeGen/include/luacodegen.h"), "luacodegen.h");

    return lib;
}

const LUAU_HEADER_DIRS = [_][]const u8{
    "Common/include/",
    "Ast/include/",
    "Compiler/include/",
    "Compiler/src/",
    "CodeGen/include/",
    "CodeGen/src/",
    "VM/include/",
    "VM/src/",
};

const LUAU_SOURCE_FILES = [_][]const u8{
    // Compiler
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

    // CodeGen
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

    // VM
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
    "VM/src/lvmload.cpp",
    "VM/src/lvmutils.cpp",

    // Ast
    "Ast/src/Ast.cpp",
    "Ast/src/Confusables.cpp",
    "Ast/src/Lexer.cpp",
    "Ast/src/Location.cpp",
    "Ast/src/Parser.cpp",
    "Ast/src/StringUtils.cpp",
    "Ast/src/TimeTrace.cpp",
};
