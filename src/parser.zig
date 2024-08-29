extern "c" fn zig_lexer([*]const u8, usize) *Lexer;
extern "c" fn zig_lexer_setSkipComments(*Lexer, bool) void;
extern "c" fn zig_lexer_setReadNames(*Lexer, bool) void;
extern "c" fn zig_lexer_next(*Lexer) *Lexeme;

extern "c" fn zig_lexeme_toString(*Lexeme, *usize) [*]const u8;

const Lexer = opaque {};
const Lexeme = opaque {};

// TODO: improve c++ binds functions
// TODO: to methods

pub fn lex(source: []const u8) *Lexer {
    return zig_lexer(source.ptr, source.len);
}

pub fn setSkipComments(lexer: *Lexer, skip: bool) void {
    zig_lexer_setSkipComments(lexer, skip);
}

pub fn setReadNames(lexer: *Lexer, read: bool) void {
    zig_lexer_setReadNames(lexer, read);
}

pub fn next(lexer: *Lexer) *Lexeme {
    return zig_lexer_next(lexer);
}

pub fn toString(lexeme: *Lexeme) []const u8 {
    var len: usize = 0;
    const ptr = zig_lexeme_toString(lexeme, &len);
    return ptr[0..len];
}
