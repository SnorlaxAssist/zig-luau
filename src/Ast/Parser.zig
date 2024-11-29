const std = @import("std");

const Allocator = @import("Allocator.zig").Allocator;
const Lexer = @import("Lexer.zig");

const zig_Position = extern struct {
    line: c_uint,
    column: c_uint,
};

const zig_Location = extern struct {
    begin: zig_Position,
    end: zig_Position,
};

const zig_ParseResult_HotComment = extern struct {
    header: c_int,
    location: zig_Location,
    content: [*c]const u8,
    contentLen: usize,
};

const zig_ParseResult_HotComments = extern struct {
    values: [*c]zig_ParseResult_HotComment,
    size: usize,
};

const zig_ParseResult_Error = extern struct {
    location: zig_Location,
    message: [*c]const u8,
    messageLen: usize,
};

const zig_ParseResult_Errors = extern struct {
    values: [*c]zig_ParseResult_Error,
    size: usize,
};

extern "c" fn zig_Luau_Ast_Parser_parse([*]const u8, usize, *Lexer.AstNameTable, *Allocator) *ParseResult;
extern "c" fn zig_Luau_Ast_ParseResult_free(*ParseResult) void;
extern "c" fn zig_Luau_Ast_ParseResult_get_hotcomments(*ParseResult) zig_ParseResult_HotComments;
extern "c" fn zig_Luau_Ast_ParseResult_free_hotcomments(zig_ParseResult_HotComments) void;
extern "c" fn zig_Luau_Ast_ParseResult_get_errors(*ParseResult) zig_ParseResult_Errors;
extern "c" fn zig_Luau_Ast_ParseResult_free_errors(zig_ParseResult_Errors) void;
extern "c" fn zig_Luau_Ast_ParseResult_hasNativeFunction(*ParseResult) bool;
extern "c" fn zig_Luau_Ast_FFlag_LuauNativeAttribute() bool;

pub fn parse(source: []const u8, nameTable: *Lexer.AstNameTable, allocator: *Allocator) *ParseResult {
    return zig_Luau_Ast_Parser_parse(
        source.ptr,
        source.len,
        nameTable,
        allocator,
    );
}

pub fn nativeAttributeEnabled() bool {
    return zig_Luau_Ast_FFlag_LuauNativeAttribute();
}

const ParseResult = opaque {
    pub const HotComment = struct {
        header: bool,
        location: zig_Location,
        content: []const u8,
    };

    pub const HotComments = struct {
        allocator: std.mem.Allocator,
        values: []const HotComment,

        pub fn deinit(self: HotComments) void {
            for (self.values) |value|
                self.allocator.free(value.content);
            self.allocator.free(self.values);
        }
    };

    pub const ParseError = struct {
        location: zig_Location,
        message: []const u8,
    };

    pub const ParseErrors = struct {
        allocator: std.mem.Allocator,
        values: []const ParseError,

        pub fn deinit(self: ParseErrors) void {
            for (self.values) |value|
                self.allocator.free(value.message);
            self.allocator.free(self.values);
        }
    };

    pub inline fn deinit(self: *ParseResult) void {
        zig_Luau_Ast_ParseResult_free(self);
    }

    pub fn getHotcomments(self: *ParseResult, allocator: std.mem.Allocator) !HotComments {
        const hotcomments = zig_Luau_Ast_ParseResult_get_hotcomments(self);
        defer zig_Luau_Ast_ParseResult_free_hotcomments(hotcomments);

        const arr = try allocator.alloc(HotComment, hotcomments.size);
        errdefer allocator.free(arr);
        errdefer for (arr) |comment| allocator.free(comment.content);

        for (0..hotcomments.size) |i| {
            const hotcomment = hotcomments.values[i];
            arr[i] = .{
                .header = hotcomment.header != 0,
                .location = hotcomment.location,
                .content = try allocator.dupe(u8, hotcomment.content[0..hotcomment.contentLen]),
            };
        }

        return .{
            .allocator = allocator,
            .values = arr,
        };
    }

    pub fn getErrors(self: *ParseResult, allocator: std.mem.Allocator) !ParseErrors {
        const errors = zig_Luau_Ast_ParseResult_get_errors(self);
        defer zig_Luau_Ast_ParseResult_free_errors(errors);

        const arr = try allocator.alloc(ParseError, errors.size);
        errdefer allocator.free(arr);
        errdefer for (arr) |comment| allocator.free(comment.message);

        for (0..errors.size) |i| {
            const err = errors.values[i];
            arr[i] = .{
                .location = err.location,
                .message = try allocator.dupe(u8, err.message[0..err.messageLen]),
            };
        }

        return .{
            .allocator = allocator,
            .values = arr,
        };
    }

    pub fn hasNativeFunction(self: *ParseResult) bool {
        return zig_Luau_Ast_ParseResult_hasNativeFunction(self);
    }
};

test ParseResult {
    {
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

        var parseResult = parse(source, astNameTable, allocator);
        defer parseResult.deinit();

        if (nativeAttributeEnabled())
            try std.testing.expect(parseResult.hasNativeFunction() == false);

        {
            const hotcomments = try parseResult.getHotcomments(std.testing.allocator);
            defer hotcomments.deinit();

            try std.testing.expectEqual(1, hotcomments.values.len);
            const first = hotcomments.values[0];
            try std.testing.expectEqualStrings("test", first.content);
            try std.testing.expectEqual(true, first.header);
            try std.testing.expectEqual(0, first.location.begin.line);
            try std.testing.expectEqual(0, first.location.begin.column);
            try std.testing.expectEqual(0, first.location.end.line);
            try std.testing.expectEqual(7, first.location.end.column);
        }

        {
            const errors = try parseResult.getErrors(std.testing.allocator);
            defer errors.deinit();

            try std.testing.expectEqual(1, errors.values.len);
            const first = errors.values[0];
            try std.testing.expectEqualStrings("Expected identifier when parsing expression, got <eof>", first.message);
            try std.testing.expectEqual(3, first.location.begin.line);
            try std.testing.expectEqual(0, first.location.begin.column);
            try std.testing.expectEqual(3, first.location.end.line);
            try std.testing.expectEqual(0, first.location.end.column);
        }
    }
    if (nativeAttributeEnabled()) {
        var allocator = Allocator.init();
        defer allocator.deinit();

        var astNameTable = Lexer.AstNameTable.init(allocator);
        defer astNameTable.deinit();
        const source =
            \\@native
            \\function test()
            \\end
            \\
        ;

        var parseResult = parse(source, astNameTable, allocator);
        defer parseResult.deinit();

        try std.testing.expect(parseResult.hasNativeFunction() == true);
    }
}
