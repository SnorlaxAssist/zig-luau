#include <Local.h>

#include "Luau/Common.h"

#include "Luau/Ast.h"
#include "Luau/Parser.h"
#include "Luau/Compiler.h"

#include <vector>

#define ZIG_LUAU_AST(name) ZIG_FN(Luau_Ast_##name)

ZIG_EXPORT Luau::ParseResult* ZIG_LUAU_AST(Parser_parse)(const char* source, size_t sourceLen, Luau::AstNameTable* names, Luau::Allocator* allocator)
{
    Luau::ParseOptions parseOptions;
    Luau::ParseResult result = Luau::Parser::parse(source, sourceLen, *names, *allocator, parseOptions);
    return new Luau::ParseResult(result);
}

ZIG_EXPORT void ZIG_LUAU_AST(ParseResult_free)(Luau::ParseResult* value)
{
    delete value;
}

ZIG_EXPORT struct zig_Position
{
    unsigned int line;
    unsigned int column;
};

ZIG_EXPORT struct zig_Location
{
    zig_Position begin;
    zig_Position end;
};

ZIG_EXPORT struct zig_ParseResult_HotComment
{
    bool header;
    zig_Location location;
    const char *content;
    size_t contentLen;
};

ZIG_EXPORT struct zig_ParseResult_HotComments
{
    zig_ParseResult_HotComment *values;
    size_t size;
};

ZIG_EXPORT struct zig_ParseResult_Error
{
    zig_Location location;
    const char *message;
    size_t messageLen;
};

ZIG_EXPORT struct zig_ParseResult_Errors
{
    zig_ParseResult_Error *values;
    size_t size;
};

ZIG_EXPORT zig_ParseResult_HotComments ZIG_LUAU_AST(ParseResult_get_hotcomments)(Luau::ParseResult* value)
{
    size_t size = value->hotcomments.size();
    zig_ParseResult_HotComment *values = new zig_ParseResult_HotComment[size];
    for (size_t i = 0; i < size; i++)
    {
        Luau::HotComment hotcomment = value->hotcomments[i];

        size_t contentLen = hotcomment.content.size();

        char *buffer = new char[contentLen];
        memcpy(buffer, hotcomment.content.c_str(), contentLen);

        values[i] = {
            hotcomment.header,
            {
                {
                    hotcomment.location.begin.line,
                    hotcomment.location.begin.column
                },
                {
                    hotcomment.location.end.line,
                    hotcomment.location.end.column
                },
            },
            buffer,
            contentLen
        };
    }
    return {values, size};
}

ZIG_EXPORT void ZIG_LUAU_AST(ParseResult_free_hotcomments)(zig_ParseResult_HotComments comments)
{
    for (size_t i = 0; i < comments.size; i++)
    {
        zig_ParseResult_HotComment hotcomment = comments.values[i];
        delete[] hotcomment.content;
    }
    delete[] comments.values;
}

ZIG_EXPORT zig_ParseResult_Errors ZIG_LUAU_AST(ParseResult_get_errors)(Luau::ParseResult* value)
{
    size_t size = value->errors.size();
    zig_ParseResult_Error *values = new zig_ParseResult_Error[size];
    for (size_t i = 0; i < size; i++)
    {
        Luau::ParseError error = value->errors[i];

        const std::string message = error.getMessage();
        const Luau::Location location = error.getLocation();

        size_t messageLen = message.size();

        char *buffer = new char[messageLen];
        memcpy(buffer, message.c_str(), messageLen);

        values[i] = {
            {
                {
                    location.begin.line,
                    location.begin.column
                },
                {
                    location.end.line,
                    location.end.column
                },
            },
            buffer,
            messageLen
        };
    }
    return {values, size};
}

ZIG_EXPORT void ZIG_LUAU_AST(ParseResult_free_errors)(zig_ParseResult_Errors errors)
{
    for (size_t i = 0; i < errors.size; i++)
    {
        zig_ParseResult_Error error = errors.values[i];
        delete[] error.message;
    }
    delete[] errors.values;
}

// Code based on https://github.com/luau-lang/luau/blob/8cc289fae430d9b0c22bde209fe5cf2d01751ff1/Compiler/src/Compiler.cpp#L3906
struct FunctionVisitor : Luau::AstVisitor
{
    std::vector<Luau::AstExprFunction*>& functions;
    bool hasTypes = false;
    bool hasNativeFunction = false;

    FunctionVisitor(std::vector<Luau::AstExprFunction*>& functions)
        : functions(functions)
    {
        // preallocate the result; this works around std::vector's inefficient growth policy for small arrays
        functions.reserve(16);
    }

    bool visit(Luau::AstExprFunction* node) override
    {
        node->body->visit(this);

        for (Luau::AstLocal* arg : node->args)
            hasTypes |= arg->annotation != nullptr;

        // this makes sure all functions that are used when compiling this one have been already added to the vector
        functions.push_back(node);

        if (!hasNativeFunction && node->hasNativeAttribute())
            hasNativeFunction = true;

        return false;
    }
};

ZIG_EXPORT bool ZIG_LUAU_AST(ParseResult_hasNativeFunction)(Luau::ParseResult* value)
{
    std::vector<Luau::AstExprFunction*> functions;
    FunctionVisitor functionVisitor(functions);
    value->root->visit(&functionVisitor);
    return functionVisitor.hasNativeFunction;
}