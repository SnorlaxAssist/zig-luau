#include "Luau/Common.h"
#include "Luau/Lexer.h"
#include "Luau/Frontend.h"

#include <cstdio>
#include <cstdlib>

extern "C" Luau::Lexer* zig_lexer(const char* source, size_t sourceLen) {
    Luau::Allocator alloc;
    Luau::AstNameTable table(alloc);
    return new Luau::Lexer(source, sourceLen, table);
}

extern "C" void zig_lexer_setSkipComments(Luau::Lexer* lexer, bool skip) {
    lexer->setSkipComments(skip);
}


extern "C" void zig_lexer_setReadNames(Luau::Lexer* lexer, bool read) {
    lexer->setReadNames(read);
}

extern "C" const Luau::Lexeme* zig_lexer_next(Luau::Lexer* lexer) {
    return &lexer->next();
}

extern "C" const char* zig_lexeme_toString(Luau::Lexeme* lexeme, size_t* len) {
    std::string str = lexeme->toString();
    *len = str.size();
    return str.c_str();
}
