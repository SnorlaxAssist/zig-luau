const Allocator = @import("Allocator.zig").Allocator;

extern "c" fn zig_Luau_Ast_Lexer_AstNameTable_new(*Allocator) *AstNameTable;
extern "c" fn zig_Luau_Ast_Lexer_AstNameTable_free(*AstNameTable) void;

pub const AstNameTable = opaque {
    pub inline fn init(LuauAllocator: *Allocator) *AstNameTable {
        return zig_Luau_Ast_Lexer_AstNameTable_new(LuauAllocator);
    }

    pub inline fn deinit(self: *AstNameTable) void {
        zig_Luau_Ast_Lexer_AstNameTable_free(self);
    }
};

test AstNameTable {
    var allocator = Allocator.init();
    defer allocator.deinit();

    var astNameTable = AstNameTable.init(allocator);
    defer astNameTable.deinit();
}
