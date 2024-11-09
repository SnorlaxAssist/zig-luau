#include "Luau/Parser.h"

extern "C" Luau::ParseResult* zig_Luau_Ast_Parser_parse(const char* source, size_t sourceLen, Luau::AstNameTable* names, Luau::Allocator* allocator)
{
    Luau::ParseOptions parseOptions;
    Luau::ParseResult result = Luau::Parser::parse(source, sourceLen, *names, *allocator, parseOptions);
    return new Luau::ParseResult(result);
}

extern "C" void zig_Luau_Ast_ParseResult_free(Luau::ParseResult* value)
{
    delete value;
}

extern "C" struct zig_Position
{
    unsigned int line;
    unsigned int column;
};

extern "C" struct zig_Location
{
    zig_Position begin;
    zig_Position end;
};

extern "C" struct zig_ParseResult_HotComment
{
    bool header;
    zig_Location location;
    const char *content;
    size_t contentLen;
};

extern "C" struct zig_ParseResult_HotComments
{
    zig_ParseResult_HotComment *values;
    size_t size;
};

extern "C" struct zig_ParseResult_Error
{
    zig_Location location;
    const char *message;
    size_t messageLen;
};

extern "C" struct zig_ParseResult_Errors
{
    zig_ParseResult_Error *values;
    size_t size;
};

extern "C" zig_ParseResult_HotComments zig_Luau_Ast_ParseResult_get_hotcomments(Luau::ParseResult* value)
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

extern "C" void zig_Luau_Ast_ParseResult_free_hotcomments(zig_ParseResult_HotComments comments)
{
    for (size_t i = 0; i < comments.size; i++)
    {
        zig_ParseResult_HotComment hotcomment = comments.values[i];
        delete[] hotcomment.content;
    }
    delete[] comments.values;
}

extern "C" zig_ParseResult_Errors zig_Luau_Ast_ParseResult_get_errors(Luau::ParseResult* value)
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

extern "C" void zig_Luau_Ast_ParseResult_free_errors(zig_ParseResult_Errors errors)
{
    for (size_t i = 0; i < errors.size; i++)
    {
        zig_ParseResult_Error error = errors.values[i];
        delete[] error.message;
    }
    delete[] errors.values;
}