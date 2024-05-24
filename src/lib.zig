const std = @import("std");

const c = @cImport({
    @cInclude("lua.h");
    @cInclude("lualib.h");

    @cInclude("luacode.h");
    @cInclude("luacodegen.h");
});

const config = @import("config");

/// The length of Luau vector values, either 3 or 4.
pub const luau_vector_size = if (config.use_4_vector) 4 else 3;

/// This function is defined in luau.cpp and must be called to define the assertion printer
extern "c" fn zig_registerAssertionHandler() void;

/// This function is defined in luau.cpp and ensures Zig uses the correct free when compiling luau code
extern "c" fn zig_luau_free(ptr: *anyopaque) void;

const Allocator = std.mem.Allocator;

// Types
//
// Luau constants and types are declared below in alphabetical order
// For constants that have a logical grouping (like Operators), Zig enums are used for type safety

/// The type of function that Luau uses for all internal allocations and frees
/// `data` is an opaque pointer to any data (the allocator), `ptr` is a pointer to the block being alloced/realloced/freed
/// `osize` is the original size or a code, and `nsize` is the new size
///
pub const AllocFn = *const fn (data: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) callconv(.C) ?*anyopaque;

/// Type for C functions
pub const CFn = *const fn (state: ?*LuaState) callconv(.C) c_int;
pub const ZigFn = *const fn (state: *Luau) i32;

/// Type for C userdata destructors
pub const CUserdataDtorFn = *const fn (userdata: *anyopaque) callconv(.C) void;
pub const ZigUserdataDtorFn = *const fn (data: *anyopaque) void;

/// Type for C useratom callback
pub const CUserAtomCallbackFn = *const fn (str: [*c]const u8, len: usize) callconv(.C) i16;


/// The internal Luau debug structure
const Debug = c.lua_Debug;

pub const DebugInfo = struct {
    source: [:0]const u8 = undefined,
    src_len: usize = 0,
    short_src: [c.LUA_IDSIZE:0]u8 = undefined,

    name: ?[:0]const u8 = undefined,
    what: FnType = undefined,

    current_line: ?i32 = null,
    first_line_defined: ?i32 = null,

    is_vararg: bool = false,

    pub const NameType = enum { global, local, method, field, upvalue, other };

    pub const FnType = enum { luau, c, main, tail };

    pub const Options = packed struct {
        f: bool = false,
        l: bool = false,
        n: bool = false,
        s: bool = false,
        u: bool = false,
        L: bool = false,

        fn toString(options: Options) [10:0]u8 {
            var str = [_:0]u8{0} ** 10;
            var index: u8 = 0;

            inline for (std.meta.fields(Options)) |field| {
                if (@field(options, field.name)) {
                    str[index] = field.name[0];
                    index += 1;
                }
            }
            while (index < str.len) : (index += 1) str[index] = 0;

            return str;
        }
    };
};

/// The superset of all errors returned from ziglua
pub const Error = error{
    /// A generic failure (used when a function can only fail in one way)
    Fail,
    /// A runtime error
    Runtime,
    /// A syntax error during precompilation
    Syntax,
    /// A memory allocation error
    Memory,
    /// An error while running the message handler
    MsgHandler,
    /// A file-releated error
    File,
};

/// Type for arrays of functions to be registered
pub const FnReg = struct {
    name: [:0]const u8,
    func: ?CFn,
};

/// The index of the global environment table
pub const GLOBALSINDEX = c.LUA_GLOBALSINDEX;
/// Index of the regsitry in the stack (pseudo-index)
pub const REGISTRYINDEX = c.LUA_REGISTRYINDEX;

/// Type for debugging hook functions
// pub const CHookFn = *const fn (state: ?*LuaState, ar: ?*Debug) callconv(.C) void;

// /// Hook event codes
// pub const Hook = c.lua_Hook;

/// Type of integers in Luau (typically an i64)
pub const Integer = c.lua_Integer;

/// Type for continuation-function contexts (usually isize)
pub const Context = isize;

/// Type for continuation functions
// pub const CContFn = *const fn (state: ?*LuaState, status: c_int, ctx: Context) callconv(.C) c_int;

pub const Libs = packed struct {
    base: bool = false,
    package: bool = false,
    string: bool = false,
    utf8: bool = false,
    table: bool = false,
    math: bool = false,
    io: bool = false,
    os: bool = false,
    bit32: bool = false,
    buffer: bool = false,
};

/// The type of the opaque structure that points to a thread and the state of a Luau interpreter
pub const LuaState = c.lua_State;

/// Luau types
/// Must be a signed integer because LuaType.none is -1
pub const LuaType = enum(i5) {
    none = c.LUA_TNONE,
    nil = c.LUA_TNIL,
    boolean = c.LUA_TBOOLEAN,
    light_userdata = c.LUA_TLIGHTUSERDATA,
    number = c.LUA_TNUMBER,
    vector = c.LUA_TVECTOR,
    string = c.LUA_TSTRING,
    table = c.LUA_TTABLE,
    function = c.LUA_TFUNCTION,
    userdata = c.LUA_TUSERDATA,
    thread = c.LUA_TTHREAD,
    buffer = c.LUA_TBUFFER,
};

/// Modes used for `Luau.load()`
pub const Mode = enum(u2) { binary, text, binary_text };

/// The minimum Luau stack available to a function
pub const MINSTACK = c.LUA_MINSTACK;

/// Option for multiple returns in `Luau.protectedCall()` and `Luau.call()`
pub const MULTRET = c.LUA_MULTRET;

/// Type of floats in Luau (typically an f64)
pub const Number = c.lua_Number;

/// The type of the reader function used by `Luau.load()`
// pub const CReaderFn = *const fn (state: ?*LuaState, data: ?*anyopaque, size: [*c]usize) callconv(.C) [*c]const u8;

/// The possible status of a call to `Luau.resumeThread`
pub const ResumeStatus = enum(u1) {
    ok = StatusCode.ok,
    yield = StatusCode.yield,
};

/// Reference constants
pub const ref_nil = c.LUA_REFNIL;
pub const ref_no = c.LUA_NOREF;

/// Status that a thread can be in
/// Usually errors are reported by a Zig error rather than a status enum value
pub const Status = enum(u3) {
    ok = StatusCode.ok,
    yield = StatusCode.yield,
    err_runtime = StatusCode.err_runtime,
    err_syntax = StatusCode.err_syntax,
    err_memory = StatusCode.err_memory,
    err_error = StatusCode.err_error,
};

/// Status codes
/// Not public, because typically Status.ok is returned from a function implicitly;
/// Any function that returns an error usually returns a Zig error, and a void return
/// is an implicit Status.ok.
/// In the rare case that the status code is required from a function, an enum is
/// used for that specific function's return type
/// TODO: see where this is used and check if a null can be used instead
const StatusCode = struct {
    pub const ok = c.LUA_OK;
    pub const yield = c.LUA_YIELD;
    pub const err_runtime = c.LUA_ERRRUN;
    pub const err_syntax = c.LUA_ERRSYNTAX;
    pub const err_memory = c.LUA_ERRMEM;
    pub const err_error = c.LUA_ERRERR;

    pub const err_gcmm = unreachable;
};

/// The unsigned version of Integer
pub const Unsigned = c.lua_Unsigned;

/// The type of warning functions used by Luau to emit warnings
// pub const CWarnFn = @compileError("CWarnFn not defined");

/// The type of the writer function used by `Luau.dump()`
// pub const CWriterFn = *const fn (state: ?*LuaState, buf: ?*const anyopaque, size: usize, data: ?*anyopaque) callconv(.C) c_int;

/// For bundling a parsed value with an arena allocator
/// Copied from std.json.Parsed
pub fn Parsed(comptime T: type) type {
    return struct {
        arena: *std.heap.ArenaAllocator,
        value: T,

        pub fn deinit(self: @This()) void {
            const allocator = self.arena.child_allocator;
            self.arena.deinit();
            allocator.destroy(self.arena);
        }
    };
}

pub const CodeGen = struct {
    pub fn Supported() bool {
        return c.luau_codegen_supported() == 1;
    }

    pub fn Create(luau : *Luau) void {
        c.luau_codegen_create(zConverter.LuauToState(luau));
    }

    pub fn Compile(luau : *Luau, idx : i32) void {
        c.luau_codegen_compile(zConverter.LuauToState(luau), @intCast(idx));
    }
};

pub const zNative = c;
pub const zConverter = struct {
    pub fn LuauToState(luau : *Luau) *LuaState {
        return @ptrCast(luau);
    }
    pub fn StateToLuau(state : *LuaState) *Luau {
        return @ptrCast(state);
    }
};

/// A Zig wrapper around the Luau C API
/// Represents a Luau state or thread and contains the entire state of the Luau interpreter
pub const Luau = struct {
    const alignment = @alignOf(std.c.max_align_t);

    /// Allows Luau to allocate memory using a Zig allocator passed in via data.
    fn alloc(data: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) callconv(.C) ?*align(alignment) anyopaque {
        // just like malloc() returns a pointer "which is suitably aligned for any built-in type",
        // the memory allocated by this function should also be aligned for any type that Lua may
        // desire to allocate. use the largest alignment for the target
        const allocator_ptr: *Allocator = @ptrCast(@alignCast(data.?));

        if (@as(?[*]align(alignment) u8, @ptrCast(@alignCast(ptr)))) |prev_ptr| {
            const prev_slice = prev_ptr[0..osize];

            // when nsize is zero the allocator must behave like free and return null
            if (nsize == 0) {
                allocator_ptr.free(prev_slice);
                return null;
            }

            // when nsize is not zero the allocator must behave like realloc
            const new_ptr = allocator_ptr.realloc(prev_slice, nsize) catch return null;
            return new_ptr.ptr;
        } else if (nsize == 0) {
            return null;
        } else {
            // ptr is null, allocate a new block of memory
            const new_ptr = allocator_ptr.alignedAlloc(u8, alignment, nsize) catch return null;
            return new_ptr.ptr;
        }
    }

    /// Initialize a Luau state with the given allocator
    pub fn init(allocator_ptr: *const Allocator) !*Luau {
        zig_registerAssertionHandler();

        // @constCast() is safe here because Lua does not mutate the pointer internally
        if (c.lua_newstate(alloc, @constCast(allocator_ptr))) |state| {
            return @ptrCast(state);
        } else return error.Memory;
    }

    /// Deinitialize a Luau state and free all memory
    pub fn deinit(luau: *Luau) void {
        luau.close();
    }

    pub fn allocator(luau: *Luau) Allocator {
        var data: ?*Allocator = undefined;
        _ = luau.getAllocFn(@ptrCast(&data));

        if (data) |allocator_ptr| {
            // Although the Allocator is passed to Lua as a pointer, return a
            // copy to make use more convenient.
            return allocator_ptr.*;
        }

        @panic("Lua.allocator() invalid on Lua states created without a Zig allocator");
    }

    pub fn absIndex(luau: *Luau, index: i32) i32 {
        return c.lua_absindex(@ptrCast(luau), index);
    }

    /// Calls a function (or any callable value)
    /// First push the function to be called onto the stack. Then push any arguments onto the stack.
    /// Then call this function. All arguments and the function value are popped, and any results
    /// are pushed onto the stack.
    pub fn call(luau: *Luau, num_args: i32, num_results: i32) void {
        c.lua_call(@ptrCast(luau), num_args, num_results);
    }

    /// Ensures that the stack has space for at least n extra arguments
    /// Returns an error if more stack space cannot be allocated
    /// Never shrinks the stack
    pub fn checkStack(luau: *Luau, n: i32) !void {
        if (c.lua_checkstack(@ptrCast(luau), n) == 0) return error.Fail;
    }

    /// Release all Luau objects in the state and free all dynamic memory
    pub fn close(luau: *Luau) void {
        c.lua_close(@ptrCast(luau));
    }

    /// Concatenates the n values at the top of the stack, pops them, and leaves the result at the top
    /// If the number of values is 1, the result is a single value on the stack (nothing changes)
    /// If the number of values is 0, the result is the empty string
    pub fn concat(luau: *Luau, n: i32) void {
        c.lua_concat(@ptrCast(luau), n);
    }

    /// Creates a new empty table and pushes onto the stack
    /// num_arr is a hint for how many elements the table will have as a sequence
    /// num_rec is a hint for how many other elements the table will have
    /// Luau may preallocate memory for the table based on the hints
    pub fn createTable(luau: *Luau, num_arr: i32, num_rec: i32) void {
        c.lua_createtable(@ptrCast(luau), num_arr, num_rec);
    }

    /// Returns true if the two values at the indexes are equal following the semantics of the
    /// Luau == operator.
    pub fn equal(luau: *Luau, index1: i32, index2: i32) bool {
        return c.lua_equal(@ptrCast(luau), index1, index2) == 1;
    }

    /// Raises a Luau error using the value at the top of the stack as the error object
    /// Does a longjump and therefore never returns
    pub fn raiseError(luau: *Luau) noreturn {
        _ = c.lua_error(@ptrCast(luau));
        unreachable;
    }

    /// Perform a full garbage-collection cycle
    pub fn gcCollect(luau: *Luau) void {
        _ = c.lua_gc(@ptrCast(luau), c.LUA_GCCOLLECT, 0);
    }

    /// Stops the garbage collector
    pub fn gcStop(luau: *Luau) void {
        _ = c.lua_gc(@ptrCast(luau), c.LUA_GCSTOP, 0);
    }

    /// Restarts the garbage collector
    pub fn gcRestart(luau: *Luau) void {
        _ = c.lua_gc(@ptrCast(luau), c.LUA_GCRESTART, 0);
    }

    /// Performs an incremental step of garbage collection corresponding to the allocation of step_size Kbytes
    pub fn gcStep(luau: *Luau) void {
        _ = c.lua_gc(@ptrCast(luau), c.LUA_GCSTEP, 0);
    }

    /// Returns the current amount of memory (in Kbytes) in use by Luau
    pub fn gcCount(luau: *Luau) i32 {
        return c.lua_gc(@ptrCast(luau), c.LUA_GCCOUNT, 0);
    }

    /// Returns the remainder of dividing the current amount of bytes of memory in use by Luau by 1024
    pub fn gcCountB(luau: *Luau) i32 {
        return c.lua_gc(@ptrCast(luau), c.LUA_GCCOUNTB, 0);
    }

    /// Sets `multiplier` as the new value for the step multiplier of the collector
    /// Returns the previous value of the step multiplier
    pub fn gcSetStepMul(luau: *Luau, multiplier: i32) i32 {
        return c.lua_gc(@ptrCast(luau), c.LUA_GCSETSTEPMUL, multiplier);
    }

    pub fn gcIsRunning(luau: *Luau) bool {
        return c.lua_gc(@ptrCast(luau), c.LUA_GCISRUNNING, 0) == 1;
    }

    pub fn gcSetGoal(luau: *Luau, goal: i32) i32 {
        return c.lua_gc(@ptrCast(luau), c.LUA_GCSETGOAL, goal);
    }

    pub fn gcSetStepSize(luau: *Luau, size: i32) i32 {
        return c.lua_gc(@ptrCast(luau), c.LUA_GCSETSTEPSIZE, size);
    }

    pub fn newUserdataDtor(luau: *Luau, comptime T: type, dtor_fn: ZigUserdataDtorFn) *T {
        // safe to .? because this function throws a Lua error on out of memory
        // so the returned pointer should never be null
        const ptr = c.lua_newuserdatadtor(@ptrCast(luau), @sizeOf(T), @ptrCast(dtor_fn)).?;
        return @ptrCast(@alignCast(ptr));
    }

    pub fn setUserdataDtor(luau: *Luau, tag: c_int, dtor: c.lua_Destructor) void {
        c.lua_setuserdatadtor(@ptrCast(luau), tag, dtor);
    }

    pub fn setUserdataTag(luau: *Luau, idx: c_int, tag: c_int) void {
        c.lua_setuserdatatag(@ptrCast(luau), idx, tag);
    }

    pub fn getUserdataDtor(luau: *Luau, tag: c_int) c.lua_Destructor {
        return c.lua_getuserdatadtor(@ptrCast(luau), tag);
    }

    pub fn getLightUserdataName(luau: *Luau, tag: c_int) ![*:0]const u8 {
        if (c.lua_getlightuserdataname(@ptrCast(luau), tag)) |name| return name;
        return error.Fail;
    }

    pub fn setLightUserdataName(luau: *Luau, tag: c_int, name: [:0]const u8) void {
        c.lua_setlightuserdataname(@ptrCast(luau), tag, name.ptr);
    }
    /// Returns the memory allocation function of a given state
    /// If data is not null, it is set to the opaque pointer given when the allocator function was set
    pub fn getAllocFn(luau: *Luau, data: ?**anyopaque) AllocFn {
        // Assert cannot be null because it is impossible (and not useful) to pass null
        // to the functions that set the allocator (setallocf and newstate)
        return c.lua_getallocf(@ptrCast(luau), @ptrCast(data)).?;
    }

    /// Pushes onto the stack the environment table of the value at the given index.
    pub fn getFenv(luau: *Luau, index: i32) void {
        c.lua_getfenv(@ptrCast(luau), index);
    }

    /// Pushes onto the stack the value t[key] where t is the value at the given index
    pub fn getField(luau: *Luau, index: i32, key: [:0]const u8) LuaType {
        return @enumFromInt(c.lua_getfield(@ptrCast(luau), index, key.ptr));
    }

    /// Pushes onto the stack the value of the global name
    pub fn getGlobal(luau: *Luau, name: [:0]const u8) !LuaType {
        const lua_type: LuaType = @enumFromInt(c.lua_getglobal(zConverter.LuauToState(luau), name.ptr));
        if (lua_type == .nil) return error.Fail;
        return lua_type;
    }

    /// If the value at the given index has a metatable, the function pushes that metatable onto the stack
    /// Otherwise an error is returned
    pub fn getMetatable(luau: *Luau, index: i32) !void {
        if (c.lua_getmetatable(@ptrCast(luau), index) == 0) return error.Fail;
    }

    /// Pushes onto the stack the value t[k] where t is the value at the given index and k is the value on the top of the stack
    pub fn getTable(luau: *Luau, index: i32) LuaType {
        return @enumFromInt(c.lua_gettable(@ptrCast(luau), index));
    }

    /// Returns the index of the top element in the stack
    /// Because indices start at 1, the result is also equal to the number of elements in the stack
    pub fn getTop(luau: *Luau) i32 {
        return c.lua_gettop(@ptrCast(luau));
    }

    /// Moves the top element into the given valid `index` shifting up any elements to make room
    pub fn insert(luau: *Luau, index: i32) void {
        // translate-c cannot translate this macro correctly
        c.lua_insert(@ptrCast(luau), index);
    }

    /// Returns true if the value at the given index is a boolean
    pub fn isBoolean(luau: *Luau, index: i32) bool {
        return c.lua_isboolean(zConverter.LuauToState(luau), index);
    }

    /// Returns true if the value at the given index is a CFn
    pub fn isCFunction(luau: *Luau, index: i32) bool {
        return c.lua_iscfunction(@ptrCast(luau), index) != 0;
    }

    /// Returns true if the value at the given index is a function (C or Luau)
    pub fn isFunction(luau: *Luau, index: i32) bool {
        return c.lua_isfunction(zConverter.LuauToState(luau), index);
    }

    /// Returns true if the value at the given index is a light userdata
    pub fn isLightUserdata(luau: *Luau, index: i32) bool {
        return c.lua_islightuserdata(zConverter.LuauToState(luau), index);
    }

    /// Returns true if the value at the given index is nil
    pub fn isNil(luau: *Luau, index: i32) bool {
        return c.lua_isnil(zConverter.LuauToState(luau), index);
    }

    /// Returns true if the given index is not valid
    pub fn isNone(luau: *Luau, index: i32) bool {
        return c.lua_isnone(zConverter.LuauToState(luau), index);
    }

    /// Returns true if the given index is not valid or if the value at the index is nil
    pub fn isNoneOrNil(luau: *Luau, index: i32) bool {
        return c.lua_isnoneornil(zConverter.LuauToState(luau), index);
    }

    /// Returns true if the value at the given index is a number
    pub fn isNumber(luau: *Luau, index: i32) bool {
        return c.lua_isnumber(@ptrCast(luau), index) != 0;
    }

    /// Returns true if the value at the given index is a string
    pub fn isString(luau: *Luau, index: i32) bool {
        return c.lua_isstring(@ptrCast(luau), index) != 0;
    }

    /// Returns true if the value at the given index is a table
    pub fn isTable(luau: *Luau, index: i32) bool {
        return c.lua_istable(zConverter.LuauToState(luau), index);
    }

    /// Returns true if the value at the given index is a thread
    pub fn isThread(luau: *Luau, index: i32) bool {
        return c.lua_isthread(zConverter.LuauToState(luau), index);
    }

    /// Returns true if the value at the given index is a userdata (full or light)
    pub fn isUserdata(luau: *Luau, index: i32) bool {
        return c.lua_isuserdata(@ptrCast(luau), index) != 0;
    }

    /// Returns true if the value at index1 is smaller than the value at index2, following the
    /// semantics of the Luau < operator.
    pub fn lessThan(luau: *Luau, index1: i32, index2: i32) bool {
        return c.lua_lessthan(@ptrCast(luau), index1, index2) == 1;
    }

    /// Creates a new independent state and returns its main thread
    pub fn newState(alloc_fn: AllocFn, data: ?*const anyopaque) !*Luau {
        zig_registerAssertionHandler();

        if (c.lua_newstate(alloc_fn, @constCast(data))) |state| {
            return @ptrCast(state);
        } else return error.Memory;
    }

    /// Creates a new empty table and pushes it onto the stack
    /// Equivalent to createTable(0, 0)
    pub fn newTable(luau: *Luau) void {
        c.lua_newtable(zConverter.LuauToState(luau));
    }

    /// Creates a new thread, pushes it on the stack, and returns a Luau state that represents the new thread
    /// The new thread shares the global environment but has a separate execution stack
    pub fn newThread(luau: *Luau) *Luau {
        return @ptrCast(c.lua_newthread(@ptrCast(luau)).?);
    }

    /// This function allocates a new userdata of the given type.
    /// Returns a pointer to the Luau-owned data
    pub fn newUserdata(luau: *Luau, comptime T: type) *T {
        // safe to .? because this function throws a Luau error on out of memory
        // so the returned pointer should never be null
        const ptr = c.lua_newuserdata(zConverter.LuauToState(luau), @sizeOf(T)).?;
        return opaqueCast(T, ptr);
    }

    /// This function creates and pushes a slice of full userdata onto the stack.
    /// Returns a slice to the Luau-owned data.
    pub fn newUserdataSlice(luau: *Luau, comptime T: type, size: usize) []T {
        // safe to .? because this function throws a Luau error on out of memory
        const ptr = c.lua_newuserdata(zConverter.LuauToState(luau), @sizeOf(T) * size).?;
        return @as([*]T, @ptrCast(@alignCast(ptr)))[0..size];
    }

    /// Pops a key from the stack, and pushes a key-value pair from the table at the given index.
    pub fn next(luau: *Luau, index: i32) bool {
        return c.lua_next(@ptrCast(luau), index) != 0;
    }

    /// Returns the length of the value at the given index
    pub fn objLen(luau: *Luau, index: i32) i32 {
        return c.lua_objlen(@ptrCast(luau), index);
    }

    /// Calls a function (or callable object) in protected mode
    pub fn pcall(luau: *Luau, num_args: i32, num_results: i32, err_func: i32) !void {
        // The translate-c version of lua_pcall does not type-check so we must rewrite it
        // (macros don't always translate well with translate-c)
        const ret = c.lua_pcall(@ptrCast(luau), num_args, num_results, err_func);
        switch (ret) {
            StatusCode.ok => return,
            StatusCode.err_runtime => return error.Runtime,
            StatusCode.err_memory => return error.Memory,
            StatusCode.err_error => return error.MsgHandler,
            else => unreachable,
        }
    }

    /// Pops `n` elements from the top of the stack
    pub fn pop(luau: *Luau, n: i32) void {
        luau.setTop(-n - 1);
    }

    /// Pushes a boolean value with value `b` onto the stack
    pub fn pushBoolean(luau: *Luau, b: bool) void {
        c.lua_pushboolean(@ptrCast(luau), @intFromBool(b));
    }

    /// Pushes a new Closure onto the stack
    /// `n` tells how many upvalues this function will have
    pub fn pushClosure(luau: *Luau, c_fn: CFn, name: [:0]const u8, n: i32) void {
        c.lua_pushcclosurek(@ptrCast(luau), c_fn, name, n, null);
    }

    /// Pushes a function onto the stack.
    /// Equivalent to pushClosure with no upvalues
    pub fn pushFunction(luau: *Luau, comptime zig_fn: ZigFn, name: [:0]const u8) void {
        luau.pushClosure(toCFn(zig_fn), name, 0);
    }
    pub fn pushCFunction(luau: *Luau, c_fn: CFn, name: [:0]const u8) void {
        luau.pushClosure(c_fn, name, 0);
    }

    /// Push a formatted string onto the stack and return a pointer to the string
    pub fn pushFString(luau: *Luau, fmt: [:0]const u8, args: anytype) [*:0]const u8 {
        return @call(.auto, c.lua_pushfstringL, .{ zConverter.LuauToState(luau), fmt.ptr } ++ args);
    }

    /// Pushes an integer with value `n` onto the stack
    pub fn pushInteger(luau: *Luau, n: Integer) void {
        c.lua_pushinteger(@ptrCast(luau), n);
    }

    /// Pushes a light userdata onto the stack
    pub fn pushLightUserdata(luau: *Luau, ptr: *anyopaque) void {
        c.lua_pushlightuserdata(zConverter.LuauToState(luau), ptr);
    }

    /// Pushes the bytes onto the stack
    pub fn pushLString(luau: *Luau, bytes: []const u8) void {
        c.lua_pushlstring(@ptrCast(luau), bytes.ptr, bytes.len);
    }

    /// Pushes a nil value onto the stack
    pub fn pushNil(luau: *Luau) void {
        c.lua_pushnil(@ptrCast(luau));
    }

    /// Pushes a float with value `n` onto the stack
    pub fn pushNumber(luau: *Luau, n: Number) void {
        c.lua_pushnumber(@ptrCast(luau), n);
    }

    /// Pushes a zero-terminated string onto the stack
    /// Luau makes a copy of the string so `str` may be freed immediately after return
    pub fn pushString(luau: *Luau, str: [:0]const u8) void {
        c.lua_pushstring(@ptrCast(luau), str.ptr);
    }

    /// Pushes this thread onto the stack
    /// Returns true if this thread is the main thread of its state
    pub fn pushThread(luau: *Luau) bool {
        return c.lua_pushthread(@ptrCast(luau)) != 0;
    }

    /// Pushes a copy of the element at the given index onto the stack
    pub fn pushValue(luau: *Luau, index: i32) void {
        c.lua_pushvalue(@ptrCast(luau), index);
    }

    /// Returns true if the two values in indices `index1` and `index2` are primitively equal
    /// Bypasses __eq metamethods
    /// Returns false if not equal, or if any index is invalid
    pub fn rawEqual(luau: *Luau, index1: i32, index2: i32) bool {
        return c.lua_rawequal(@ptrCast(luau), index1, index2) != 0;
    }

    /// Similar to `Luau.getTable()` but does a raw access (without metamethods)
    pub fn rawGetTable(luau: *Luau, index: i32) LuaType {
        return @enumFromInt(c.lua_rawget(@ptrCast(luau), index));
    }

    /// Pushes onto the stack the value t[n], where `t` is the table at the given `index`
    /// Returns the `LuaType` of the pushed value
    pub fn rawGetIndex(luau: *Luau, index: i32, n: i32) LuaType {
        return @enumFromInt(c.lua_rawgeti(@ptrCast(luau), index, n));
    }

    /// Similar to `Luau.setTable()` but does a raw assignment (without metamethods)
    pub fn rawSetTable(luau: *Luau, index: i32) void {
        c.lua_rawset(@ptrCast(luau), index);
    }

    /// Does the equivalent of t[`i`] = v where t is the table at the given `index`
    /// and v is the value at the top of the stack
    /// Pops the value from the stack. Does not use __newindex metavalue
    pub fn rawSetIndex(luau: *Luau, index: i32, i: i32) void {
        c.lua_rawseti(@ptrCast(luau), index, i);
    }

    /// Sets the C function f as the new value of global name
    pub fn register(luau: *Luau, name: [:0]const u8, comptime zig_fn: ZigFn) void {
        // translate-c failure
        luau.pushFunction(zig_fn, name);
        luau.setGlobal(name);
    }

    /// Removes the element at the given valid `index` shifting down elements to fill the gap
    pub fn remove(luau: *Luau, index: i32) void {
        c.lua_remove(@ptrCast(luau), index);
    }

    /// Moves the top element into the given valid `index` without shifting any elements,
    /// then pops the top element
    pub fn replace(luau: *Luau, index: i32) void {
        c.lua_replace(@ptrCast(luau), index);
    }

    /// Starts and resumes a coroutine in the thread
   pub fn resumeThread(luau: *Luau, from: ?*Luau, num_args: i32) !ResumeStatus {
        const from_state: ?*LuaState = if (from) |from_val| @ptrCast(from_val) else null;
        const thread_status = c.lua_resume(@ptrCast(luau), from_state, num_args);
        switch (thread_status) {
            StatusCode.err_runtime => return error.Runtime,
            StatusCode.err_memory => return error.Memory,
            StatusCode.err_error => return error.MsgHandler,
            else => return @enumFromInt(thread_status),
        }
    }


    /// Pops a table from the stack and sets it as the new environment for the value at the
    /// given index. Returns an error if the value at that index is not a function or thread or userdata.
    pub fn setfenv(luau: *Luau, index: i32) !void {
        if (c.lua_setfenv(@ptrCast(luau), index) == 0) return error.Fail;
    }

    /// Does the equivalent to t[`k`] = v where t is the value at the given `index`
    /// and v is the value on the top of the stack
    pub fn setField(luau: *Luau, index: i32, k: [:0]const u8) void {
        c.lua_setfield(@ptrCast(luau), index, k.ptr);
    }

    /// Pops a value from the stack and sets it as the new value of global `name`
    pub fn setGlobal(luau: *Luau, name: [:0]const u8) void {
        c.lua_setglobal(zConverter.LuauToState(luau), name.ptr);
    }

    /// Pops a table or nil from the stack and sets that value as the new metatable for the
    /// value at the given `index`
    pub fn setMetatable(luau: *Luau, index: i32) void {
        // lua_setmetatable always returns 1 so is safe to ignore
        _ = c.lua_setmetatable(@ptrCast(luau), index);
    }

    /// Does the equivalent to t[k] = v, where t is the value at the given `index`
    /// v is the value on the top of the stack, and k is the value just below the top
    pub fn setTable(luau: *Luau, index: i32) void {
        c.lua_settable(@ptrCast(luau), index);
    }

    /// Sets the top of the stack to `index`
    /// If the new top is greater than the old, new elements are filled with nil
    /// If `index` is 0 all stack elements are removed
    pub fn setTop(luau: *Luau, index: i32) void {
        c.lua_settop(@ptrCast(luau), index);
    }

    /// Returns the status of this thread
    pub fn status(luau: *Luau) Status {
        return @enumFromInt(c.lua_status(@ptrCast(luau)));
    }

    /// Converts the Luau value at the given `index` into a boolean
    /// The Luau value at the index will be considered true unless it is false or nil
    pub fn toBoolean(luau: *Luau, index: i32) bool {
        return c.lua_toboolean(@ptrCast(luau), index) != 0;
    }

    /// Converts a value at the given `index` into a CFn
    /// Returns an error if the value is not a CFn
    pub fn toCFunction(luau: *Luau, index: i32) !CFn {
        return c.lua_tocfunction(@ptrCast(luau), index) orelse return error.Fail;
    }

    /// Converts the Luau value at the given `index` to a signed integer
    /// The Luau value must be an integer, or a number, or a string convertible to an integer otherwise toInteger returns 0
    pub fn toInteger(luau: *Luau, index: i32) !Integer {
        var success: c_int = undefined;
        const result = c.lua_tointegerx(@ptrCast(luau), index, &success);
        if (success == 0) return error.Fail;
        return result;
    }

    /// Returns a slice of bytes at the given index
    /// If the value is not a string or number, returns an error
    /// If the value was a number the actual value in the stack will be changed to a string
    pub fn toLString(luau: *Luau, index: i32) ![:0]const u8 {
        var length: usize = undefined;
        if (c.lua_tolstring(@ptrCast(luau), index, &length)) |ptr| return ptr[0..length :0];
        return error.Fail;
    }

    /// Converts the Luau value at the given `index` to a float
    /// The Luau value must be a number or a string convertible to a number otherwise toNumber returns 0
    pub fn toNumber(luau: *Luau, index: i32) !Number {
        var success: c_int = undefined;
        const result = c.lua_tonumberx(@ptrCast(luau), index, &success);
        if (success == 0) return error.Fail;
        return result;
    }

    /// Converts the value at the given `index` to an opaque pointer
    pub fn toPointer(luau: *Luau, index: i32) !*const anyopaque {
        if (c.lua_topointer(@ptrCast(luau), index)) |ptr| return ptr;
        return error.Fail;
    }

    /// Converts the Luau value at the given `index` to a zero-terminated many-itemed-pointer (string)
    /// Returns an error if the conversion failed
    /// If the value was a number the actual value in the stack will be changed to a string
    pub fn toString(luau: *Luau, index: i32) ![:0]const u8 {
        var length: usize = undefined;
        if (c.lua_tolstring(@ptrCast(luau), index, &length)) |str| return str[0..length:0];
        return error.Fail;
    }

    /// Converts the value at the given `index` to a Luau thread (wrapped with a `Luau` struct)
    /// The thread does _not_ contain an allocator because it is not the main thread and should therefore not be used with `deinit()`
    /// Returns an error if the value is not a thread
    pub fn toThread(luau: *Luau, index: i32) !*Luau {
        const thread = c.lua_tothread(@ptrCast(luau), index);
        if (thread) |thread_ptr| return @ptrCast(thread_ptr);
        return error.Fail;
    }

    /// Returns a Luau-owned userdata pointer of the given type at the given index.
    /// Works for both light and full userdata.
    /// Returns an error if the value is not a userdata.
    pub fn toUserdata(luau: *Luau, comptime T: type, index: i32) !*T {
        if (c.lua_touserdata(@ptrCast(luau), index)) |ptr| return opaqueCast(T, ptr);
        return error.Fail;
    }

    /// Returns a Luau-owned userdata slice of the given type at the given index.
    /// Returns an error if the value is not a userdata.
    pub fn toUserdataSlice(luau: *Luau, comptime T: type, index: i32) ![]T {
        if (c.lua_touserdata(@ptrCast(luau), index)) |ptr| {
            const size = @as(u32, @intCast(luau.objectLen(index))) / @sizeOf(T);
            return @as([*]T, @ptrCast(@alignCast(ptr)))[0..size];
        }
        return error.Fail;
    }

    /// Returns the `LuaType` of the value at the given index
    /// Note that this is equivalent to lua_type but because type is a Zig primitive it is renamed to `typeOf`
    pub fn typeOf(luau: *Luau, index: i32) LuaType {
        return @enumFromInt(c.lua_type(@ptrCast(luau), index));
    }

    /// Returns the name of the given `LuaType` as a null-terminated slice
    pub fn typeName(luau: *Luau, t: LuaType) [:0]const u8 {
        return std.mem.span(c.lua_typename(@ptrCast(luau), @intFromEnum(t)));
    }

    /// Returns the pseudo-index that represents the `i`th upvalue of the running function
    pub fn upvalueIndex(i: i32) i32 {
        return c.lua_upvalueindex(i);
    }

    /// Pops `num` values from the current stack and pushes onto the stack of `to`
    pub fn xMove(luau: *Luau, to: *Luau, num: i32) void {
        c.lua_xmove(@ptrCast(luau), @ptrCast(to), num);
    }

    /// Yields a coroutine
    /// This function must be used as the return expression of a function
    pub fn yield(luau: *Luau, num_results: i32) i32 {
        return c.lua_yield(@ptrCast(luau), num_results);
    }

    // Debug library functions
    //
    // The debug interface functions are included in alphabetical order
    // Each is kept similar to the original C API function while also making it easy to use from Zig

    /// Gets information about a specific function or function invocation.
    pub fn getInfo(luau: *Luau, level: i32, options: DebugInfo.Options, info: *DebugInfo) void {
        const str = options.toString();

        var ar: Debug = undefined;

        // should never fail because we are controlling options with the struct param
        _ = c.lua_getinfo(@ptrCast(luau), level, &str, &ar);
        // std.debug.assert( != 0);

        // copy data into a struct
        if (options.l) info.current_line = if (ar.currentline == -1) null else ar.currentline;
        if (options.n) {
            info.name = if (ar.name != null) std.mem.span(ar.name) else null;
        }
        if (options.s) {
            info.source = std.mem.span(ar.source);
            // TODO: short_src figureit out
            @memcpy(&info.short_src, ar.short_src[0..c.LUA_IDSIZE]);
            info.first_line_defined = ar.linedefined;
            info.what = blk: {
                const what = std.mem.span(ar.what);
                if (std.mem.eql(u8, "Luau", what)) break :blk .luau;
                if (std.mem.eql(u8, "C", what)) break :blk .c;
                if (std.mem.eql(u8, "main", what)) break :blk .main;
                if (std.mem.eql(u8, "tail", what)) break :blk .tail;
                unreachable;
            };
        }
    }

    /// Gets information about a local variable
    /// Returns the name of the local variable
    pub fn getLocal(luau: *Luau, level: i32, n: i32) ![:0]const u8 {
        if (c.lua_getlocal(@ptrCast(luau), level, n)) |name| {
            return std.mem.span(name);
        }
        return error.Fail;
    }

    /// Gets information about the `n`th upvalue of the closure at index `func_index`
    pub fn getUpvalue(luau: *Luau, func_index: i32, n: i32) ![:0]const u8 {
        if (c.lua_getupvalue(@ptrCast(luau), func_index, n)) |name| {
            return std.mem.span(name);
        }
        return error.Fail;
    }

    /// Sets the value of a local variable
    /// Returns an error when the index is greater than the number of active locals
    /// Returns the name of the local variable
    pub fn setLocal(luau: *Luau, level: i32, n: i32) ![:0]const u8 {
        if (c.lua_setlocal(@ptrCast(luau), level, n)) |name| {
            return std.mem.span(name);
        }
        return error.Fail;
    }

    /// Sets the value of a closure's upvalue
    /// Returns the name of the upvalue or an error if the upvalue does not exist
    pub fn setUpvalue(luau: *Luau, func_index: i32, n: i32) ![:0]const u8 {
        if (c.lua_setupvalue(@ptrCast(luau), func_index, n)) |name| {
            return std.mem.span(name);
        }
        return error.Fail;
    }

    // Auxiliary library functions
    //
    // Auxiliary library functions are included in alphabetical order.
    // Each is kept similar to the original C API function while also making it easy to use from Zig

    /// Checks whether `cond` is true. Raises an error using `Luau.argError()` if not
    /// Possibly never returns
    pub fn argCheck(luau: *Luau, cond: bool, arg: i32, extra_msg: [:0]const u8) void {
        // translate-c failed
        if (!cond) luau.argError(arg, extra_msg);
    }

    /// Raises an error reporting a problem with argument `arg` of the C function that called it
    pub fn argError(luau: *Luau, arg: i32, extra_msg: [*:0]const u8) noreturn {
        _ = c.luaL_argerror(zConverter.LuauToState(luau), arg, extra_msg);
        unreachable;
    }

    /// Calls a metamethod
    pub fn callMeta(luau: *Luau, obj: i32, field: [:0]const u8) !void {
        if (c.luaL_callmeta(@ptrCast(luau), obj, field.ptr) == 0) return error.Fail;
    }

    /// Checks whether the function has an argument of any type at position `arg`
    pub fn checkAny(luau: *Luau, arg: i32) void {
        c.luaL_checkany(@ptrCast(luau), arg);
    }

    /// Checks whether the function argument `arg` is a number and returns the number cast to an Integer
    pub fn checkInteger(luau: *Luau, arg: i32) Integer {
        return c.luaL_checkinteger(@ptrCast(luau), arg);
    }

    /// Checks whether the function argument `arg` is a slice of bytes and returns the slice
    pub fn checkBytes(luau: *Luau, arg: i32) [:0]const u8 {
        var length: usize = 0;
        const str = c.luaL_checklstring(@ptrCast(luau), arg, &length);
        // luaL_checklstring never returns null (throws luau error)
        return str[0..length :0];
    }

    /// Checks whether the function argument `arg` is a number and returns the number
    pub fn checkNumber(luau: *Luau, arg: i32) Number {
        return c.luaL_checknumber(@ptrCast(luau), arg);
    }

    /// Checks whether the function argument `arg` is a string and searches for the enum value with the same name in `T`.
    /// `default` is used as a default value when not null
    /// Returns the enum value found
    /// Useful for mapping Luau strings to Zig enums
    pub fn checkOption(luau: *Luau, comptime T: type, arg: i32, default: ?T) T {
        const name = blk: {
            if (default) |defaultName| {
                break :blk luau.optLString(arg, @tagName(defaultName));
            } else {
                break :blk luau.checkBytes(arg);
            }
        };

        inline for (std.meta.fields(T)) |field| {
            if (std.mem.eql(u8, field.name, name)) {
                return @enumFromInt(field.value);
            }
        }

        return luau.argError(arg, luau.pushFString("invalid option '%s'", .{name.ptr}));
    }

    /// Grows the stack size to top + `size` elements, raising an error if the stack cannot grow to that size
    /// `msg` is an additional text to go into the error message
    pub fn checkStackErr(luau: *Luau, size: i32, msg: ?[*:0]const u8) void {
        c.luaL_checkstack(@ptrCast(luau), size, msg);
    }

    /// Checks whether the function argument `arg` is a string and returns the string
    pub fn checkString(luau: *Luau, arg: i32) [:0]const u8 {
        var length: usize = 0;
        const str = c.luaL_checklstring(@ptrCast(luau), arg, &length);
        // luaL_checklstring never returns null (throws lua error)
        return str[0..length :0];
    }

    pub fn checkUnsigned(luau: *Luau, arg: i32) [*:0]const u8 {
        return c.luaL_checkunsigned(@ptrCast(luau), arg, null);
    }


    /// Checks whether the function argument `arg` has type `t`
    pub fn checkType(luau: *Luau, arg: i32, t: LuaType) void {
        c.luaL_checktype(@ptrCast(luau), arg, @intFromEnum(t));
    }

    /// Checks whether the function argument `arg` is a userdata of the type `name`
    /// Returns the userdata's memory-block address
    pub fn checkUserdata(luau: *Luau, comptime T: type, arg: i32, name: [:0]const u8) *T {
        // the returned pointer will not be null
        return opaqueCast(T, c.luaL_checkudata(@ptrCast(luau), arg, name.ptr).?);
    }

    /// Checks whether the function argument `arg` is a userdata of the type `name`
    /// Returns a Luau-owned userdata slice
    pub fn checkUserdataSlice(luau: *Luau, comptime T: type, arg: i32, name: [:0]const u8) []T {
        // the returned pointer will not be null
        const ptr = c.luaL_checkudata(@ptrCast(luau), arg, name.ptr).?;
        const size = @as(u32, @intCast(luau.objLen(arg))) / @sizeOf(T);
        return @as([*]T, @ptrCast(@alignCast(ptr)))[0..size];
    }

    /// Raises an error
    pub fn raiseErrorStr(luau: *Luau, fmt: [:0]const u8, args: anytype) noreturn {
        _ = @call(.auto, c.luaL_errorL, .{ zConverter.LuauToState(luau), fmt.ptr } ++ args);
        unreachable;
    }

    pub fn loadBytecode(luau: *Luau, chunkname: [:0]const u8, bytecode: []const u8) !void {
        if (c.luau_load(@ptrCast(luau), chunkname.ptr, bytecode.ptr, bytecode.len, 0) != 0) return error.Fail;
    }

    /// Pushes onto the stack the field `e` from the metatable of the object at index `obj`
    /// and returns the type of the pushed value
    pub fn getMetaField(luau: *Luau, obj: i32, field: [:0]const u8) !LuaType {
        const val_type: LuaType = @enumFromInt(c.luaL_getmetafield(@ptrCast(luau), obj, field.ptr));
        if (val_type == .nil) return error.Fail;
        return val_type;
    }

    pub fn getMainThread(luau: *Luau) *Luau {
        return @ptrCast(c.lua_mainthread(@ptrCast(luau)));
    }

    /// Pushes onto the stack the metatable associated with the name `type_name` in the registry
    /// or nil if there is no metatable associated with that name. Returns the type of the pushed value
    pub fn getMetatableRegistry(luau: *Luau, table_name: [:0]const u8) LuaType {
        return @enumFromInt(c.luaL_getmetatable(@ptrCast(luau), table_name));
    }

    /// If the registry already has the key `key`, returns an error
    /// Otherwise, creates a new table to be used as a metatable for userdata
    pub fn newMetatable(luau: *Luau, key: [:0]const u8) !void {
        if (c.luaL_newmetatable(@ptrCast(luau), key.ptr) == 0) return error.Fail;
    }

    /// Creates a new Luau state with an allocator using the default libc allocator
    pub fn newStateLibc() !*Luau {
        zig_registerAssertionHandler();

        if (c.luaL_newstate()) |state| {
            return @ptrCast(state);
        } else return error.Memory;
    }

    // luaL_opt (a macro) really isn't that useful, so not going to implement for now

    /// If the function argument `arg` is an integer, returns the integer
    /// If the argument is absent or nil returns `default`
    pub fn optInteger(luau: *Luau, arg: i32) ?Integer {
        if (luau.isNoneOrNil(arg)) return null;
        return luau.checkInteger(arg);
    }

    /// If the function argument `arg` is a slice of bytes, returns the slice
    /// If the argument is absent or nil returns `default`
    pub fn optLString(luau: *Luau, arg: i32, default: [:0]const u8) [:0]const u8 {
        var length: usize = 0;
        // will never return null because default cannot be null
        const ret: [*]const u8 = c.luaL_optlstring(@ptrCast(luau), arg, default.ptr, &length);
        if (ret == default.ptr) return default;
        return ret[0..length :0];
    }

    /// If the function argument `arg` is a number, returns the number
    /// If the argument is absent or nil returns `default`
    pub fn optNumber(luau: *Luau, arg: i32) ?Number {
        if (luau.isNoneOrNil(arg)) return null;
        return luau.checkNumber(arg);
    }

    /// If the function argument `arg` is a string, returns the string
    /// If the argment is absent or nil returns `default`
    pub fn optString(luau: *Luau, arg: i32) ?[:0]const u8 {
        if (luau.isNoneOrNil(arg)) return null;
        return luau.checkString(arg);
    }

    pub fn optUnsigned(luau: *Luau, arg: i32) ?Unsigned {
        if (luau.isNoneOrNil(arg)) return null;
        return luau.checkUnsigned(arg);
    }

    /// Creates and returns a reference in the table at index `index` for the object on the top of the stack
    /// Pops the object
    pub fn ref(luau: *Luau, index: i32) !i32 {
        const ret = c.lua_ref(@ptrCast(luau), index);
        return if (ret == ref_nil) error.Fail else ret;
    }

    pub fn findTable(luau: *Luau, index: i32, name: [:0]const u8, sizehint: usize) ?[:0]const u8 {
        if (c.luaL_findtable(@ptrCast(luau), index, name, @intCast(sizehint))) |e| {
            return std.mem.span(e);
        }
        return null;
    }

    /// Opens a library
    pub fn registerFns(luau: *Luau, libname: ?[:0]const u8, funcs: []const FnReg) void {
        // translated from the implementation of luaI_openlib so we can use a slice of
        // FnReg without requiring a sentinel end value
        if (libname) |name| {
            _ = luau.findTable(REGISTRYINDEX, "_LOADED", 1);
            _ = luau.getField(-1, name);
            if (!luau.isTable(-1)) {
                luau.pop(1);
                if (luau.findTable(GLOBALSINDEX, name, funcs.len)) |_| {
                    luau.raiseErrorStr("name conflict for module '%s'", .{name.ptr});
                }
                luau.pushValue(-1);
                luau.setField(-3, name);
            }
            luau.remove(-2);
            luau.insert(-1);
        }
        for (funcs) |f| {
            if (f.func) |func| {
                luau.pushCFunction(func, f.name);
                luau.setField(-2, f.name);
            }
        }
    }

    /// Returns the name of the type of the value at the given `index`
    pub fn typeNameIndex(luau: *Luau, index: i32) [:0]const u8 {
        return std.mem.span(c.luaL_typename(@ptrCast(luau), index));
    }

    /// Releases the reference `r` from the table at index `index`
    pub fn unref(luau: *Luau, r: i32) void {
        c.lua_unref(@ptrCast(luau), r);
    }

    /// Pushes onto the stack a string identifying the current position of the control
    /// at the call stack `level`
    pub fn where(luau: *Luau, level: i32) void {
        c.luaL_where(@ptrCast(luau), level);
    }

    // Standard library loading functions

    /// Opens the specified standard library functions
    /// Behaves like openLibs, but allows specifying which libraries
    /// to expose to the global table rather than all of them
    pub fn open(luau: *Luau, libs: Libs) void {
        if (libs.base) luau.requireF("", c.luaopen_base);
        if (libs.string) luau.requireF(c.LUA_STRLIBNAME, c.luaopen_string);
        if (libs.table) luau.requireF(c.LUA_TABLIBNAME, c.luaopen_table);
        if (libs.math) luau.requireF(c.LUA_MATHLIBNAME, c.luaopen_math);
        if (libs.os) luau.requireF(c.LUA_OSLIBNAME, c.luaopen_os);
        if (libs.debug) luau.requireF(c.LUA_DBLIBNAME, c.luaopen_debug);
        if (libs.bit32) luau.requireF(c.LUA_BITLIBNAME, c.luaopen_bit32);
        if (libs.utf8) luau.requireF(c.LUA_UTF8LIBNAME, c.luaopen_utf8);
        if (libs.buffer) luau.requireF(c.LUA_BUFFERLIBNAME, c.luaopen_buffer);
    }

    fn requireF(luau: *Luau, name: [:0]const u8, func: ZigFn) void {
        luau.pushFunction(func, name);
        luau.pushString(name);
        luau.call(1, 0);
    }

    /// Open all standard libraries
    pub fn openLibs(luau: *Luau) void {
        c.luaL_openlibs(@ptrCast(luau));
    }

    /// Open the basic standard library
    pub fn openBase(luau: *Luau) void {
        _ = c.luaopen_base(@ptrCast(luau));
    }

    /// Open the string standard library
    pub fn openString(luau: *Luau) void {
        _ = c.luaopen_string(@ptrCast(luau));
    }

    /// Open the table standard library
    pub fn openTable(luau: *Luau) void {
        _ = c.luaopen_table(@ptrCast(luau));
    }

    /// Open the math standard library
    pub fn openMath(luau: *Luau) void {
        _ = c.luaopen_math(@ptrCast(luau));
    }

    /// Open the os standard library
    pub fn openOS(luau: *Luau) void {
        _ = c.luaopen_os(@ptrCast(luau));
    }

    /// Open the debug standard library
    pub fn openDebug(luau: *Luau) void {
        _ = c.luaopen_debug(@ptrCast(luau));
    }

    /// Open the coroutine standard library
    pub fn openCoroutine(luau: *Luau) void {
        _ = c.luaopen_coroutine(@ptrCast(luau));
    }

    /// Open the utf8 standard library
    pub fn openUtf8(luau: *Luau) void {
        _ = c.luaopen_utf8(@ptrCast(luau));
    }

    /// Open the bit32 standard library
    pub fn openBit32(luau: *Luau) void {
        _ = c.luaopen_bit32(@ptrCast(luau));
    }

    /// Open the buffer standard library
    pub fn openBuffer(luau: *Luau) void {
        _ = c.luaopen_buffer(@ptrCast(luau));
    }

    pub fn sandbox(luau: *Luau) void {
        c.luaL_sandbox(@ptrCast(luau));
    }

    pub fn sandboxThread(luau: *Luau) void {
        c.luaL_sandboxthread(@ptrCast(luau));
    }

};

/// A string buffer allowing for Zig code to build Luau strings piecemeal
/// All LuaBuffer functions are wrapped in this struct to make the API more convenient to use
pub const Buffer = struct {
    b: LuaBuffer = undefined,

    /// Initialize a Luau string buffer
    pub fn init(buf: *Buffer, luau: *Luau) void {
        c.luaL_buffinit(@ptrCast(luau), &buf.b);
    }

    /// TODO: buffinitsize
    /// Internal Luau type for a string buffer
    pub const LuaBuffer = c.luaL_Strbuf;

    pub const buffer_size = c.LUA_BUFFERSIZE;

    /// Adds `byte` to the buffer
    pub fn addChar(buf: *Buffer, byte: u8) void {
        // could not be translated by translate-c
        var lua_buf = &buf.b;
        if (lua_buf.p > &lua_buf.buffer[buffer_size - 1]) _ = buf.prep();
        lua_buf.p.* = byte;
        lua_buf.p += 1;
    }

    /// Adds the string to the buffer
    pub fn addBytes(buf: *Buffer, str: []const u8) void {
        c.luaL_addlstring(&buf.b, str.ptr, str.len);
    }

    /// Adds to the buffer a string of `length` previously copied to the buffer area
    pub fn addSize(buf: *Buffer, length: usize) void {
        // another function translate-c couldn't handle
        // c.luaL_addsize(&buf.b, length);
        var lua_buf = &buf.b;
        lua_buf.p += length;
    }

    /// Adds the zero-terminated string pointed to by `str` to the buffer
    pub fn addString(buf: *Buffer, str: [:0]const u8) void {
        c.luaL_addlstring(&buf.b, str.ptr, str.len);
    }

    /// Adds the value on the top of the stack to the buffer and pops the value
    pub fn addValue(buf: *Buffer) void {
        c.luaL_addvalue(&buf.b);
    }

    /// Adds the value at the given index to the buffer
    pub fn addValueAny(buf: *Buffer, idx: i32) void {
        c.luaL_addvalueany(&buf.b, idx);
    }

    /// Equivalent to prepSize with a buffer size of Buffer.buffer_size
    pub fn prep(buf: *Buffer) []u8 {
        return c.luaL_prepbuffsize(&buf.b, buffer_size)[0..buffer_size];
    }

    /// Finishes the use of the buffer leaving the final string on the top of the stack
    pub fn pushResult(buf: *Buffer) void {
        c.luaL_pushresult(&buf.b);
    }

    /// Equivalent to `Buffer.addSize()` followed by `Buffer.pushResult()`
    pub fn pushResultSize(buf: *Buffer, size: usize) void {
        c.luaL_pushresultsize(&buf.b, size);
    }
};

// Helper functions to make the ziglua API easier to use

pub inline fn opaqueCast(comptime T: type, ptr: *anyopaque) *T {
    return @ptrCast(@alignCast(ptr));
}

// pub const ZigFn = fn (luau: *Luau) i32;
// // pub const ZigHookFn = fn (luau: *Luau, event: Event, info: *DebugInfo) void;
// pub const ZigContFn = fn (luau: *Luau, status: Status, ctx: Context) i32;
// pub const ZigReaderFn = fn (luau: *Luau, data: *anyopaque) ?[]const u8;
// pub const ZigUserdataDtorFn = fn (data: *anyopaque) void;
// pub const ZigUserAtomCallbackFn = fn (str: []const u8) i16;
// pub const ZigWarnFn = fn (data: ?*anyopaque, msg: []const u8, to_cont: bool) void;
// pub const ZigWriterFn = fn (luau: *Luau, buf: []const u8, data: *anyopaque) bool;

// fn TypeOfWrap(comptime T: type) type {
//     return switch (T) {
//         LuaState => Luau,
//         ZigFn => CFn,
//         // ZigHookFn => CHookFn,
//         ZigContFn => CContFn,
//         ZigReaderFn => CReaderFn,
//         ZigUserdataDtorFn => CUserdataDtorFn,
//         ZigUserAtomCallbackFn => CUserAtomCallbackFn,
//         ZigWarnFn => CWarnFn,
//         ZigWriterFn => CWriterFn,
//         else => @compileError("unsupported type given to wrap: '" ++ @typeName(T) ++ "'"),
//     };
// }

/// Wraps the given value for use in the Luau API
/// Supports the following:
/// * `LuaState` => `Luau`
// pub fn wrap(comptime value: anytype) TypeOfWrap(@TypeOf(value)) {
//     const T = @TypeOf(value);
//     return switch (T) {
//         ZigFn => wrapZigFn(value),
//         // ZigHookFn => wrapZigHookFn(value),
//         ZigContFn => wrapZigContFn(value),
//         ZigReaderFn => wrapZigReaderFn(value),
//         ZigUserdataDtorFn => wrapZigUserdataDtorFn(value),
//         ZigUserAtomCallbackFn => wrapZigUserAtomCallbackFn(value),
//         ZigWarnFn => wrapZigWarnFn(value),
//         ZigWriterFn => wrapZigWriterFn(value),
//         else => @compileError("unsupported type given to wrap: '" ++ @typeName(T) ++ "'"),
//     };
// }

/// Wrap a ZigFn in a CFn for passing to the API
pub fn toCFn(comptime f: ZigFn) CFn {
    return struct {
        fn inner(state: ?*LuaState) callconv(.C) c_int {
            // this is called by Luau, state should never be null
            return @call(.always_inline, f, .{@as(*Luau, @ptrCast(state.?))});
        }
    }.inner;
}

/// Wrap a ZigHookFn in a CHookFn for passing to the API
// fn wrapZigHookFn(comptime f: ZigHookFn) CHookFn {
//     return struct {
//         fn inner(state: ?*LuaState, ar: ?*Debug) callconv(.C) void {
//             // this is called by Luau, state should never be null
//             var info: DebugInfo = .{
//                 .current_line = if (ar.?.currentline == -1) null else ar.?.currentline,
//                 .private = @ptrCast(ar.?.i_ci),
//             };
//             @call(.always_inline, f, .{ @as(*Luau, @ptrCast(state.?)), @as(Event, @enumFromInt(ar.?.event)), &info });
//         }
//     }.inner;
// }

/// Wrap a ZigContFn in a CContFn for passing to the API
// fn wrapZigContFn(comptime f: ZigContFn) CContFn {
//     return struct {
//         fn inner(state: ?*LuaState, status: c_int, ctx: Context) callconv(.C) c_int {
//             // this is called by Luau, state should never be null
//             return @call(.always_inline, f, .{ @as(*Luau, @ptrCast(state.?)), @as(Status, @enumFromInt(status)), ctx });
//         }
//     }.inner;
// }

/// Wrap a ZigReaderFn in a CReaderFn for passing to the API
// fn wrapZigReaderFn(comptime f: ZigReaderFn) CReaderFn {
//     return struct {
//         fn inner(state: ?*LuaState, data: ?*anyopaque, size: [*c]usize) callconv(.C) [*c]const u8 {
//             if (@call(.always_inline, f, .{ @as(*Luau, @ptrCast(state.?)), data.? })) |buffer| {
//                 size.* = buffer.len;
//                 return buffer.ptr;
//             } else {
//                 size.* = 0;
//                 return null;
//             }
//         }
//     }.inner;
// }

/// Wrap a ZigFn in a CFn for passing to the API
// fn wrapZigUserdataDtorFn(comptime f: ZigUserdataDtorFn) CUserdataDtorFn {
//     return struct {
//         fn inner(userdata: *anyopaque) callconv(.C) void {
//             return @call(.always_inline, f, .{userdata});
//         }
//     }.inner;
// }

/// Wrap a ZigFn in a CFn for passing to the API
// fn wrapZigUserAtomCallbackFn(comptime f: ZigUserAtomCallbackFn) CUserAtomCallbackFn {
//     return struct {
//         fn inner(str: [*c]const u8, len: usize) callconv(.C) i16 {
//             if (str) |s| {
//                 const buf = s[0..len];
//                 return @call(.always_inline, f, .{buf});
//             }
//             return -1;
//         }
//     }.inner;
// }

/// Wrap a ZigWarnFn in a CWarnFn for passing to the API
// fn wrapZigWarnFn(comptime f: ZigWarnFn) CWarnFn {
//     return struct {
//         fn inner(data: ?*anyopaque, msg: [*c]const u8, to_cont: c_int) callconv(.C) void {
//             // warning messages emitted from Luau should be null-terminated for display
//             const message = std.mem.span(@as([*:0]const u8, @ptrCast(msg)));
//             @call(.always_inline, f, .{ data, message, to_cont != 0 });
//         }
//     }.inner;
// }

/// Wrap a ZigWriterFn in a CWriterFn for passing to the API
// fn wrapZigWriterFn(comptime f: ZigWriterFn) CWriterFn {
//     return struct {
//         fn inner(state: ?*LuaState, buf: ?*const anyopaque, size: usize, data: ?*anyopaque) callconv(.C) c_int {
//             // this is called by Luau, state should never be null
//             const buffer = @as([*]const u8, @ptrCast(buf))[0..size];
//             const result = @call(.always_inline, f, .{ @as(*Luau, @ptrCast(state.?)), buffer, data.? });
//             // it makes more sense for the inner writer function to return false for failure,
//             // so negate the result here
//             return @intFromBool(!result);
//         }
//     }.inner;
// }

/// Zig wrapper for Luau lua_CompileOptions that uses the same defaults as Luau if
/// no compile options is specified.
pub const CompileOptions = struct {
    optimization_level: i32 = 1,
    debug_level: i32 = 1,
    coverage_level: i32 = 0,
    /// global builtin to construct vectors; disabled by default (<vector_lib>.<vector_ctor>)
    vector_lib: ?[*:0]const u8 = null,
    vector_ctor: ?[*:0]const u8 = null,
    /// vector type name for type tables; disabled by default
    vector_type: ?[*:0]const u8 = null,
    /// null-terminated array of globals that are mutable; disables the import optimization for fields accessed through these
    mutable_globals: ?[*:null]const ?[*:0]const u8 = null,
};

/// Compile luau source into bytecode, return callee owned buffer allocated through the given allocator.
pub fn compile(allocator: Allocator, source: []const u8, options: CompileOptions) ![]const u8 {
    var size: usize = 0;

    var opts = c.lua_CompileOptions{
        .optimizationLevel = options.optimization_level,
        .debugLevel = options.debug_level,
        .coverageLevel = options.coverage_level,
        .vectorLib = options.vector_lib,
        .vectorCtor = options.vector_ctor,
        .mutableGlobals = options.mutable_globals,
    };
    const bytecode = c.luau_compile(source.ptr, source.len, &opts, &size);
    if (bytecode == null) return error.Memory;
    defer zig_luau_free(bytecode);
    return try allocator.dupe(u8, bytecode[0..size]);
}
