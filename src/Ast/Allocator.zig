const std = @import("std");

extern "c" fn zig_Luau_Ast_Allocator_new() Allocator.C;
extern "c" fn zig_Luau_Ast_Allocator_free(Allocator.C) void;

pub const Allocator = struct {
    pub const C = *align(8) opaque {};

    pub inline fn init() *Allocator {
        return @ptrCast(zig_Luau_Ast_Allocator_new());
    }

    pub inline fn deinit(self: *Allocator) void {
        zig_Luau_Ast_Allocator_free(self.raw());
    }

    pub inline fn raw(self: *Allocator) C {
        return @ptrCast(@alignCast(self));
    }
};

test Allocator {
    var allocator = Allocator.init();
    defer allocator.deinit();
}
