const std = @import("std");
const Parser = @import("../Ast/Parser.zig");
const Lexer = @import("../Ast/Lexer.zig");

const c = @import("c");

extern "c" fn zig_Luau_Compiler_compile_ParseResult(*const Parser.ParseResult, *const Lexer.AstNameTable, *usize, ?*c.lua_CompileOptions, ?*anyopaque) ?[*]const u8;
extern "c" fn zig_Luau_Compiler_compile_free(*anyopaque) void;

pub fn compileParseResult(
    allocator: std.mem.Allocator,
    parseResult: *Parser.ParseResult,
    namesTable: *Lexer.AstNameTable,
) error{OutOfMemory}![]const u8 {
    var size: usize = 0;
    const bytes = zig_Luau_Compiler_compile_ParseResult(parseResult, namesTable, &size, null, null) orelse return error.OutOfMemory;
    defer zig_Luau_Compiler_compile_free(@ptrCast(@constCast(bytes)));
    return try allocator.dupe(u8, bytes[0..size]);
}

test compileParseResult {
    const Allocator = @import("../Ast/Allocator.zig").Allocator;

    var allocator = Allocator.init();
    defer allocator.deinit();

    var astNameTable = Lexer.AstNameTable.init(allocator);
    defer astNameTable.deinit();
    const source =
        \\--!test
        \\-- This is a test comment
        \\local x =
        \\
    ;

    var parseResult = Parser.parse(source, astNameTable, allocator);
    defer parseResult.deinit();

    const zig_allocator = std.testing.allocator;
    const bytes = try compileParseResult(zig_allocator, parseResult, astNameTable);
    defer zig_allocator.free(bytes);

    try std.testing.expect(bytes[0] == 0);
    try std.testing.expectEqualStrings(bytes[1..], ":4: Expected identifier when parsing expression, got <eof>");
}
