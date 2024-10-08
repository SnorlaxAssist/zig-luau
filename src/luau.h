
#ifndef LUAU_HEADERS
#define LUAU_HEADERS

#include "lua.h"
#include "lualib.h"
#include "luacode.h"
#if !defined(__EMSCRIPTEN__) && !defined(__wasm__) && !defined(__wasm32__) && !defined(__wasm64__)
#include "luacodegen.h"
#endif

#endif // LUAU_HEADERS
