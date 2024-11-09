const Allocator = @import("Allocator.zig").Allocator;

extern "c" fn zig_Luau_Ast_Lexer_AstNameTable_new(Allocator.C) AstNameTable.C;
extern "c" fn zig_Luau_Ast_Lexer_AstNameTable_free(AstNameTable.C) void;

pub const AstNameTable = struct {
    pub const C = *align(8) opaque {};

    pub inline fn init(LuauAllocator: *Allocator) *AstNameTable {
        return @ptrCast(zig_Luau_Ast_Lexer_AstNameTable_new(LuauAllocator.raw()));
    }

    pub inline fn deinit(self: *AstNameTable) void {
        zig_Luau_Ast_Lexer_AstNameTable_free(self.raw());
    }

    pub inline fn raw(self: *AstNameTable) C {
        return @ptrCast(@alignCast(self));
    }
};

test AstNameTable {
    var allocator = Allocator.init();
    defer allocator.deinit();

    var astNameTable = AstNameTable.init(allocator);
    defer astNameTable.deinit();
}
