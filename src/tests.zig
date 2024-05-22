const std = @import("std");
const testing = std.testing;

const zigluau = @import("zigluau");

const AllocFn = zigluau.AllocFn;
const Buffer = zigluau.Buffer;
const DebugInfo = zigluau.DebugInfo;
const Lua = zigluau.Lua;

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
    var lua = try Lua.init(testing.allocator);
    try expectEqual(zigluau.Status.ok, lua.status());
    lua.deinit();

    // attempt to initialize the Zig wrapper with no memory
    try expectError(error.Memory, Lua.init(&testing.failing_allocator));

    // use the library directly
    lua = try Lua.newState(alloc, null);
    lua.close();

    // use the library with a bad AllocFn
    try expectError(error.Memory, Lua.newState(failing_alloc, null));

    // use the auxiliary library (uses libc realloc and cannot be checked for leaks!)
    lua = try Lua.newStateLibc();
    lua.close();
}

test "alloc functions" {
    var lua = try Lua.newState(alloc, null);
    defer lua.deinit();

    // get default allocator
    var data: *anyopaque = undefined;
    try expectEqual(alloc, lua.getAllocFn(&data));
}

test "Zig allocator access" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const inner = struct {
        fn inner(l: *Lua) i32 {
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

    lua.pushFunction(zigluau.wrap(inner));
    lua.pushInteger(10);
    try lua.protectedCall(1, 1, 0);

    try expectEqual(45, try lua.toInteger(-1));
}

test "standard library loading" {
    // open all standard libraries
    {
        var lua = try Lua.init(testing.allocator);
        defer lua.deinit();
        lua.openLibs();
    }

    // open all standard libraries with individual functions
    // these functions are only useful if you want to load the standard
    // packages into a non-standard table
    {
        var lua = try Lua.init(testing.allocator);
        defer lua.deinit();

        lua.openBase();
        lua.openString();
        lua.openTable();
        lua.openMath();
        lua.openOS();
        lua.openDebug();

        lua.openCoroutine();
        lua.openUtf8();
    }
}

test "number conversion success and failure" {
    const lua = try Lua.init(testing.allocator);
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
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.pushNumber(1);
    lua.pushNumber(2);

    try testing.expect(!lua.equal(1, 2));
    try testing.expect(lua.lessThan(1, 2));

    lua.pushInteger(2);
    try testing.expect(lua.equal(2, 3));
}

const add = struct {
    fn addInner(l: *Lua) i32 {
        const a = l.toInteger(1) catch 0;
        const b = l.toInteger(2) catch 0;
        l.pushInteger(a + b);
        return 1;
    }
}.addInner;

test "type of and getting values" {
    var lua = try Lua.init(testing.allocator);
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

    try expectEqualStrings("all your codebase are belong to us", lua.pushStringZ("all your codebase are belong to us"));
    try expectEqual(.string, lua.typeOf(-1));
    try expect(lua.isString(-1));

    lua.pushFunction(zigluau.wrap(add));
    try expectEqual(.function, lua.typeOf(-1));
    try expect(lua.isCFunction(-1));
    try expect(lua.isFunction(-1));
    try expectEqual(zigluau.wrap(add), try lua.toCFunction(-1));

    try expectEqualStrings("hello world", lua.pushString("hello world"));
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
    var lua = try Lua.init(testing.allocator);
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

test "executing string contents" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();
    lua.openLibs();

    try lua.loadString("f = function(x) return x + 10 end");
    try lua.protectedCall(0, 0, 0);
    try lua.loadString("a = f(2)");
    try lua.protectedCall(0, 0, 0);

    try expectEqual(.number, try lua.getGlobal("a"));
    try expectEqual(12, try lua.toInteger(1));

    try expectError(error.Fail, lua.loadString("bad syntax"));
    try lua.loadString("a = g()");
    try expectError(error.Runtime, lua.protectedCall(0, 0, 0));
}

test "filling and checking the stack" {
    var lua = try Lua.init(testing.allocator);
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
    var lua = try Lua.init(testing.allocator);
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
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.register("zigadd", zigluau.wrap(add));

    _ = try lua.getGlobal("zigadd");
    lua.pushInteger(10);
    lua.pushInteger(32);

    // protectedCall is preferred, but we might as well test call when we know it is safe
    lua.call(2, 1);
    try expectEqual(42, try lua.toInteger(1));
}

test "string buffers" {
    var lua = try Lua.init();
    defer lua.deinit();

    var buffer: Buffer = undefined;
    buffer.init(lua);

    buffer.addChar('z');
    buffer.addStringZ("igl");

    var str = buffer.prep();
    str[0] = 'u';
    str[1] = 'a';
    buffer.addSize(2);

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
    fn subInner(l: *Lua) i32 {
        const a = l.toInteger(1) catch 0;
        const b = l.toInteger(2) catch 0;
        l.pushInteger(a - b);
        return 1;
    }
}.subInner;

test "function registration" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const funcs = [_]zigluau.FnReg{
        .{ .name = "add", .func = zigluau.wrap(add) },
    };
    lua.newTable();
    lua.registerFns(null, &funcs);

    _ = lua.getField(-1, "add");
    lua.pushInteger(1);
    lua.pushInteger(2);
    try lua.protectedCall(2, 1, 0);
    try expectEqual(3, lua.toInteger(-1));
    lua.setTop(0);

    // register functions as globals in a library table
    lua.registerFns("testlib", &funcs);

    // testlib.add(1, 2)
    _ = try lua.getGlobal("testlib");
    _ = lua.getField(-1, "add");
    lua.pushInteger(1);
    lua.pushInteger(2);
    try lua.protectedCall(2, 1, 0);
    try expectEqual(3, lua.toInteger(-1));
}

test "warn fn" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.warning("this message is going to the void", false);

    const warnFn = zigluau.wrap(struct {
        fn inner(data: ?*anyopaque, msg: []const u8, to_cont: bool) void {
            _ = data;
            _ = to_cont;
            if (!std.mem.eql(u8, msg, "this will be caught by the warnFn")) std.debug.panic("test failed", .{});
        }
    }.inner);

    lua.setWarnF(warnFn, null);
    lua.warning("this will be caught by the warnFn", false);
}

test "concat" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    _ = lua.pushStringZ("hello ");
    lua.pushNumber(10);
    _ = lua.pushStringZ(" wow!");
    lua.concat(3);

    try expectEqualStrings("hello 10 wow!", try lua.toString(-1));
}

test "garbage collector" {
    var lua = try Lua.init(testing.allocator);
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

test "table access" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString("a = { [1] = 'first', key = 'value', ['other one'] = 1234 }");
    _ = try lua.getGlobal("a");

    try expectEqual(.string, lua.rawGetIndex(1, 1));
    try expectEqualStrings("first", try lua.toString(-1));

    _ = lua.pushStringZ("key");
    try expectEqual(.string, lua.getTable(1));
    try expectEqualStrings("value", try lua.toString(-1));

    _ = lua.pushStringZ("other one");
    try expectEqual(.number, lua.rawGetTable(1));
    try expectEqual(1234, try lua.toInteger(-1));

    // a.name = "zigluau"
    _ = lua.pushStringZ("name");
    _ = lua.pushStringZ("zigluau");
    lua.setTable(1);

    // a.lang = "zig"
    _ = lua.pushStringZ("lang");
    _ = lua.pushStringZ("zig");
    lua.rawSetTable(1);

    try expectError(error.Fail, lua.getMetatable(1));

    // create a metatable (it isn't a useful one)
    lua.newTable();

    lua.pushFunction(zigluau.wrap(add));
    lua.setField(-2, "__len");
    lua.setMetatable(1);

    try lua.getMetatable(1);
    _ = try lua.getMetaField(1, "__len");
    try expectError(error.Fail, lua.getMetaField(1, "__index"));

    lua.pushBoolean(true);
    lua.setField(1, "bool");

    try lua.doString("b = a.bool");
    try expectEqual(.boolean, try lua.getGlobal("b"));
    try expect(lua.toBoolean(-1));

    // create array [1, 2, 3, 4, 5]
    lua.createTable(0, 0);
    var index: i32 = 1;
    while (index <= 5) : (index += 1) {
        lua.pushInteger(index);
        lua.rawSetIndex(-2, index);
    }

    // add a few more
    while (index <= 10) : (index += 1) {
        lua.pushInteger(index);
        lua.rawSetIndex(-2, index);
    }
}

test "threads" {
    var lua = try Lua.init(testing.allocator);
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
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const Data = struct {
        val: i32,
        code: [4]u8,
    };

    // create a Lua-owned pointer to a Data with 2 associated user values
    var data = lua.newUserdata(Data);
    data.val = 1;
    @memcpy(&data.code, "abcd");

    try expectEqual(data, try lua.toUserdata(Data, 1));
    try expectEqual(@as(*const anyopaque, @ptrCast(data)), try lua.toPointer(1));
}

test "upvalues" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // counter from PIL
    const counter = struct {
        fn inner(l: *Lua) i32 {
            var counter = l.toInteger(Lua.upvalueIndex(1)) catch 0;
            counter += 1;
            l.pushInteger(counter);
            l.pushInteger(counter);
            l.replace(Lua.upvalueIndex(1));
            return 1;
        }
    }.inner;

    // Initialize the counter at 0
    lua.pushInteger(0);
    lua.pushClosure(zigluau.wrap(counter), 1);
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

test "table traversal" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString("t = { key = 'value', second = true, third = 1 }");
    _ = try lua.getGlobal("t");

    lua.pushNil();

    while (lua.next(1)) {
        switch (lua.typeOf(-1)) {
            .string => {
                try expectEqualStrings("key", try lua.toString(-2));
                try expectEqualStrings("value", try lua.toString(-1));
            },
            .boolean => {
                try expectEqualStrings("second", try lua.toString(-2));
                try expectEqual(true, lua.toBoolean(-1));
            },
            .number => {
                try expectEqualStrings("third", try lua.toString(-2));
                try expectEqual(1, try lua.toInteger(-1));
            },
            else => unreachable,
        }
        lua.pop(1);
    }
}

test "raise error" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const makeError = struct {
        fn inner(l: *Lua) i32 {
            _ = l.pushStringZ("makeError made an error");
            l.raiseError();
            return 0;
        }
    }.inner;

    lua.pushFunction(zigluau.wrap(makeError));
    try expectError(error.Runtime, lua.protectedCall(0, 0, 0));
    try expectEqualStrings("makeError made an error", try lua.toString(-1));
}

fn continuation(l: *Lua, status: zigluau.Status, ctx: isize) i32 {
    _ = status;

    if (ctx == 5) {
        _ = l.pushStringZ("done");
        return 1;
    } else {
        // yield the current context value
        l.pushInteger(ctx);
        return l.yieldCont(1, ctx + 1, zigluau.wrap(continuation));
    }
}

fn continuation52(l: *Lua) i32 {
    const ctxOrNull = l.getContext() catch unreachable;
    const ctx = ctxOrNull orelse 0;
    if (ctx == 5) {
        _ = l.pushStringZ("done");
        return 1;
    } else {
        // yield the current context value
        l.pushInteger(ctx);
        return l.yieldCont(1, ctx + 1, zigluau.wrap(continuation52));
    }
}

test "yielding no continuation" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    var thread = lua.newThread();
    const func = zigluau.wrap(struct {
        fn inner(l: *Lua) i32 {
            l.pushInteger(1);
            return l.yield(1);
        }
    }.inner);
    thread.pushFunction(func);
    _ = try thread.resumeThread(null, 0);

    try expectEqual(1, thread.toInteger(-1));
}

test "resuming" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // here we create a Lua function that will run 5 times, continutally
    // yielding a count until it finally returns the string "done"
    var thread = lua.newThread();
    thread.openLibs();
    try thread.doString(
        \\counter = function()
        \\  coroutine.yield(1)
        \\  coroutine.yield(2)
        \\  coroutine.yield(3)
        \\  coroutine.yield(4)
        \\  coroutine.yield(5)
        \\  return "done"
        \\end
    );
    _ = try thread.getGlobal("counter");

    var i: i32 = 1;
    while (i <= 5) : (i += 1) {
        try expectEqual(.yield, try thread.resumeThread(lua, 0));
        try expectEqual(i, thread.toInteger(-1));
        lua.pop(lua.getTop());
    }
    try expectEqual(.ok, try thread.resumeThread(lua, 0));
    try expectEqualStrings("done", try thread.toString(-1));
}

test "aux check functions" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const function = zigluau.wrap(struct {
        fn inner(l: *Lua) i32 {
            l.checkAny(1);
            _ = l.checkInteger(2);
            _ = l.checkNumber(3);
            _ = l.checkString(4);
            l.checkType(5, .boolean);
            return 0;
        }
    }.inner);

    lua.pushFunction(function);
    lua.protectedCall(0, 0, 0) catch {
        try expectStringContains("argument #1", try lua.toString(-1));
        lua.pop(-1);
    };

    lua.pushFunction(function);
    lua.pushNil();
    lua.protectedCall(1, 0, 0) catch {
        try expectStringContains("number expected", try lua.toString(-1));
        lua.pop(-1);
    };

    lua.pushFunction(function);
    lua.pushNil();
    lua.pushInteger(3);
    lua.protectedCall(2, 0, 0) catch {
        try expectStringContains("string expected", try lua.toString(-1));
        lua.pop(-1);
    };

    lua.pushFunction(function);
    lua.pushNil();
    lua.pushInteger(3);
    lua.pushNumber(4);
    lua.protectedCall(3, 0, 0) catch {
        try expectStringContains("string expected", try lua.toString(-1));
        lua.pop(-1);
    };

    lua.pushFunction(function);
    lua.pushNil();
    lua.pushInteger(3);
    lua.pushNumber(4);
    _ = lua.pushString("hello world");
    lua.protectedCall(4, 0, 0) catch {
        try expectStringContains("boolean expected", try lua.toString(-1));
        lua.pop(-1);
    };

    lua.pushFunction(function);
    // test pushFail here (currently acts the same as pushNil)
    lua.pushNil();
    lua.pushInteger(3);
    lua.pushNumber(4);
    _ = lua.pushString("hello world");
    lua.pushBoolean(true);
    try lua.protectedCall(5, 0, 0);
}

test "aux opt functions" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const function = zigluau.wrap(struct {
        fn inner(l: *Lua) i32 {
            expectEqual(10, l.optInteger(1) orelse 10) catch unreachable;
            expectEqualStrings("zig", l.optString(2) orelse "zig") catch unreachable;
            expectEqual(1.23, l.optNumber(3) orelse 1.23) catch unreachable;
            expectEqualStrings("lang", l.optString(4) orelse "lang") catch unreachable;
            return 0;
        }
    }.inner);

    lua.pushFunction(function);
    try lua.protectedCall(0, 0, 0);

    lua.pushFunction(function);
    lua.pushInteger(10);
    _ = lua.pushString("zig");
    lua.pushNumber(1.23);
    _ = lua.pushStringZ("lang");
    try lua.protectedCall(4, 0, 0);
}

test "checkOption" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const Variant = enum {
        one,
        two,
        three,
    };

    const function = zigluau.wrap(struct {
        fn inner(l: *Lua) i32 {
            const option = l.checkOption(Variant, 1, .one);
            l.pushInteger(switch (option) {
                .one => 1,
                .two => 2,
                .three => 3,
            });
            return 1;
        }
    }.inner);

    lua.pushFunction(function);
    _ = lua.pushStringZ("one");
    try lua.protectedCall(1, 1, 0);
    try expectEqual(1, try lua.toInteger(-1));
    lua.pop(1);

    lua.pushFunction(function);
    _ = lua.pushStringZ("two");
    try lua.protectedCall(1, 1, 0);
    try expectEqual(2, try lua.toInteger(-1));
    lua.pop(1);

    lua.pushFunction(function);
    _ = lua.pushStringZ("three");
    try lua.protectedCall(1, 1, 0);
    try expectEqual(3, try lua.toInteger(-1));
    lua.pop(1);

    // try the default now
    lua.pushFunction(function);
    try lua.protectedCall(0, 1, 0);
    try expectEqual(1, try lua.toInteger(-1));
    lua.pop(1);

    // check the raised error
    lua.pushFunction(function);
    _ = lua.pushStringZ("unknown");
    try expectError(error.Runtime, lua.protectedCall(1, 1, 0));
    try expectStringContains("(invalid option 'unknown')", try lua.toString(-1));
}

test "where" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const whereFn = zigluau.wrap(struct {
        fn inner(l: *Lua) i32 {
            l.where(1);
            return 1;
        }
    }.inner);

    lua.pushFunction(whereFn);
    lua.setGlobal("whereFn");

    try lua.doString(
        \\
        \\ret = whereFn()
    );

    _ = try lua.getGlobal("ret");
    try expectEqualStrings("[string \"...\"]:2: ", try lua.toString(-1));
}

test "ref luau" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.pushNil();
    try expectError(error.Fail, lua.ref(1));
    try expectEqual(1, lua.getTop());

    // In luau lua.ref does not pop the item from the stack
    // and the data is stored in the registry_index by default
    _ = lua.pushString("Hello there");
    const ref = try lua.ref(2);

    _ = lua.rawGetIndex(zigluau.registry_index, ref);
    try expectEqualStrings("Hello there", try lua.toString(-1));

    lua.unref(ref);
}

test "metatables" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString("f = function() return 10 end");

    try lua.newMetatable("mt");
    // set the len metamethod to the function f
    _ = try lua.getGlobal("f");
    lua.setField(1, "__len");

    lua.newTable();
     _ = lua.getField(zigluau.registry_index, "mt");
	lua.setMetatable(-2);

    try lua.callMeta(-1, "__len");
    try expectEqual(10, try lua.toNumber(-1));
}

test "args and errors" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const argCheck = zigluau.wrap(struct {
        fn inner(l: *Lua) i32 {
            l.argCheck(false, 1, "error!");
            return 0;
        }
    }.inner);

    lua.pushFunction(argCheck);
    try expectError(error.Runtime, lua.protectedCall(0, 0, 0));

    const raisesError = zigluau.wrap(struct {
        fn inner(l: *Lua) i32 {
            l.raiseErrorStr("some error %s!", .{"zig"});
            unreachable;
        }
    }.inner);

    lua.pushFunction(raisesError);
    try expectError(error.Runtime, lua.protectedCall(0, 0, 0));
    try expectEqualStrings("some error zig!", try lua.toString(-1));
}

test "userdata" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const Type = struct { a: i32, b: f32 };
    try lua.newMetatable("Type");

    const checkUdata = zigluau.wrap(struct {
        fn inner(l: *Lua) i32 {
            const ptr = l.checkUserdata(Type, 1, "Type");
            if (ptr.a != 1234) {
                _ = l.pushString("error!");
                l.raiseError();
            }
            if (ptr.b != 3.14) {
                _ = l.pushString("error!");
                l.raiseError();
            }
            return 1;
        }
    }.inner);

    lua.pushFunction(checkUdata);

    {
        var t = lua.newUserdata(Type);
        _ = lua.getField(zigluau.registry_index, "Type");
        lua.setMetatable(-2);

        t.a = 1234;
        t.b = 3.14;

        // call checkUdata asserting that the udata passed in with the
        // correct metatable and values
        try lua.protectedCall(1, 1, 0);
    }
}

test "userdata slices" {
    const Integer = zigluau.Integer;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.newMetatable("FixedArray");

    // create an array of 10
    const slice = lua.newUserdataSlice(Integer, 10);
    _ = lua.getField(zigluau.registry_index, "FixedArray");
    lua.setMetatable(-2);

    for (slice, 1..) |*item, index| {
        item.* = @intCast(index);
    }

    const udataFn = struct {
        fn inner(l: *Lua) i32 {
            _ = l.checkUserdataSlice(Integer, 1, "FixedArray");

            _ = l.testUserdataSlice(Integer, 1, "FixedArray") catch unreachable;

            const arr = l.toUserdataSlice(Integer, 1) catch unreachable;
            for (arr, 1..) |item, index| {
                if (item != index) l.raiseErrorStr("something broke!", .{});
            }

            return 0;
        }
    }.inner;

    lua.pushFunction(zigluau.wrap(udataFn));
    lua.pushValue(2);

    try lua.protectedCall(1, 0, 0);
}

test "function environments" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString("function test() return x end");

    // set the global _G.x to be 10
    lua.pushInteger(10);
    lua.setGlobal("x");

    _ = try lua.getGlobal("test");
    try lua.protectedCall(0, 1, 0);
    try testing.expectEqual(10, lua.toInteger(1));
    lua.pop(1);

    // now set the functions table to have a different value of x
    _ = try lua.getGlobal("test");
    lua.newTable();
    lua.pushInteger(20);
    lua.setField(2, "x");
    try lua.setFnEnvironment(1);

    try lua.protectedCall(0, 1, 0);
    try testing.expectEqual(20, lua.toInteger(1));
    lua.pop(1);

    _ = try lua.getGlobal("test");
    lua.getFnEnvironment(1);
    _ = lua.getField(2, "x");
    try testing.expectEqual(20, lua.toInteger(3));
}

test "objectLen" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    _ = lua.pushStringZ("lua");
    try testing.expectEqual(3, lua.objectLen(-1));
}

// Debug Library
test "debug interface" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString(
        \\f = function(x)
        \\  local y = x * 2
        \\  y = y + 2
        \\  return x + y
        \\end
    );
    _ = try lua.getGlobal("f");

    var info: DebugInfo = undefined;

    lua.getInfo(-1, .{
        .l = true,
        .s = true,
        .n = true,
        .u = true,
    }, &info);

    // get information about the function
    try expectEqual(.lua, info.what);
    const len = std.mem.len(@as([*:0]u8, @ptrCast(&info.short_src)));
    try expectEqual(1, info.first_line_defined);

    try expectEqual(1, info.current_line);
    try expectEqualStrings("[string \"...\"]", info.short_src[0..len]);
}

test "debug upvalues" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString(
        \\f = function(x)
        \\  return function(y)
        \\    return x + y
        \\  end
        \\end
        \\addone = f(1)
    );
    _ = try lua.getGlobal("addone");

    // index doesn't exist
    try expectError(error.Fail, lua.getUpvalue(1, 2));

    // inspect the upvalue (should be x)
    try expectEqualStrings("", try lua.getUpvalue(-1, 1));
    try expectEqual(1, try lua.toNumber(-1));
    lua.pop(1);

    // now make the function an "add five" function
    lua.pushNumber(5);
    _ = try lua.setUpvalue(-2, 1);

    // call the new function (should return 7)
    lua.pushNumber(2);
    try lua.protectedCall(1, 1, 0);
    try expectEqual(7, try lua.toNumber(-1));
}

test "compile and run bytecode" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();
    lua.openLibs();

    // Load bytecode
    const src = "return 133";
    const bc = try zigluau.compile(testing.allocator, src, zigluau.CompileOptions{});
    defer testing.allocator.free(bc);

    try lua.loadBytecode("...", bc);
    try lua.protectedCall(0, 1, 0);
    const v = try lua.toInteger(-1);
    try expectEqual(133, v);

    // Try mutable globals.  Calls to mutable globals should produce longer bytecode.
    const src2 = "Foo.print()\nBar.print()";
    const bc1 = try zigluau.compile(testing.allocator, src2, zigluau.CompileOptions{});
    defer testing.allocator.free(bc1);

    const options = zigluau.CompileOptions{
        .mutable_globals = &[_:null]?[*:0]const u8{ "Foo", "Bar" },
    };
    const bc2 = try zigluau.compile(testing.allocator, src2, options);
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

    // create a Lua-owned pointer to a Data, configure Data with a destructor.
    {
        var lua = try Lua.init(testing.allocator);
        defer lua.deinit(); // forces dtors to be called at the latest

        var data = lua.newUserdataDtor(Data, zigluau.wrap(Data.dtor));
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

test "tagged userdata" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit(); // forces dtors to be called at the latest

    const Data = struct {
        val: i32,
    };

    // create a Lua-owned tagged pointer
    var data = lua.newUserdataTagged(Data, 13);
    data.val = 1;

    const data2 = try lua.toUserdataTagged(Data, -1, 13);
    try testing.expectEqual(data.val, data2.val);

    var tag = try lua.userdataTag(-1);
    try testing.expectEqual(13, tag);

    lua.setUserdataTag(-1, 100);
    tag = try lua.userdataTag(-1);
    try testing.expectEqual(100, tag);

    // Test that tag mismatch error handling works.  Userdata is not tagged with 123.
    try expectError(error.Fail, lua.toUserdataTagged(Data, -1, 123));

    // should not fail
    _ = try lua.toUserdataTagged(Data, -1, 100);

    // Integer is not userdata, so userdataTag should fail.
    lua.pushInteger(13);
    try expectError(error.Fail, lua.userdataTag(-1));
}

fn vectorCtor(l: *Lua) i32 {
    const x = l.toNumber(1) catch unreachable;
    const y = l.toNumber(2) catch unreachable;
    const z = l.toNumber(3) catch unreachable;
    if (zigluau.luau_vector_size == 4) {
        const w = l.optNumber(4, 0);
        l.pushVector(@floatCast(x), @floatCast(y), @floatCast(z), @floatCast(w));
    } else {
        l.pushVector(@floatCast(x), @floatCast(y), @floatCast(z));
    }
    return 1;
}

test "luau vectors" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();
    lua.openLibs();
    lua.register("vector", zigluau.wrap(vectorCtor));

    try lua.doString(
        \\function test()
        \\  local a = vector(1, 2, 3)
        \\  local b = vector(4, 5, 6)
        \\  local c = (a + b) * vector(2, 2, 2)
        \\  return vector(c.x, c.y, c.z)
        \\end
    );
    _ = try lua.getGlobal("test");
    try lua.protectedCall(0, 1, 0);
    var v = try lua.toVector(-1);
    try testing.expectEqualSlices(f32, &[3]f32{ 10, 14, 18 }, v[0..3]);

    if (zigluau.luau_vector_size == 3) lua.pushVector(1, 2, 3) else lua.pushVector(1, 2, 3, 4);
    try expect(lua.isVector(-1));
    v = try lua.toVector(-1);
    const expected = if (zigluau.luau_vector_size == 3) [3]f32{ 1, 2, 3 } else [4]f32{ 1, 2, 3, 4 };
    try expectEqual(expected, v);
    try expectEqualStrings("vector", lua.typeNameIndex(-1));

    lua.pushInteger(5);
    try expect(!lua.isVector(-1));
}

test "luau 4-vectors" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();
    lua.openLibs();
    lua.register("vector", zigluau.wrap(vectorCtor));

    // More specific 4-vector tests
    if (zigluau.luau_vector_size == 4) {
        try lua.doString(
            \\local a = vector(1, 2, 3, 4)
            \\local b = vector(5, 6, 7, 8)
            \\return a + b
        );
        const vec4 = try lua.toVector(-1);
        try expectEqual([4]f32{ 6, 8, 10, 12 }, vec4);
    }
}

test "useratom" {
    const useratomCb = struct {
        pub fn inner(str: []const u8) i16 {
            if (std.mem.eql(u8, str, "method_one")) {
                return 0;
            } else if (std.mem.eql(u8, str, "another_method")) {
                return 1;
            }
            return -1;
        }
    }.inner;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();
    lua.setUserAtomCallbackFn(zigluau.wrap(useratomCb));

    _ = lua.pushStringZ("unknownatom");
    _ = lua.pushStringZ("method_one");
    _ = lua.pushStringZ("another_method");

    const atom_idx0, const str0 = try lua.toStringAtom(-2);
    const atom_idx1, const str1 = try lua.toStringAtom(-1);
    const atom_idx2, const str2 = try lua.toStringAtom(-3);
    try testing.expect(std.mem.eql(u8, str0, "method_one"));
    try testing.expect(std.mem.eql(u8, str1, "another_method"));
    try testing.expect(std.mem.eql(u8, str2, "unknownatom")); // should work, but returns -1 for atom idx

    try expectEqual(0, atom_idx0);
    try expectEqual(1, atom_idx1);
    try expectEqual(-1, atom_idx2);

    lua.pushInteger(13);
    try expectError(error.Fail, lua.toStringAtom(-1));
}

test "namecall" {
    const funcs = struct {
        const dot_idx: i32 = 0;
        const sum_idx: i32 = 1;

        // The useratom callback to initially form a mapping from method names to
        // integer indices. The indices can then be used to quickly dispatch the right
        // method in namecalls without needing to perform string compares.
        pub fn useratomCb(str: []const u8) i16 {
            if (std.mem.eql(u8, str, "dot")) {
                return dot_idx;
            }
            if (std.mem.eql(u8, str, "sum")) {
                return sum_idx;
            }
            return -1;
        }

        pub fn vectorNamecall(l: *Lua) i32 {
            const atom_idx, _ = l.namecallAtom() catch {
                l.raiseErrorStr("%s is not a valid vector method", .{l.checkString(1).ptr});
            };
            switch (atom_idx) {
                dot_idx => {
                    const a = l.checkVector(1);
                    const b = l.checkVector(2);
                    l.pushNumber(a[0] * b[0] + a[1] * b[1] + a[2] * b[2]); // vec3 dot
                    return 1;
                },
                sum_idx => {
                    const a = l.checkVector(1);
                    l.pushNumber(a[0] + a[1] + a[2]);
                    return 1;
                },
                else => unreachable,
            }
        }
    };

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();
    lua.setUserAtomCallbackFn(zigluau.wrap(funcs.useratomCb));

    lua.register("vector", zigluau.wrap(vectorCtor));
    lua.pushVector(0, 0, 0);

    try lua.newMetatable("vector");
    _ = lua.pushStringZ("__namecall");
    lua.pushFunctionNamed(zigluau.wrap(funcs.vectorNamecall), "vector_namecall");
    lua.setTable(-3);

    lua.setReadonly(-1, true);
    lua.setMetatable(-2);

    // Vector setup, try some lua code on them.
    try lua.doString(
        \\local a = vector(1, 2, 3)
        \\local b = vector(3, 2, 1)
        \\return a:dot(b)
    );
    const d = try lua.toNumber(-1);
    lua.pop(-1);
    try expectEqual(10, d);

    try lua.doString(
        \\local a = vector(1, 2, 3)
        \\return a:sum()
    );
    const s = try lua.toNumber(-1);
    lua.pop(-1);
    try expectEqual(6, s);
}

test "toAny" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    //int
    lua.pushInteger(100);
    const my_int = try lua.toAny(i32, -1);
    try testing.expect(my_int == 100);

    //bool
    lua.pushBoolean(true);
    const my_bool = try lua.toAny(bool, -1);
    try testing.expect(my_bool);

    //float
    lua.pushNumber(100.0);
    const my_float = try lua.toAny(f32, -1);
    try testing.expect(my_float == 100.0);

    //[]const u8
    _ = lua.pushStringZ("hello world");
    const my_string_1 = try lua.toAny([]const u8, -1);
    try testing.expect(std.mem.eql(u8, my_string_1, "hello world"));

    //[:0]const u8
    _ = lua.pushStringZ("hello world");
    const my_string_2 = try lua.toAny([:0]const u8, -1);
    try testing.expect(std.mem.eql(u8, my_string_2, "hello world"));

    //[*:0]const u8
    _ = lua.pushStringZ("hello world");
    const my_string_3 = try lua.toAny([*:0]const u8, -1);
    const end = std.mem.indexOfSentinel(u8, 0, my_string_3);
    try testing.expect(std.mem.eql(u8, my_string_3[0..end], "hello world"));

    //ptr
    var my_value: i32 = 100;
    _ = lua.pushLightUserdata(&my_value);
    const my_ptr = try lua.toAny(*i32, -1);
    try testing.expect(my_ptr.* == my_value);

    //optional
    lua.pushNil();
    const maybe = try lua.toAny(?i32, -1);
    try testing.expect(maybe == null);

    //enum
    const MyEnumType = enum { hello, goodbye };
    _ = lua.pushStringZ("hello");
    const my_enum = try lua.toAny(MyEnumType, -1);
    try testing.expect(my_enum == MyEnumType.hello);

    //void
    try lua.doString("value = {}\nvalue_err = {a = 5}");
    _ = try lua.getGlobal("value");
    try testing.expectEqual(void{}, try lua.toAny(void, -1));
    _ = try lua.getGlobal("value_err");
    try testing.expectError(error.VoidTableIsNotEmpty, lua.toAny(void, -1));
}

test "toAny struct" {
//     var lua = try Lua.init(testing.allocator);
//     defer lua.deinit();

//     const MyType = struct {
//         foo: i32,
//         bar: bool,
//         bizz: []const u8 = "hi",
//     };
//     try lua.doString("value = {[\"foo\"] = 10, [\"bar\"] = false}");
//     const lua_type = try lua.getGlobal("value");
//     try testing.expect(lua_type == .table);
//     const my_struct = try lua.toAny(MyType, 1);
//     try testing.expect(std.meta.eql(
//         my_struct,
//         MyType{ .foo = 10, .bar = false },
//     ));
}

test "toAny struct recursive" {
//     var lua = try Lua.init(testing.allocator);
//     defer lua.deinit();

//     const MyType = struct {
//         foo: i32 = 10,
//         bar: bool = false,
//         bizz: []const u8 = "hi",
//         meep: struct { a: ?i7 = null } = .{},
//     };

//     try lua.doString(
//         \\value = {
//         \\  ["foo"] = 10,
//         \\  ["bar"] = false,
//         \\  ["bizz"] = "hi",
//         \\  ["meep"] = {
//         \\    ["a"] = nil
//         \\  }
//         \\}
//     );

//     _ = try lua.getGlobal("value");
//     const my_struct = try lua.toAny(MyType, -1);
//     try testing.expectEqualDeep(MyType{}, my_struct);
}

test "toAny tagged union" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const MyType = union(enum) {
        a: i32,
        b: bool,
        c: []const u8,
        d: struct { t0: f64, t1: f64 },
    };

    try lua.doString(
        \\value0 = {
        \\  ["c"] = "Hello, world!",
        \\}
        \\value1 = {
        \\  ["d"] = {t0 = 5.0, t1 = -3.0},
        \\}
        \\value2 = {
        \\  ["a"] = 1000,
        \\}
    );

    _ = try lua.getGlobal("value0");
    const my_struct0 = try lua.toAny(MyType, -1);
    try testing.expectEqualDeep(MyType{ .c = "Hello, world!" }, my_struct0);

    _ = try lua.getGlobal("value1");
    const my_struct1 = try lua.toAny(MyType, -1);
    try testing.expectEqualDeep(MyType{ .d = .{ .t0 = 5.0, .t1 = -3.0 } }, my_struct1);

    _ = try lua.getGlobal("value2");
    const my_struct2 = try lua.toAny(MyType, -1);
    try testing.expectEqualDeep(MyType{ .a = 1000 }, my_struct2);
}

test "toAny slice" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const program =
        \\list = {1, 2, 3, 4, 5}
    ;
    try lua.doString(program);
    _ = try lua.getGlobal("list");
    const sliced = try lua.toAnyAlloc([]u32, -1);
    defer sliced.deinit();

    try testing.expect(
        std.mem.eql(u32, &[_]u32{ 1, 2, 3, 4, 5 }, sliced.value),
    );
}

test "toAny array" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const arr: [5]?u32 = .{ 1, 2, null, 4, 5 };
    const program =
        \\array= {1, 2, nil, 4, 5}
    ;
    try lua.doString(program);
    _ = try lua.getGlobal("array");
    const array = try lua.toAny([5]?u32, -1);
    try testing.expectEqual(arr, array);
}

test "toAny vector" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const vec = @Vector(4, bool){ true, false, false, true };
    const program =
        \\vector= {true, false, false, true}
    ;
    try lua.doString(program);
    _ = try lua.getGlobal("vector");
    const vector = try lua.toAny(@Vector(4, bool), -1);
    try testing.expectEqual(vec, vector);
}

test "pushAny" {
//     var lua = try Lua.init(testing.allocator);
//     defer lua.deinit();

//     //int
//     try lua.pushAny(1);
//     const my_int = try lua.toInteger(-1);
//     try testing.expect(my_int == 1);

//     //float
//     try lua.pushAny(1.0);
//     const my_float = try lua.toNumber(-1);
//     try testing.expect(my_float == 1.0);

//     //bool
//     try lua.pushAny(true);
//     const my_bool = lua.toBoolean(-1);
//     try testing.expect(my_bool);

//     //string literal
//     try lua.pushAny("hello world");
//     const value = try lua.toString(-1);
//     const end = std.mem.indexOfSentinel(u8, 0, value);
//     try testing.expect(std.mem.eql(u8, value[0..end], "hello world"));

//     //null
//     try lua.pushAny(null);
//     try testing.expect(try lua.toAny(?f32, -1) == null);

//     //optional
//     const my_optional: ?i32 = -1;
//     try lua.pushAny(my_optional);
//     try testing.expect(try lua.toAny(?i32, -1) == my_optional);

//     //enum
//     const MyEnumType = enum { hello, goodbye };
//     try lua.pushAny(MyEnumType.goodbye);
//     const my_enum = try lua.toAny(MyEnumType, -1);
//     try testing.expect(my_enum == MyEnumType.goodbye);

//     //void
//     try lua.pushAny(void{});
//     try testing.expectEqual(void{}, try lua.toAny(void, -1));
}

test "pushAny struct" {
//     var lua = try Lua.init(testing.allocator);
//     defer lua.deinit();

//     const MyType = struct {
//         foo: i32 = 1,
//         bar: bool = false,
//         bizz: []const u8 = "hi",
//     };
//     try lua.pushAny(MyType{});
//     const value = try lua.toAny(MyType, -1);
//     try testing.expect(std.mem.eql(u8, value.bizz, (MyType{}).bizz));
//     try testing.expect(value.foo == (MyType{}).foo);
//     try testing.expect(value.bar == (MyType{}).bar);
}

test "pushAny tagged union" {
//     var lua = try Lua.init(testing.allocator);
//     defer lua.deinit();

//     const MyType = union(enum) {
//         a: i32,
//         b: bool,
//         c: []const u8,
//         d: struct { t0: f64, t1: f64 },
//     };

//     const t0 = MyType{ .d = .{ .t0 = 5.0, .t1 = -3.0 } };
//     try lua.pushAny(t0);
//     const value0 = try lua.toAny(MyType, -1);
//     try testing.expectEqualDeep(t0, value0);

//     const t1 = MyType{ .c = "Hello, world!" };
//     try lua.pushAny(t1);
//     const value1 = try lua.toAny(MyType, -1);
//     try testing.expectEqualDeep(t1, value1);
}

test "pushAny toAny slice/array/vector" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    var my_array = [_]u32{ 1, 2, 3, 4, 5 };
    const my_slice: []u32 = my_array[0..];
    const my_vector: @Vector(5, u32) = .{ 1, 2, 3, 4, 5 };
    try lua.pushAny(my_slice);
    try lua.pushAny(my_array);
    try lua.pushAny(my_vector);
    const vector = try lua.toAny(@TypeOf(my_vector), -1);
    const array = try lua.toAny(@TypeOf(my_array), -2);
    const slice = try lua.toAnyAlloc(@TypeOf(my_slice), -3);
    defer slice.deinit();

    try testing.expectEqual(my_array, array);
    try testing.expectEqualDeep(my_slice, slice.value);
    try testing.expectEqual(my_vector, vector);
}

fn foo(a: i32, b: i32) i32 {
    return a + b;
}

fn bar(a: i32, b: i32) !i32 {
    if (a > b) return error.wrong;
    return a + b;
}

test "autoPushFunction" {
//     var lua = try Lua.init(testing.allocator);
//     defer lua.deinit();
//     lua.openLibs();

//     lua.autoPushFunction(foo);
//     lua.setGlobal("foo");

//     lua.autoPushFunction(bar);
//     lua.setGlobal("bar");

//     try lua.doString(
//         \\result = foo(1, 2)
//     );
//     try lua.doString(
//         \\local status, result = pcall(bar, 1, 2)
//     );

//     //automatic api construction
//     const my_api = .{
//         .foo = foo,
//         .bar = bar,
//     };

//     try lua.pushAny(my_api);
//     lua.setGlobal("api");

//     try lua.doString(
//         \\api.foo(1, 2)
//     );
}

test "autoCall" {
//     var lua = try Lua.init(testing.allocator);
//     defer lua.deinit();

//     const program =
//         \\function add(a, b)
//         \\   return a + b
//         \\end
//     ;

//     try lua.doString(program);

//     for (0..100) |_| {
//         const sum = try lua.autoCall(usize, "add", .{ 1, 2 });
//         try std.testing.expect(3 == sum);
//     }

//     for (0..100) |_| {
//         const sum = try lua.autoCallAlloc(usize, "add", .{ 1, 2 });
//         defer sum.deinit();
//         try std.testing.expect(3 == sum.value);
//     }
}

test "autoCall stress test" {
//     var lua = try Lua.init(testing.allocator);
//     defer lua.deinit();

//     const program =
//         \\function add(a, b)
//         \\   return a + b
//         \\end
//         \\
//         \\
//         \\function KeyBindings()
//         \\
//         \\   local bindings = {
//         \\      {['name'] = 'player_right', ['key'] = 'a'},
//         \\      {['name'] = 'player_left',  ['key'] = 'd'},
//         \\      {['name'] = 'player_up',    ['key'] = 'w'},
//         \\      {['name'] = 'player_down',  ['key'] = 's'},
//         \\      {['name'] = 'zoom_in',      ['key'] = '='},
//         \\      {['name'] = 'zoom_out',     ['key'] = '-'},
//         \\      {['name'] = 'debug_mode',   ['key'] = '/'},
//         \\   }
//         \\
//         \\   return bindings
//         \\end
//     ;

//     try lua.doString(program);

//     const ConfigType = struct {
//         name: []const u8,
//         key: []const u8,
//         shift: bool = false,
//         control: bool = false,
//     };

//     for (0..100) |_| {
//         const sum = try lua.autoCallAlloc([]ConfigType, "KeyBindings", .{});
//         defer sum.deinit();
//     }
}

test "get set" {
//     var lua = try Lua.init(testing.allocator);
//     defer lua.deinit();

//     try lua.set("hello", true);
//     try testing.expect(try lua.get(bool, "hello"));

//     try lua.set("world", 1000);
//     try testing.expect(try lua.get(u64, "world") == 1000);

//     try lua.set("foo", 'a');
//     try testing.expect(try lua.get(u8, "foo") == 'a');
}

test "array of strings" {
//     var lua = try Lua.init(testing.allocator);
//     defer lua.deinit();

//     const program =
//         \\function strings()
//         \\   return {"hello", "world", "my name", "is foobar"}
//         \\end
//     ;

//     try lua.doString(program);

//     for (0..100) |_| {
//         const strings = try lua.autoCallAlloc([]const []const u8, "strings", .{});
//         defer strings.deinit();
//     }
}
