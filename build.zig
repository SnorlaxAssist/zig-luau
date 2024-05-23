const std = @import("std");

const Build = std.Build;
const Step = std.Build.Step;

const LIB_LUAU = "./lib/Luau/";

pub fn build(b: *Build) !void {
    // Remove the default install and uninstall steps
    b.top_level_steps = .{};

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_4_vector = b.option(bool, "use_4_vector", "Build Luau to use 4-vectors instead of the default 3-vector.") orelse false;

    // Zig module
    const zigluau = b.addModule("zigluau", .{
        .root_source_file = .{ .path = "src/lib.zig" },
    });

    // Expose build configuration to the ziglua module
    const config = b.addOptions();
    config.addOption(bool, "use_4_vector", use_4_vector);
    zigluau.addOptions("config", config);

    const vector_size: usize = if (use_4_vector) 4 else 3;
    zigluau.addCMacro("LUA_VECTOR_SIZE", b.fmt("{}", .{vector_size}));

    const lib = try buildLuau(b, target, optimize, use_4_vector);

    b.installArtifact(lib);

    zigluau.addIncludePath(b.path("lib/Luau/Common/include"));
    zigluau.addIncludePath(b.path("lib/Luau/Compiler/include"));
    zigluau.addIncludePath(b.path("lib/Luau/Ast/include"));
    zigluau.addIncludePath(b.path("lib/Luau/VM/include"));

    zigluau.linkLibrary(lib);

    // Tests
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("zigluau", zigluau);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run zigluau tests");
    test_step.dependOn(&run_tests.step);

    // Examples
    const examples = [_]struct { []const u8, []const u8 }{
        .{ "luau-bytecode", "examples/luau-bytecode.zig" },
    };

    for (examples) |example| {
        const exe = b.addExecutable(.{
            .name = example[0],
            .root_source_file = .{ .path = example[1] },
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("zigluau", zigluau);

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
        .name = "zigluau",
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });
    docs.root_module.addOptions("config", config);
    docs.root_module.addImport("zigluau", zigluau);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Build and install the documentation");
    docs_step.dependOn(&install_docs.step);
}

/// Luau has diverged enough from Lua (C++, project structure, ...) that it is easier to separate the build logic
fn buildLuau(b: *Build, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, use_4_vector: bool) !*Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "luau",
        .target = target,
        .optimize = optimize,
        .version = std.SemanticVersion{ .major = 0, .minor = 625, .patch = 0 },
    });

    for (LUAU_HEADER_DIRS) |dir| {
        lib.addIncludePath(b.path(dir));
    }

    const FLAGS = [_][]const u8{
        "-DLUA_USE_LONGJMP=1",
        "-DLUA_API=extern\"C\"",
        "-DLUACODE_API=extern\"C\"",
        "-DLUACODEGEN_API=extern\"C\"",
        if (use_4_vector) "-DLUA_VECTOR_SIZE=4" else "",
    };

    lib.linkLibCpp();
    lib.addCSourceFiles(.{
        .files = &LUAU_SOURCE_FILES,
        .flags = &FLAGS,
    });
    lib.addCSourceFile(.{ .file = .{ .path = "src/luau.cpp" }, .flags = &FLAGS });

    // It may not be as likely that other software links against Luau, but might as well expose these anyway
    lib.installHeader(b.path(LIB_LUAU ++ "VM/include/lua.h"), "lua.h");
    lib.installHeader(b.path(LIB_LUAU ++ "VM/include/lualib.h"), "lualib.h");
    lib.installHeader(b.path(LIB_LUAU ++ "VM/include/luaconf.h"), "luaconf.h");
    lib.installHeader(b.path(LIB_LUAU ++ "CodeGen/include/luacodegen.h"), "luacodegen.h");

    return lib;
}

const LUAU_HEADER_DIRS = [_][]const u8{
    LIB_LUAU ++ "Common/include/",
    LIB_LUAU ++ "Ast/include/",
    LIB_LUAU ++ "Compiler/include/",
    LIB_LUAU ++ "Compiler/src/",
    LIB_LUAU ++ "CodeGen/include/",
    LIB_LUAU ++ "CodeGen/src/",
    LIB_LUAU ++ "VM/include/",
    LIB_LUAU ++ "VM/src/",
};

const LUAU_SOURCE_FILES = [_][]const u8{
    // Compiler
    LIB_LUAU ++ "Compiler/src/BuiltinFolding.cpp",
    LIB_LUAU ++ "Compiler/src/Builtins.cpp",
    LIB_LUAU ++ "Compiler/src/BytecodeBuilder.cpp",
    LIB_LUAU ++ "Compiler/src/Compiler.cpp",
    LIB_LUAU ++ "Compiler/src/ConstantFolding.cpp",
    LIB_LUAU ++ "Compiler/src/CostModel.cpp",
    LIB_LUAU ++ "Compiler/src/TableShape.cpp",
    LIB_LUAU ++ "Compiler/src/Types.cpp",
    LIB_LUAU ++ "Compiler/src/ValueTracking.cpp",
    LIB_LUAU ++ "Compiler/src/lcode.cpp",

    // CodeGen
    LIB_LUAU ++ "CodeGen/src/AssemblyBuilderA64.cpp",
    LIB_LUAU ++ "CodeGen/src/AssemblyBuilderX64.cpp",
    LIB_LUAU ++ "CodeGen/src/CodeAllocator.cpp",
    LIB_LUAU ++ "CodeGen/src/CodeBlockUnwind.cpp",
    LIB_LUAU ++ "CodeGen/src/CodeGen.cpp",
    LIB_LUAU ++ "CodeGen/src/CodeGenAssembly.cpp",
    LIB_LUAU ++ "CodeGen/src/CodeGenContext.cpp",
    LIB_LUAU ++ "CodeGen/src/CodeGenUtils.cpp",
    LIB_LUAU ++ "CodeGen/src/CodeGenA64.cpp",
    LIB_LUAU ++  "CodeGen/src/CodeGenX64.cpp",
    LIB_LUAU ++ "CodeGen/src/EmitBuiltinsX64.cpp",
    LIB_LUAU ++ "CodeGen/src/EmitCommonX64.cpp",
    LIB_LUAU ++ "CodeGen/src/EmitInstructionX64.cpp",
    LIB_LUAU ++ "CodeGen/src/IrAnalysis.cpp",
    LIB_LUAU ++ "CodeGen/src/IrBuilder.cpp",
    LIB_LUAU ++ "CodeGen/src/IrCallWrapperX64.cpp",
    LIB_LUAU ++ "CodeGen/src/IrDump.cpp",
    LIB_LUAU ++ "CodeGen/src/IrLoweringA64.cpp",
    LIB_LUAU ++ "CodeGen/src/IrLoweringX64.cpp",
    LIB_LUAU ++ "CodeGen/src/IrRegAllocA64.cpp",
    LIB_LUAU ++ "CodeGen/src/IrRegAllocX64.cpp",
    LIB_LUAU ++ "CodeGen/src/IrTranslateBuiltins.cpp",
    LIB_LUAU ++ "CodeGen/src/IrTranslation.cpp",
    LIB_LUAU ++ "CodeGen/src/IrUtils.cpp",
    LIB_LUAU ++ "CodeGen/src/IrValueLocationTracking.cpp",
    LIB_LUAU ++ "CodeGen/src/lcodegen.cpp",
    LIB_LUAU ++ "CodeGen/src/NativeProtoExecData.cpp",
    LIB_LUAU ++ "CodeGen/src/NativeState.cpp",
    LIB_LUAU ++ "CodeGen/src/OptimizeConstProp.cpp",
    LIB_LUAU ++ "CodeGen/src/OptimizeDeadStore.cpp",
    LIB_LUAU ++ "CodeGen/src/OptimizeFinalX64.cpp",
    LIB_LUAU ++ "CodeGen/src/UnwindBuilderDwarf2.cpp",
    LIB_LUAU ++ "CodeGen/src/UnwindBuilderWin.cpp",
    LIB_LUAU ++ "CodeGen/src/BytecodeAnalysis.cpp",
    LIB_LUAU ++ "CodeGen/src/BytecodeSummary.cpp",
    LIB_LUAU ++ "CodeGen/src/SharedCodeAllocator.cpp",

    // VM
    LIB_LUAU ++ "VM/src/lapi.cpp",
    LIB_LUAU ++ "VM/src/laux.cpp",
    LIB_LUAU ++ "VM/src/lbaselib.cpp",
    LIB_LUAU ++ "VM/src/lbitlib.cpp",
    LIB_LUAU ++ "VM/src/lbuffer.cpp",
    LIB_LUAU ++ "VM/src/lbuflib.cpp",
    LIB_LUAU ++ "VM/src/lbuiltins.cpp",
    LIB_LUAU ++ "VM/src/lcorolib.cpp",
    LIB_LUAU ++ "VM/src/ldblib.cpp",
    LIB_LUAU ++ "VM/src/ldebug.cpp",
    LIB_LUAU ++ "VM/src/ldo.cpp",
    LIB_LUAU ++ "VM/src/lfunc.cpp",
    LIB_LUAU ++ "VM/src/lgc.cpp",
    LIB_LUAU ++ "VM/src/lgcdebug.cpp",
    LIB_LUAU ++ "VM/src/linit.cpp",
    LIB_LUAU ++ "VM/src/lmathlib.cpp",
    LIB_LUAU ++ "VM/src/lmem.cpp",
    LIB_LUAU ++ "VM/src/lnumprint.cpp",
    LIB_LUAU ++ "VM/src/lobject.cpp",
    LIB_LUAU ++ "VM/src/loslib.cpp",
    LIB_LUAU ++ "VM/src/lperf.cpp",
    LIB_LUAU ++ "VM/src/lstate.cpp",
    LIB_LUAU ++ "VM/src/lstring.cpp",
    LIB_LUAU ++ "VM/src/lstrlib.cpp",
    LIB_LUAU ++ "VM/src/ltable.cpp",
    LIB_LUAU ++ "VM/src/ltablib.cpp",
    LIB_LUAU ++ "VM/src/ltm.cpp",
    LIB_LUAU ++ "VM/src/ludata.cpp",
    LIB_LUAU ++ "VM/src/lutf8lib.cpp",
    LIB_LUAU ++ "VM/src/lvmexecute.cpp",
    LIB_LUAU ++ "VM/src/lvmload.cpp",
    LIB_LUAU ++ "VM/src/lvmutils.cpp",

    // Ast
    LIB_LUAU ++ "Ast/src/Ast.cpp",
    LIB_LUAU ++ "Ast/src/Confusables.cpp",
    LIB_LUAU ++ "Ast/src/Lexer.cpp",
    LIB_LUAU ++ "Ast/src/Location.cpp",
    LIB_LUAU ++ "Ast/src/Parser.cpp",
    LIB_LUAU ++ "Ast/src/StringUtils.cpp",
    LIB_LUAU ++ "Ast/src/TimeTrace.cpp",
};
