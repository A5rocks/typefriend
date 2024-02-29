const std = @import("std");
const tokenizer = @import("./tokenizer.zig");
const parser = @import("./parser.zig");

pub fn main() !void {
    parser.parse();
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // const allocator = gpa.allocator();
    // defer {
    //     const deinit_status = gpa.deinit();
    //     if (deinit_status == .leak) @panic("leaked");
    // }

    // var file = try std.fs.cwd().openFile("test.py", .{});
    // defer file.close();

    // const file_size = try file.getEndPos();
    // if (file_size > std.math.maxInt(u32)) {
    //     // too big!
    //     // todo: error
    //     std.log.warn("file too big", .{});
    //     return;
    // }

    // const contents = try allocator.alloc(u8, file_size);
    // defer allocator.free(contents);
    // const bytes_read = try file.readAll(contents);
    // std.debug.assert(bytes_read == file_size);

    // var timer = try std.time.Timer.start();
    // var tokens = try tokenizer.tokenize(contents, allocator);
    // std.log.info("tokenized {} tokens (took {}ns)", .{ tokens.items.len, timer.read() });

    // var token_idx: u32 = 0;
    // for (0.., contents) |i, char| {
    //     while (token_idx < tokens.items.len and tokens.items[token_idx].start == i) {
    //         std.debug.print("|", .{});
    //         token_idx += 1;
    //     }
    //     std.debug.print("{c}", .{char});
    // }

    // for (tokens.items) |token| {
    //     if (token.type == .Unknown) {
    //         std.log.warn("unknown found", .{});
    //     }
    // }
    // tokens.deinit();
}

// make zig realize `tokenizer` exists for `zig build test`.
test "test tokenizer" {
    _ = tokenizer;
}
