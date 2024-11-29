const std = @import("std");

extern "c" fn zig_Luau_Ast_Allocator_new() *Allocator;
extern "c" fn zig_Luau_Ast_Allocator_free(*Allocator) void;

pub const Allocator = opaque {
    pub inline fn init() *Allocator {
        return zig_Luau_Ast_Allocator_new();
    }

    pub inline fn deinit(self: *Allocator) void {
        zig_Luau_Ast_Allocator_free(self);
    }
};

test Allocator {
    var allocator = Allocator.init();
    defer allocator.deinit();
}
