#include "Luau/Lexer.h"

extern "C" Luau::AstNameTable* zig_Luau_Ast_Lexer_AstNameTable_new(Luau::Allocator* allocator)
{
    return new Luau::AstNameTable(*allocator);
}

extern "C" void zig_Luau_Ast_Lexer_AstNameTable_free(Luau::AstNameTable* value)
{
    delete value;
}