#include <Local.h>

#include "Luau/Allocator.h"

#define ZIG_LUAU_AST(name) ZIG_FN(Luau_Ast_##name)

ZIG_EXPORT Luau::Allocator* ZIG_LUAU_AST(Allocator_new)()
{
    return new Luau::Allocator();
}

ZIG_EXPORT void ZIG_LUAU_AST(Allocator_free)(Luau::Allocator* value)
{
    delete value;
}