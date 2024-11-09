#include "Luau/Allocator.h"

extern "C" Luau::Allocator* zig_Luau_Ast_Allocator_new()
{
    return new Luau::Allocator();
}

extern "C" void zig_Luau_Ast_Allocator_free(Luau::Allocator* value)
{
    delete value;
}