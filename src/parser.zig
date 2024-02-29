const std = @import("std");
const file = @embedFile("python.peg");
const tokenizer = @import("./tokenizer.zig");

// idea 1: dynamically created module
// rejected!

fn token_type_from_string(contents: []const u8) tokenizer.TokenType {
    const tokens = tokenizer.comptime_tokenize(contents, 1) catch unreachable;
    return tokens[0].type;
}

const plus = token_type_from_string("+");

// idea 2: pass through current PEG grammar being parsed (only at comptime)
pub fn parse() void {
    std.log.info("{any}", .{plus});
}
