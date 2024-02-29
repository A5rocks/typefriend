const std = @import("std");
const tokenizer = @import("./tokenizer.zig");

const py = @cImport({
    // build for CPython 3.7+
    // for some reason this doesn't let me instantiate type objs
    // @cDefine("Py_LIMITED_API", "0x03070000");
    @cDefine("PY_SSIZE_T_CLEAN", "");
    @cInclude("Python.h");
});

const TokenObject = extern struct {
    ob_base: py.PyObject,
    // todo: is it possible to keep a struct in this struct
    //       without it being extern? (some opaque type?)
    token: tokenizer.Token
};

fn token_repr(self_: [*c]py.PyObject) callconv(.C) ?*py.PyObject {
    const self: *TokenObject = @ptrCast(self_);
    const tag: [*c]const u8 = @tagName(self.token.type);
    return py.PyUnicode_FromFormat("<%s start=%u end=%u>", tag, self.token.start, self.token.end);
}

var Token = py.PyTypeObject{
    .ob_base = .{
        .ob_base = .{},
        .ob_size = 0,
    },
    .tp_name = "typefriend.Token",
    .tp_doc = py.PyDoc_STR("Tokenized piece of Python syntax."),
    .tp_basicsize = @sizeOf(TokenObject),
    .tp_itemsize = 0,
    .tp_flags = py.Py_TPFLAGS_DEFAULT,
    .tp_repr = token_repr,
};

const module_base = py.PyModuleDef_Base{ .ob_base = py.PyObject{ .ob_refcnt = 1, .ob_type = null } };

fn typefriend_tokenize(self: [*c]py.PyObject, args: [*c]py.PyObject) callconv(.C) ?*py.PyObject {
    _ = self;
    var code: [*:0]u8 = undefined;
    if (py.PyArg_ParseTuple(args, "s", &code) == 0) {
        return null;
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("leaked memory");
    }

    // todo: do a proper error
    // todo: I could probably release GIL around this?
    const tokens = tokenizer.tokenize(std.mem.sliceTo(code, 0), allocator) catch unreachable;
    defer tokens.deinit();
    const list = py.PyList_New(@intCast(tokens.items.len));
    
    for (tokens.items, 0..) |token, i| {
        // ugh, this sucks; surely there's a way to allocate all this at once?
        // (also this surely isn't in the stable api. oops)
        var obj: *TokenObject = @ptrCast(py._PyObject_New(@ptrCast(&Token)));
        obj.token = token;
        if (py.PyList_SetItem(list, @intCast(i), @ptrCast(obj)) == -1) {
            return null;
        }
    }

    return list;
}

var methods = [_:py.PyMethodDef{}]py.PyMethodDef{
    .{.ml_name = "tokenize", .ml_meth = typefriend_tokenize, .ml_flags = py.METH_VARARGS, .ml_doc = "Tokenize given Python code."}
};

var module = py.PyModuleDef{
    .m_base = module_base,
    .m_name = "typefriend",
    .m_doc = "Friendly embeddable typechecker",
    .m_size = -1,
    .m_methods = &methods,
};

export fn PyInit_typefriend() callconv(.C) ?*py.PyObject {
    if (py.PyType_Ready(&Token) < 0) {
        return null;
    }

    const m = py.PyModule_Create(&module);
    if (m == null) {
        return null;
    }

    py.Py_IncRef(@ptrCast(&Token));
    if (py.PyModule_AddObject(m, "Token", @ptrCast(&Token)) < 0) {
        // todo: make a helper function to do equiv of Py_DECREF
        py.Py_DecRef(@ptrCast(&Token));
        py.Py_DecRef(m);
        return null;
    }

    return m;
}
