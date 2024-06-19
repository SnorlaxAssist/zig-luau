const std = @import("std");
const testing = std.testing;

const luau = @import("luau");

const AllocFn = luau.AllocFn;
const Buffer = luau.Buffer;
const DebugInfo = luau.DebugInfo;
const Luau = luau.Luau;

const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectEqualStrings = testing.expectEqualStrings;
const expectError = testing.expectError;

fn expectStringContains(actual: []const u8, expected_contains: []const u8) !void {
    if (std.mem.indexOf(u8, actual, expected_contains) == null) return;
    return error.TestExpectedStringContains;
}

fn alloc(data: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) callconv(.C) ?*anyopaque {
    _ = data;

    const alignment = @alignOf(std.c.max_align_t);
    if (@as(?[*]align(alignment) u8, @ptrCast(@alignCast(ptr)))) |prev_ptr| {
        const prev_slice = prev_ptr[0..osize];
        if (nsize == 0) {
            testing.allocator.free(prev_slice);
            return null;
        }
        const new_ptr = testing.allocator.realloc(prev_slice, nsize) catch return null;
        return new_ptr.ptr;
    } else if (nsize == 0) {
        return null;
    } else {
        const new_ptr = testing.allocator.alignedAlloc(u8, alignment, nsize) catch return null;
        return new_ptr.ptr;
    }
}

fn failing_alloc(data: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) callconv(.C) ?*anyopaque {
    _ = data;
    _ = ptr;
    _ = osize;
    _ = nsize;
    return null;
}

test "initialization" {
    // initialize the Zig wrapper
    var lua = try Luau.init(&testing.allocator);
    try expectEqual(luau.Status.ok, lua.status());
    lua.deinit();

    // attempt to initialize the Zig wrapper with no memory
    try expectError(error.Memory, Luau.init(&testing.failing_allocator));

    // use the library directly
    lua = try Luau.newState(alloc, null);
    lua.close();

    // use the library with a bad AllocFn
    try expectError(error.Memory, Luau.newState(failing_alloc, null));

    // use the auxiliary library (uses libc realloc and cannot be checked for leaks!)
    lua = try Luau.newStateLibc();
    lua.close();
}

test "alloc functions" {
    var lua = try Luau.newState(alloc, null);
    defer lua.deinit();

    // get default allocator
    var data: *anyopaque = undefined;
    try expectEqual(alloc, lua.getAllocFn(&data));
}

test "Zig allocator access" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    const inner = struct {
        fn inner(l: *Luau) i32 {
            const allocator = l.allocator();

            const num = l.toInteger(1) catch unreachable;

            // Use the allocator
            const nums = allocator.alloc(i32, @intCast(num)) catch unreachable;
            defer allocator.free(nums);

            // Do something pointless to use the slice
            var sum: i32 = 0;
            for (nums, 0..) |*n, i| n.* = @intCast(i);
            for (nums) |n| sum += n;

            l.pushInteger(sum);
            return 1;
        }
    }.inner;

    lua.pushFunction(inner, "test");
    lua.pushInteger(10);
    try lua.pcall(1, 1, 0);

    try expectEqual(45, try lua.toInteger(-1));
}

test "standard library loading" {
    // open all standard libraries
    {
        var lua = try Luau.init(&testing.allocator);
        defer lua.deinit();
        lua.openLibs();
    }

    // open all standard libraries with individual functions
    // these functions are only useful if you want to load the standard
    // packages into a non-standard table
    {
        var lua = try Luau.init(&testing.allocator);
        defer lua.deinit();

        lua.openBase();
        lua.openString();
        lua.openTable();
        lua.openMath();
        lua.openOS();
        lua.openDebug();
        lua.openCoroutine();

        // lua.openUtf8();
    }
}

test "number conversion success and failure" {
    const lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    _ = lua.pushString("1234.5678");
    try expectEqual(1234.5678, try lua.toNumber(-1));

    _ = lua.pushString("1234");
    try expectEqual(1234, try lua.toInteger(-1));

    lua.pushNil();
    try expectError(error.Fail, lua.toNumber(-1));
    try expectError(error.Fail, lua.toInteger(-1));

    _ = lua.pushString("fail");
    try expectError(error.Fail, lua.toNumber(-1));
    try expectError(error.Fail, lua.toInteger(-1));
}

test "compare" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    lua.pushNumber(1);
    lua.pushNumber(2);

    try testing.expect(!lua.equal(1, 2));
    try testing.expect(lua.lessThan(1, 2));

    lua.pushInteger(2);
    try testing.expect(lua.equal(2, 3));
}

const add = struct {
    fn addInner(l: *Luau) i32 {
        const a = l.toInteger(1) catch 0;
        const b = l.toInteger(2) catch 0;
        l.pushInteger(a + b);
        return 1;
    }
}.addInner;

test "type of and getting values" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    lua.pushNil();
    try expect(lua.isNil(1));
    try expect(lua.isNoneOrNil(1));
    try expect(lua.isNoneOrNil(2));
    try expect(lua.isNone(2));
    try expectEqual(.nil, lua.typeOf(1));

    lua.pushBoolean(true);
    try expectEqual(.boolean, lua.typeOf(-1));
    try expect(lua.isBoolean(-1));

    lua.newTable();
    try expectEqual(.table, lua.typeOf(-1));
    try expect(lua.isTable(-1));

    lua.pushInteger(1);
    try expectEqual(.number, lua.typeOf(-1));
    try expect(lua.isNumber(-1));
    try expectEqual(1, try lua.toInteger(-1));
    try expectEqualStrings("number", lua.typeNameIndex(-1));

    var value: i32 = 0;
    lua.pushLightUserdata(&value);
    try expectEqual(.light_userdata, lua.typeOf(-1));
    try expect(lua.isLightUserdata(-1));
    try expect(lua.isUserdata(-1));

    lua.pushNumber(0.1);
    try expectEqual(.number, lua.typeOf(-1));
    try expect(lua.isNumber(-1));
    try expectEqual(0.1, try lua.toNumber(-1));

    _ = lua.pushThread();
    try expectEqual(.thread, lua.typeOf(-1));
    try expect(lua.isThread(-1));
    try expectEqual(lua, (try lua.toThread(-1)));

    lua.pushString("all your codebase are belong to us");
    try expectEqualStrings("all your codebase are belong to us", try lua.toString(-1));
    try expectEqual(.string, lua.typeOf(-1));
    try expect(lua.isString(-1));

    lua.pushFunction(add, "func");
    try expectEqual(.function, lua.typeOf(-1));
    try expect(lua.isCFunction(-1));
    try expect(lua.isFunction(-1));
    try expectEqual(luau.toCFn(add), try lua.toCFunction(-1));

    lua.pushString("hello world");
    try expectEqualStrings("hello world", try lua.toString(-1));
    try expectEqual(.string, lua.typeOf(-1));
    try expect(lua.isString(-1));

    _ = lua.pushFString("%s %s %d", .{ "hello", "world", @as(i32, 10) });
    try expectEqual(.string, lua.typeOf(-1));
    try expect(lua.isString(-1));
    try expectEqualStrings("hello world 10", try lua.toString(-1));

    lua.pushValue(2);
    try expectEqual(.boolean, lua.typeOf(-1));
    try expect(lua.isBoolean(-1));
}

test "typenames" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    try expectEqualStrings("no value", lua.typeName(.none));
    try expectEqualStrings("nil", lua.typeName(.nil));
    try expectEqualStrings("boolean", lua.typeName(.boolean));
    try expectEqualStrings("userdata", lua.typeName(.light_userdata));
    try expectEqualStrings("number", lua.typeName(.number));
    try expectEqualStrings("string", lua.typeName(.string));
    try expectEqualStrings("table", lua.typeName(.table));
    try expectEqualStrings("function", lua.typeName(.function));
    try expectEqualStrings("userdata", lua.typeName(.userdata));
    try expectEqualStrings("thread", lua.typeName(.thread));
    try expectEqualStrings("vector", lua.typeName(.vector));
    try expectEqualStrings("buffer", lua.typeName(.buffer));
}

// test "executing string contents" {
//     var lua = try Luau.init(&testing.allocator);
//     defer lua.deinit();
//     lua.openLibs();

//     try lua.loadString("f = function(x) return x + 10 end");
//     try lua.pcall(0, 0, 0);
//     try lua.loadString("a = f(2)");
//     try lua.pcall(0, 0, 0);

//     try expectEqual(.number, try lua.getGlobal("a"));
//     try expectEqual(12, try lua.toInteger(1));

//     try expectError(error.Fail, lua.loadString("bad syntax"));
//     try lua.loadString("a = g()");
//     try expectError(error.Runtime, lua.pcall(0, 0, 0));
// }

test "filling and checking the stack" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    try expectEqual(0, lua.getTop());

    // We want to push 30 values onto the stack
    // this should work without fail
    try lua.checkStack(30);

    var count: i32 = 0;
    while (count < 30) : (count += 1) {
        lua.pushNil();
    }

    try expectEqual(30, lua.getTop());

    // this should fail (beyond max stack size)
    try expectError(error.Fail, lua.checkStack(1_000_000));

    // this is small enough it won't fail (would raise an error if it did)
    lua.checkStackErr(40, null);
    while (count < 40) : (count += 1) {
        lua.pushNil();
    }

    try expectEqual(40, lua.getTop());
}

test "stack manipulation" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    var num: i32 = 1;
    while (num <= 10) : (num += 1) {
        lua.pushInteger(num);
    }
    try expectEqual(10, lua.getTop());

    lua.setTop(12);
    try expectEqual(12, lua.getTop());
    try expect(lua.isNil(-1));

    lua.remove(1);
    try expect(lua.isNil(-1));

    lua.insert(1);
    try expect(lua.isNil(1));

    lua.setTop(0);
    try expectEqual(0, lua.getTop());
}

test "calling a function" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    lua.register("zigadd", add);

    _ = try lua.getGlobal("zigadd");
    lua.pushInteger(10);
    lua.pushInteger(32);

    // pcall is preferred, but we might as well test call when we know it is safe
    lua.call(2, 1);
    try expectEqual(42, try lua.toInteger(1));
}

test "string buffers" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    var buffer: Buffer = undefined;
    buffer.init(lua);

    buffer.addChar('z');
    buffer.addString("igl");

    var str = buffer.prep();
    str[0] = 'u';
    str[1] = 'a';
    str[2] = 'u';
    buffer.addSize(3);

    buffer.addString(" api ");
    lua.pushNumber(5.1);
    buffer.addValue();
    buffer.pushResult();
    try expectEqualStrings("zigluau api 5.1", try lua.toString(-1));

    // now test a small buffer
    buffer.init(lua);
    var b = buffer.prep();
    b[0] = 'a';
    b[1] = 'b';
    b[2] = 'c';
    buffer.addSize(3);

    b = buffer.prep();
    @memcpy(b[0..23], "defghijklmnopqrstuvwxyz");
    buffer.addSize(23);
    buffer.pushResult();
    try expectEqualStrings("abcdefghijklmnopqrstuvwxyz", try lua.toString(-1));
    lua.pop(1);

    buffer.init(lua);
    b = buffer.prep();
    @memcpy(b[0..3], "abc");
    buffer.pushResultSize(3);
    try expectEqualStrings("abc", try lua.toString(-1));
    lua.pop(1);
}

const sub = struct {
    fn subInner(l: *Luau) i32 {
        const a = l.toInteger(1) catch 0;
        const b = l.toInteger(2) catch 0;
        l.pushInteger(a - b);
        return 1;
    }
}.subInner;

test "function registration" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    const funcs = [_]luau.FnReg{
        .{ .name = "add", .func = luau.toCFn(add) },
    };
    lua.newTable();
    lua.registerFns(null, &funcs);

    _ = lua.getField(-1, "add");
    lua.pushInteger(1);
    lua.pushInteger(2);
    try lua.pcall(2, 1, 0);
    try expectEqual(3, lua.toInteger(-1));
    lua.setTop(0);

    // register functions as globals in a library table
    lua.registerFns("testlib", &funcs);

    // testlib.add(1, 2)
    _ = try lua.getGlobal("testlib");
    _ = lua.getField(-1, "add");
    lua.pushInteger(1);
    lua.pushInteger(2);
    try lua.pcall(2, 1, 0);
    try expectEqual(3, lua.toInteger(-1));
}

test "warn fn" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    const warnFn = struct {
        fn inner(L: *Luau) i32 {
            const msg = L.toString(1) catch unreachable;
            if (!std.mem.eql(u8, msg, "this will be caught by the warnFn")) std.debug.panic("test failed", .{});
            return 0;
        }
    }.inner;

    lua.pushFunction(warnFn, "newWarn");
    lua.pushValue(-1);
    lua.setField(luau.GLOBALSINDEX, "warn");
    lua.pushString("this will be caught by the warnFn");
    lua.call(1, 0);
}

test "concat" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    _ = lua.pushString("hello ");
    lua.pushNumber(10);
    _ = lua.pushString(" wow!");
    lua.concat(3);

    try expectEqualStrings("hello 10 wow!", try lua.toString(-1));
}

test "garbage collector" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    // because the garbage collector is an opaque, unmanaged
    // thing, it is hard to test, so just run each function
    lua.gcStop();
    lua.gcCollect();
    lua.gcRestart();
    _ = lua.gcCount();
    _ = lua.gcCountB();

    _ = lua.gcIsRunning();
    lua.gcStep();

    _ = lua.gcSetGoal(10);
    _ = lua.gcSetStepMul(2);
    _ = lua.gcSetStepSize(1);
}

test "threads" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    var new_thread = lua.newThread();
    try expectEqual(1, lua.getTop());
    try expectEqual(0, new_thread.getTop());

    lua.pushInteger(10);
    lua.pushNil();

    lua.xMove(new_thread, 2);
    try expectEqual(2, new_thread.getTop());
}

test "userdata and uservalues" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    const Data = struct {
        val: i32,
        code: [4]u8,
    };

    // create a Luau-owned pointer to a Data with 2 associated user values
    var data = lua.newUserdata(Data);
    data.val = 1;
    @memcpy(&data.code, "abcd");

    try expectEqual(data, try lua.toUserdata(Data, 1));
    try expectEqual(@as(*const anyopaque, @ptrCast(data)), try lua.toPointer(1));
}

test "upvalues" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    // counter from PIL
    const counter = struct {
        fn inner(l: *Luau) i32 {
            var counter = l.toInteger(Luau.upvalueIndex(1)) catch 0;
            counter += 1;
            l.pushInteger(counter);
            l.pushInteger(counter);
            l.replace(Luau.upvalueIndex(1));
            return 1;
        }
    }.inner;

    // Initialize the counter at 0
    lua.pushInteger(0);
    lua.pushClosure(luau.toCFn(counter), "counter", 1);
    lua.setGlobal("counter");

    // call the function repeatedly, each time ensuring the result increases by one
    var expected: i32 = 1;
    while (expected <= 10) : (expected += 1) {
        _ = try lua.getGlobal("counter");
        lua.call(0, 1);
        try expectEqual(expected, try lua.toInteger(-1));
        lua.pop(1);
    }
}

test "raise error" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    const makeError = struct {
        fn inner(l: *Luau) i32 {
            _ = l.pushString("makeError made an error");
            l.raiseError();
            return 0;
        }
    }.inner;

    lua.pushFunction(makeError, "func");
    try expectError(error.Runtime, lua.pcall(0, 0, 0));
    try expectEqualStrings("makeError made an error", try lua.toString(-1));
}

fn continuation(l: *Luau, status: luau.Status, ctx: isize) i32 {
    _ = status;

    if (ctx == 5) {
        _ = l.pushString("done");
        return 1;
    } else {
        // yield the current context value
        l.pushInteger(ctx);
        return l.yieldCont(1, ctx + 1, luau.wrap(continuation));
    }
}

fn continuation52(l: *Luau) i32 {
    const ctxOrNull = l.getContext() catch unreachable;
    const ctx = ctxOrNull orelse 0;
    if (ctx == 5) {
        _ = l.pushString("done");
        return 1;
    } else {
        // yield the current context value
        l.pushInteger(ctx);
        return l.yieldCont(1, ctx + 1, luau.wrap(continuation52));
    }
}

test "yielding no continuation" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    var thread = lua.newThread();
    const func = struct {
        fn inner(l: *Luau) i32 {
            l.pushInteger(1);
            return l.yield(1);
        }
    }.inner;
    thread.pushFunction(func, "func");
    _ = try thread.resumeThread(null, 0);

    try expectEqual(1, thread.toInteger(-1));
}

test "aux check functions" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    const function = struct {
        fn inner(l: *Luau) i32 {
            l.checkAny(1);
            _ = l.checkInteger(2);
            _ = l.checkNumber(3);
            _ = l.checkString(4);
            l.checkType(5, .boolean);
            return 0;
        }
    }.inner;

    lua.pushFunction(function, "func");
    lua.pcall(0, 0, 0) catch {
        try expectStringContains("argument #1", try lua.toString(-1));
        lua.pop(-1);
    };

    lua.pushFunction(function, "func");
    lua.pushNil();
    lua.pcall(1, 0, 0) catch {
        try expectStringContains("number expected", try lua.toString(-1));
        lua.pop(-1);
    };

    lua.pushFunction(function, "func");
    lua.pushNil();
    lua.pushInteger(3);
    lua.pcall(2, 0, 0) catch {
        try expectStringContains("string expected", try lua.toString(-1));
        lua.pop(-1);
    };

    lua.pushFunction(function, "func");
    lua.pushNil();
    lua.pushInteger(3);
    lua.pushNumber(4);
    lua.pcall(3, 0, 0) catch {
        try expectStringContains("string expected", try lua.toString(-1));
        lua.pop(-1);
    };

    lua.pushFunction(function, "func");
    lua.pushNil();
    lua.pushInteger(3);
    lua.pushNumber(4);
    _ = lua.pushString("hello world");
    lua.pcall(4, 0, 0) catch {
        try expectStringContains("boolean expected", try lua.toString(-1));
        lua.pop(-1);
    };

    lua.pushFunction(function, "func");
    // test pushFail here (currently acts the same as pushNil)
    lua.pushNil();
    lua.pushInteger(3);
    lua.pushNumber(4);
    _ = lua.pushString("hello world");
    lua.pushBoolean(true);
    try lua.pcall(5, 0, 0);
}

test "aux opt functions" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    const function = struct {
        fn inner(l: *Luau) i32 {
            expectEqual(10, l.optInteger(1) orelse 10) catch unreachable;
            expectEqualStrings("zig", l.optString(2) orelse "zig") catch unreachable;
            expectEqual(1.23, l.optNumber(3) orelse 1.23) catch unreachable;
            expectEqualStrings("lang", l.optString(4) orelse "lang") catch unreachable;
            return 0;
        }
    }.inner;

    lua.pushFunction(function, "func");
    try lua.pcall(0, 0, 0);

    lua.pushFunction(function, "func");
    lua.pushInteger(10);
    _ = lua.pushString("zig");
    lua.pushNumber(1.23);
    _ = lua.pushString("lang");
    try lua.pcall(4, 0, 0);
}

test "checkOption" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    const Variant = enum {
        one,
        two,
        three,
    };

    const function = struct {
        fn inner(l: *Luau) i32 {
            const option = l.checkOption(Variant, 1, .one);
            l.pushInteger(switch (option) {
                .one => 1,
                .two => 2,
                .three => 3,
            });
            return 1;
        }
    }.inner;

    lua.pushFunction(function, "func");
    _ = lua.pushString("one");
    try lua.pcall(1, 1, 0);
    try expectEqual(1, try lua.toInteger(-1));
    lua.pop(1);

    lua.pushFunction(function, "func");
    _ = lua.pushString("two");
    try lua.pcall(1, 1, 0);
    try expectEqual(2, try lua.toInteger(-1));
    lua.pop(1);

    lua.pushFunction(function, "func");
    _ = lua.pushString("three");
    try lua.pcall(1, 1, 0);
    try expectEqual(3, try lua.toInteger(-1));
    lua.pop(1);

    // try the default now
    lua.pushFunction(function, "func");
    try lua.pcall(0, 1, 0);
    try expectEqual(1, try lua.toInteger(-1));
    lua.pop(1);

    // check the raised error
    lua.pushFunction(function, "func");
    _ = lua.pushString("unknown");
    try expectError(error.Runtime, lua.pcall(1, 1, 0));
    try expectStringContains("(invalid option 'unknown')", try lua.toString(-1));
}

test "ref luau" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    lua.pushNil();
    try expectError(error.Fail, lua.ref(1));
    try expectEqual(1, lua.getTop());

    // In luau lua.ref does not pop the item from the stack
    // and the data is stored in the REGISTRYINDEX by default
    _ = lua.pushString("Hello there");
    const ref = try lua.ref(2);

    _ = lua.rawGetIndex(luau.REGISTRYINDEX, ref);
    try expectEqualStrings("Hello there", try lua.toString(-1));

    lua.unref(ref);
}

test "args and errors" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    const argCheck = struct {
        fn inner(l: *Luau) i32 {
            l.argCheck(false, 1, "error!");
            return 0;
        }
    }.inner;

    lua.pushFunction(argCheck, "ArgCheck");
    try expectError(error.Runtime, lua.pcall(0, 0, 0));

    const raisesError = struct {
        fn inner(l: *Luau) i32 {
            l.raiseErrorStr("some error %s!", .{"zig"});
            unreachable;
        }
    }.inner;

    lua.pushFunction(raisesError, "Error");
    try expectError(error.Runtime, lua.pcall(0, 0, 0));
    try expectEqualStrings("some error zig!", try lua.toString(-1));
}

test "objectLen" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();

    _ = lua.pushString("lua");
    try testing.expectEqual(3, lua.objLen(-1));
}

test "compile and run bytecode" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit();
    lua.openLibs();

    // Load bytecode
    const src = "return 133";
    const bc = try luau.compile(testing.allocator, src, luau.CompileOptions{});
    defer testing.allocator.free(bc);

    try lua.loadBytecode("...", bc);
    try lua.pcall(0, 1, 0);
    const v = try lua.toInteger(-1);
    try expectEqual(133, v);

    // Try mutable globals.  Calls to mutable globals should produce longer bytecode.
    const src2 = "Foo.print()\nBar.print()";
    const bc1 = try luau.compile(testing.allocator, src2, luau.CompileOptions{});
    defer testing.allocator.free(bc1);

    const options = luau.CompileOptions{
        .mutable_globals = &[_:null]?[*:0]const u8{ "Foo", "Bar" },
    };
    const bc2 = try luau.compile(testing.allocator, src2, options);
    defer testing.allocator.free(bc2);
    // A really crude check for changed bytecode.  Better would be to match
    // produced bytecode in text format, but the API doesn't support it.
    try expect(bc1.len < bc2.len);
}

test "userdata dtor" {
    var gc_hits: i32 = 0;

    const Data = struct {
        gc_hits_ptr: *i32,

        pub fn dtor(udata: *anyopaque) void {
            const self: *@This() = @alignCast(@ptrCast(udata));
            self.gc_hits_ptr.* = self.gc_hits_ptr.* + 1;
        }
    };

    // create a Luau-owned pointer to a Data, configure Data with a destructor.
    {
        var lua = try Luau.init(&testing.allocator);
        defer lua.deinit(); // forces dtors to be called at the latest

        var data = lua.newUserdataDtor(Data, Data.dtor);
        data.gc_hits_ptr = &gc_hits;
        try expectEqual(@as(*anyopaque, @ptrCast(data)), try lua.toPointer(1));
        try expectEqual(0, gc_hits);
        lua.pop(1); // don't let the stack hold a ref to the user data
        lua.gcCollect();
        try expectEqual(1, gc_hits);
        lua.gcCollect();
        try expectEqual(1, gc_hits);
    }
}

fn vectorCtor(l: *Luau) i32 {
    const x = l.toNumber(1) catch unreachable;
    const y = l.toNumber(2) catch unreachable;
    const z = l.toNumber(3) catch unreachable;
    if (luau.luau_vector_size == 4) {
        const w = l.optNumber(4, 0);
        l.pushVector(@floatCast(x), @floatCast(y), @floatCast(z), @floatCast(w));
    } else {
        l.pushVector(@floatCast(x), @floatCast(y), @floatCast(z));
    }
    return 1;
}

fn foo(a: i32, b: i32) i32 {
    return a + b;
}

fn bar(a: i32, b: i32) !i32 {
    if (a > b) return error.wrong;
    return a + b;
}

test "debug stacktrace" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit(); // forces dtors to be called at the latest

    const stackTrace = struct {
        fn inner(l: *Luau) i32 {
            l.pushString(l.debugTrace());
            return 1;
        }
    }.inner;
    lua.pushFunction(stackTrace, "test");
    try lua.pcall(0, 1, 0);
    try expectEqualStrings("[C] function test\n", try lua.toString(-1));
}

test "debug stacktrace luau" {
    var lua = try Luau.init(&testing.allocator);
    defer lua.deinit(); // forces dtors to be called at the latest

    const src =
        \\function MyFunction()
        \\  return stack()
        \\end
        \\
        \\return MyFunction()
        \\
    ;

    const bc = try luau.compile(testing.allocator, src, .{
        .debug_level = 2,
    });
    defer testing.allocator.free(bc);

    const stackTrace = struct {
        fn inner(l: *Luau) i32 {
            l.pushString(l.debugTrace());
            return 1;
        }
    }.inner;
    lua.pushFunction(stackTrace, "stack");
    lua.setGlobal("stack");

    try lua.loadBytecode("module", bc);
    try lua.pcall(0, 1, 0);
    try expectEqualStrings(
        \\[C] function stack
        \\[string "module"]:2 function MyFunction
        \\[string "module"]:5
        \\
    , try lua.toString(-1));
}
