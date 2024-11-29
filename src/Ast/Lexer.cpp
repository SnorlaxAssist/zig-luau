#include <Local.h>

#include "Luau/Lexer.h"

#define ZIG_LUAU_AST(name) ZIG_FN(Luau_Ast_##name)

ZIG_EXPORT Luau::AstNameTable* ZIG_LUAU_AST(Lexer_AstNameTable_new)(Luau::Allocator* allocator)
{
    return new Luau::AstNameTable(*allocator);
}

ZIG_EXPORT void ZIG_LUAU_AST(Lexer_AstNameTable_free)(Luau::AstNameTable* value)
{
    delete value;
}