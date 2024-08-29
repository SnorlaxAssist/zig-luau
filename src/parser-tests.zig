const std = @import("std");
const analysis = @import("luau_analysis");

test "string_multi" {
    const lexer = analysis.lex("[[some string]]");

    const lexeme = analysis.next(lexer);

    std.debug.print("{s}\n", .{analysis.toString(lexeme)});
}
