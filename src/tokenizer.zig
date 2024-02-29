const std = @import("std");
const ziglyph = @import("ziglyph");

// todo: keep track of errors out of band and have the tokenizer just continue
const LexError = error{
    NonUtf8,
    // UnexpectedEof,
    UnknownCharacter,
    UnknownStringMode,
    UnterminatedString,
    ImproperNesting,
    InvalidNumber,
    UnterminatedNotEquals,
    UnexpectedContinuation,
};

const CharReadError = error{
    Utf8InvalidStartByte,
    Utf8ExpectedContinuation,
    Utf8OverlongEncoding,
    Utf8EncodesSurrogateHalf,
    Utf8CodepointTooLarge,
};

const OOMErrorSet = error{
    OutOfMemory,
};

pub const TokenType = enum(u8) {
    // structure
    EndOfFile,
    EndOfLine,
    NL, // non logical new line
    Indent,
    Dedent,
    Unknown,
    // larger pieces
    Identifier,
    String,
    Float,
    Integer,
    Comment,
    // fstrings
    FStringStart,
    FStringEnd,
    FStringContent,
    // (
    LParen,
    // )
    RParen,
    // :
    Colon,
    // :=
    ColonEquals,
    // {
    LBrace,
    // }
    RBrace,
    // =
    Equals,
    // ==
    EqualsEquals,
    // +
    Plus,
    // +=
    PlusEquals,
    // -
    Minus,
    // -=
    MinusEquals,
    // .
    Dot,
    // ...
    Ellipsis,
    // ,
    Comma,
    // ->
    Arrow,
    // *
    Star,
    // **
    StarStar,
    // *=
    StarEquals,
    // |
    Pipe,
    // |=
    PipeEquals,
    // @
    At,
    // @=
    AtEquals,
    // [
    LBracket,
    // ]
    RBracket,
    // !=
    ExclamationEquals,
    // todo: should this really be tokenized? feels like fstring special thing...
    // ! (as in {5!r})
    Exclamation,
    // <
    LessThan,
    // <=
    LessThanEquals,
    // <<
    LessThanLessThan,
    // >
    GreaterThan,
    // >=
    GreaterThanEquals,
    // >>
    GreaterThanGreaterThan,
    // %
    Percent,
    // %=
    PercentEquals,
    // todo: should this spit out EndOfLine?
    // ;
    Semicolon,
    // /
    Slash,
    // /=
    SlashEquals,
    // ~
    Tilde,
    // &
    Ampersand,
    // &=
    AmpersandEquals,
    // ^
    Caret,
    // ^=
    CaretEquals,

    // soft keywords (note: update `keywords` when updating)
    match,
    case,
    @"_",
    type,

    // keywords (note: update `keywords` when updating)
    False,
    None,
    True,
    @"and",
    as,
    assert,
    @"async",
    @"await",
    @"break",
    class,
    @"continue",
    def,
    del,
    elif,
    @"else",
    except,
    finally,
    @"for",
    from,
    global,
    @"if",
    import,
    in,
    is,
    lambda,
    nonlocal,
    not,
    @"or",
    pass,
    raise,
    @"return",
    @"try",
    @"while",
    with,
    yield
};

const keywords = [_]TokenType{
    // soft keywords
    .match,
    .case,
    .@"_",
    .type,

    // keywords
    .False,
    .None,
    .True,
    .@"and",
    .as,
    .assert,
    .@"async",
    .@"await",
    .@"break",
    .class,
    .@"continue",
    .def,
    .del,
    .elif,
    .@"else",
    .except,
    .finally,
    .@"for",
    .from,
    .global,
    .@"if",
    .import,
    .in,
    .is,
    .lambda,
    .nonlocal,
    .not,
    .@"or",
    .pass,
    .raise,
    .@"return",
    .@"try",
    .@"while",
    .with,
    .yield
};

pub const Token = extern struct { type: TokenType, start: u32, end: u32 };

const StringMode = struct {
    bytes: bool,
    format: bool,
};

const Whitespace = struct { spaces: u32, tabs: u32 };

const Tokenizer = struct {
    contents: []const u8,
    rune: ?u21,
    location: u32,
    nesting: u8,
    tokens: union(enum) {
        array_list: std.ArrayList(Token),
        slice: []Token
    },
    token_count: u32,
    newLineIsLogical: bool,

    fn next(self: *Tokenizer) CharReadError!void {
        errdefer self.rune = null;
        if (self.location + 1 >= self.contents.len) {
            self.location += 1;
            self.rune = null;
            // return LexError.UnexpectedEof;
        } else {
            const len = try std.unicode.utf8ByteSequenceLength(self.contents[self.location + 1]);
            const rune = if (len != 1) try std.unicode.utf8Decode(self.contents[self.location + 1 .. self.location + 1 + len]) else self.contents[self.location + 1];
            self.location += len;
            self.rune = rune;
        }
    }

    fn add_token(self: *Tokenizer, t: TokenType, start: u32, end: u32) void {
        // todo: have an assert that the token is the expected size
        switch (self.tokens) {
            .array_list => |*ts| ts.*.appendAssumeCapacity(.{ .type = t, .start = start, .end = end }),
            .slice => |s| {
                self.token_count += 1;
                s[self.token_count - 1] = .{.type = t, .start = start, .end = end};
            },
        }
        
        self.newLineIsLogical = true;
    }

    fn create(contents: []const u8, allocator: std.mem.Allocator) !Tokenizer {
        // 2 * contents.len an overestimate. but necessary so that we
        // can assume enough capacity in the worst case.
        const tokens = try std.ArrayList(Token).initCapacity(allocator, 2 * contents.len);

        if (contents.len == 0) {
            return Tokenizer{
                .contents = contents,
                .rune = null,
                .location = 0,
                .nesting = 0,
                .tokens = .{
                    .array_list = tokens
                },
                .token_count = 0,
                .newLineIsLogical = false,
            };
        }
        const len = try std.unicode.utf8ByteSequenceLength(contents[0]);
        const rune = try std.unicode.utf8Decode(contents[0..len]);

        return Tokenizer{ .contents = contents, .rune = rune, .location = 0, .nesting = 0, .tokens = .{.array_list = tokens}, .newLineIsLogical = false, .token_count = 0 };
    }

    fn create_comptime(contents: []const u8, into: []Token) !Tokenizer {
        if (contents.len == 0) {
            return Tokenizer{
                .contents = contents,
                .rune = null,
                .location = 0,
                .nesting = 0,
                .tokens = .{
                    .slice = into
                },
                .token_count = 0,
                .newLineIsLogical = false,
            };
        }
        const len = try std.unicode.utf8ByteSequenceLength(contents[0]);
        const rune = try std.unicode.utf8Decode(contents[0..len]);

        return Tokenizer{ .contents = contents, .rune = rune, .location = 0, .nesting = 0, .tokens = .{.slice = into}, .newLineIsLogical = false, .token_count = 0 };
    }

    fn deinit(self: *Tokenizer) void {
        switch (self.tokens) {
            .array_list => |l| l.deinit(),
            .slice => |_| {},
        }
    }

    fn getLastToken(self: *Tokenizer) Token {
        switch (self.tokens) {
            .array_list => |ts| return ts.getLast(),
            .slice => |s| return s[self.token_count - 1]
        }
    }

    fn setLastTokenEnd(self: *Tokenizer, to: u32) void {
        switch (self.tokens) {
            .array_list => |*ts| ts.items[ts.items.len - 1].end = to,
            .slice => |s| s[self.token_count - 1].end = to
        }
    }
};

pub fn tokenize(contents: []const u8, allocator: std.mem.Allocator) !std.ArrayList(Token) {
    // get the encoding cookie
    var offset: u8 = 0;

    if (contents.len >= 3 and std.mem.eql(u8, contents[0..3], "\xef\xbb\xbf")) {
        offset = 3;
    }

    if (!encoding_cookie_is_utf8(contents, offset)) {
        return LexError.NonUtf8;
    }

    var tokenizer = try Tokenizer.create(contents[offset..], allocator);
    errdefer tokenizer.deinit(); // just in case
    var indents = std.ArrayList(Whitespace).init(allocator);
    defer indents.deinit();
    try indents.append(.{ .spaces = 0, .tabs = 0 });

    var indent_buffer: ?Whitespace = null;

    while (tokenizer.rune != null) {
        const whitespace = try next(&tokenizer);
        // todo: is it possible for there to have been 0 tokens?
        if (whitespace != null and tokenizer.getLastToken().type == .EndOfLine and tokenizer.nesting == 0) {
            indent_buffer = whitespace;
        }

        if (tokenizer.getLastToken().type == .EndOfLine and (tokenizer.rune != '#' and tokenizer.rune != ' ' and tokenizer.rune != '\t' and tokenizer.rune != '\r' and tokenizer.rune != '\n')) {
            // todo: this doesn't catch switching tabs out for spaces
            const indent_amount = indent_buffer orelse Whitespace{ .spaces = 0, .tabs = 0 };
            const chars = indent_amount.spaces + indent_amount.tabs;
            while (true) {
                const last_indent = indents.getLast();
                if (last_indent.tabs > indent_amount.tabs or last_indent.spaces > indent_amount.spaces) {
                    _ = indents.pop();
                    tokenizer.add_token(.Dedent, tokenizer.location - chars, tokenizer.location - chars);
                } else if (last_indent.tabs < indent_amount.tabs or last_indent.spaces < indent_amount.spaces) {
                    try indents.append(indent_amount);
                    tokenizer.add_token(.Indent, tokenizer.location - chars, tokenizer.location);
                    break;
                } else {
                    break;
                }
            }
            indent_buffer = null;
        }
    }

    while (true) {
        const last_indent = indents.pop();
        if (last_indent.spaces != 0 or last_indent.tabs != 0) {
            tokenizer.add_token(.Dedent, tokenizer.location, tokenizer.location);
        } else {
            break;
        }
    }
    // not appendAssumeCapacity because it's not linked to a text token
    switch (tokenizer.tokens) {
        .array_list => |*ts| {
            try ts.*.append(.{ .type = .EndOfFile, .start = tokenizer.location, .end = tokenizer.location });
            try ts.*.resize(ts.items.len);

            return ts.*;
        },
        .slice => |_| unreachable,
    }
}

pub fn comptime_tokenize(contents: []const u8, comptime length: comptime_int) ![length]Token {
    var result: [length]Token = undefined;
    var tokenizer = try Tokenizer.create_comptime(contents, &result);

    while (tokenizer.rune != null) {
        const ws = try next(&tokenizer) orelse .{.spaces = 0, .tabs=0};
        if (ws.spaces != 0 or ws.tabs != 0) {
            @compileError("whitespace in front of token");
        }
    }

    if (tokenizer.token_count != length) unreachable;

    return result;
}

fn next(tokenizer: *Tokenizer) !?Whitespace {
    const rune = tokenizer.rune.?;

    switch (rune) {
        'a'...'z', 'A'...'Z', '_', 0x80...std.math.maxInt(u21) => {
            // identifier or prefixed string
            if (rune != '_' and !xid_start(rune)) {
                return LexError.UnknownCharacter;
            }

            const start = tokenizer.location;
            while (true) {
                try tokenizer.next();
                if (tokenizer.rune == null) {
                    // todo: use a trie instead
                    var exited = false;
                    for (keywords) |token_type| {
                        if (std.mem.eql(u8, @tagName(token_type), tokenizer.contents[start..tokenizer.location])) {
                            tokenizer.add_token(token_type, start, tokenizer.location);
                            exited = true;
                            break;
                        }
                    }
                    if (!exited) {
                        tokenizer.add_token(.Identifier, start, tokenizer.location);
                    }
                    break;
                } else if (xid_continue(tokenizer.rune.?)) {
                    // continue token
                } else if (tokenizer.rune == '"' or tokenizer.rune == '\'') {
                    // prefixed string
                    if (tokenizer.location - start > 2) {
                        return LexError.UnknownStringMode;
                    }

                    // todo: possible to make this cleaner?
                    const mode: StringMode = switch (tokenizer.contents[start]) {
                        'r', 'R' => blk: {
                            if (tokenizer.location - start == 1) {
                                break :blk .{ .bytes = false, .format = false };
                            } else {
                                switch (tokenizer.contents[start + 1]) {
                                    'b', 'B' => {
                                        break :blk .{ .bytes = true, .format = false };
                                    },
                                    'f', 'F' => {
                                        break :blk .{ .bytes = false, .format = true };
                                    },
                                    else => {
                                        return LexError.UnknownStringMode;
                                    },
                                }
                            }
                        },
                        'u', 'U' => blk: {
                            if (tokenizer.location - start == 1) {
                                break :blk .{ .bytes = false, .format = false };
                            } else {
                                return LexError.UnknownStringMode;
                            }
                        },
                        'f', 'F' => blk: {
                            if (tokenizer.location - start == 1) {
                                break :blk .{ .bytes = false, .format = true };
                            } else {
                                switch (tokenizer.contents[start + 1]) {
                                    'r', 'R' => {
                                        break :blk .{ .bytes = false, .format = true };
                                    },
                                    else => {
                                        return LexError.UnknownStringMode;
                                    },
                                }
                            }
                        },
                        'b', 'B' => blk: {
                            if (tokenizer.location - start == 1) {
                                break :blk .{ .bytes = true, .format = false };
                            } else {
                                switch (tokenizer.contents[start + 1]) {
                                    'r', 'R' => {
                                        break :blk .{ .bytes = true, .format = false };
                                    },
                                    else => {
                                        return LexError.UnknownStringMode;
                                    },
                                }
                            }
                        },
                        else => {
                            return LexError.UnknownStringMode;
                        },
                    };

                    // todo: should this do the FStringStart thing stdlib does?
                    _ = try tokenize_string(tokenizer, mode, start);
                    break;
                } else {
                    // todo: use a trie instead
                    var exited = false;
                    for (keywords) |token_type| {
                        if (std.mem.eql(u8, @tagName(token_type), tokenizer.contents[start..tokenizer.location])) {
                            tokenizer.add_token(token_type, start, tokenizer.location);
                            exited = true;
                            break;
                        }
                    }
                    if (!exited) {
                        tokenizer.add_token(.Identifier, start, tokenizer.location);
                    }
                    break;
                }
            }
        },
        '0'...'9' => {
            // number
            try tokenize_number(tokenizer, null, false);
        },
        '.' => {
            const loc = tokenizer.location;
            try tokenizer.next();
            if (tokenizer.rune != null and '0' <= tokenizer.rune.? and tokenizer.rune.? <= '9') {
                try tokenize_number(tokenizer, loc, true);
            } else if (tokenizer.rune == '.') {
                const before = tokenizer.location;
                try tokenizer.next();
                if (tokenizer.rune != '.') {
                    tokenizer.add_token(.Dot, loc, before);
                    tokenizer.add_token(.Dot, loc + 1, tokenizer.location);
                } else {
                    try tokenizer.next();
                    tokenizer.add_token(.Ellipsis, loc, tokenizer.location);
                }
            } else {
                tokenizer.add_token(.Dot, loc, tokenizer.location);
            }
        },
        '"', '\'' => {
            const start = tokenizer.location;
            const mode: StringMode = .{ .bytes = false, .format = false };
            try tokenize_string(tokenizer, mode, start);
            tokenizer.add_token(.String, start, tokenizer.location);
        },
        '(' => {
            const start = tokenizer.location;
            tokenizer.nesting += 1;
            try tokenizer.next();
            tokenizer.add_token(.LParen, start, tokenizer.location);
        },
        ')' => {
            if (tokenizer.nesting == 0) {
                return LexError.ImproperNesting;
            }
            const start = tokenizer.location;
            tokenizer.nesting -= 1;
            try tokenizer.next();
            tokenizer.add_token(.RParen, start, tokenizer.location);
        },
        '[' => {
            const start = tokenizer.location;
            tokenizer.nesting += 1;
            try tokenizer.next();
            tokenizer.add_token(.LBracket, start, tokenizer.location);
        },
        ']' => {
            if (tokenizer.nesting == 0) {
                return LexError.ImproperNesting;
            }
            const start = tokenizer.location;
            tokenizer.nesting -= 1;
            try tokenizer.next();
            tokenizer.add_token(.RBracket, start, tokenizer.location);
        },
        '{' => {
            const start = tokenizer.location;
            tokenizer.nesting += 1;
            try tokenizer.next();
            tokenizer.add_token(.LBrace, start, tokenizer.location);
        },
        '}' => {
            if (tokenizer.nesting == 0) {
                return LexError.ImproperNesting;
            }
            const start = tokenizer.location;
            tokenizer.nesting -= 1;
            try tokenizer.next();
            tokenizer.add_token(.RBrace, start, tokenizer.location);
        },
        ':' => {
            const loc = tokenizer.location;
            try tokenizer.next();
            if (tokenizer.rune == '=') {
                try tokenizer.next();
                tokenizer.add_token(.ColonEquals, loc, tokenizer.location);
            } else {
                tokenizer.add_token(.Colon, loc, tokenizer.location);
            }
        },
        '+' => {
            const loc = tokenizer.location;
            try tokenizer.next();
            if (tokenizer.rune == '=') {
                try tokenizer.next();
                tokenizer.add_token(.PlusEquals, loc, tokenizer.location);
            } else {
                tokenizer.add_token(.Plus, loc, tokenizer.location);
            }
        },
        '^' => {
            const loc = tokenizer.location;
            try tokenizer.next();
            if (tokenizer.rune == '=') {
                try tokenizer.next();
                tokenizer.add_token(.CaretEquals, loc, tokenizer.location);
            } else {
                tokenizer.add_token(.Caret, loc, tokenizer.location);
            }
        },
        '&' => {
            const loc = tokenizer.location;
            try tokenizer.next();
            if (tokenizer.rune == '=') {
                try tokenizer.next();
                tokenizer.add_token(.AmpersandEquals, loc, tokenizer.location);
            } else {
                tokenizer.add_token(.Ampersand, loc, tokenizer.location);
            }
        },
        '/' => {
            const loc = tokenizer.location;
            try tokenizer.next();
            if (tokenizer.rune == '=') {
                try tokenizer.next();
                tokenizer.add_token(.SlashEquals, loc, tokenizer.location);
            } else {
                tokenizer.add_token(.Slash, loc, tokenizer.location);
            }
        },
        '%' => {
            const loc = tokenizer.location;
            try tokenizer.next();
            if (tokenizer.rune == '=') {
                try tokenizer.next();
                tokenizer.add_token(.PercentEquals, loc, tokenizer.location);
            } else {
                tokenizer.add_token(.Percent, loc, tokenizer.location);
            }
        },
        '<' => {
            const loc = tokenizer.location;
            try tokenizer.next();
            if (tokenizer.rune == '=') {
                try tokenizer.next();
                tokenizer.add_token(.LessThanEquals, loc, tokenizer.location);
            } else if (tokenizer.rune == '<') {
                try tokenizer.next();
                tokenizer.add_token(.LessThanLessThan, loc, tokenizer.location);
            } else {
                tokenizer.add_token(.LessThan, loc, tokenizer.location);
            }
        },
        '>' => {
            const loc = tokenizer.location;
            try tokenizer.next();
            if (tokenizer.rune == '=') {
                try tokenizer.next();
                tokenizer.add_token(.GreaterThanEquals, loc, tokenizer.location);
            } else if (tokenizer.rune == '>') {
                try tokenizer.next();
                tokenizer.add_token(.GreaterThanGreaterThan, loc, tokenizer.location);
            } else {
                tokenizer.add_token(.GreaterThan, loc, tokenizer.location);
            }
        },
        '*' => {
            const loc = tokenizer.location;
            try tokenizer.next();
            if (tokenizer.rune == '*') {
                try tokenizer.next();
                tokenizer.add_token(.StarStar, loc, tokenizer.location);
            } else if (tokenizer.rune == '=') {
                try tokenizer.next();
                tokenizer.add_token(.StarEquals, loc, tokenizer.location);
            } else {
                tokenizer.add_token(.Star, loc, tokenizer.location);
            }
        },
        '!' => {
            const loc = tokenizer.location;
            try tokenizer.next();
            if (tokenizer.rune == '=') {
                try tokenizer.next();
                tokenizer.add_token(.ExclamationEquals, loc, tokenizer.location);
            } else {
                // return LexError.UnterminatedNotEquals;
                tokenizer.add_token(.Exclamation, loc, tokenizer.location);
            }
        },
        '|' => {
            const loc = tokenizer.location;
            try tokenizer.next();
            if (tokenizer.rune == '=') {
                try tokenizer.next();
                tokenizer.add_token(.PipeEquals, loc, tokenizer.location);
            } else {
                tokenizer.add_token(.Pipe, loc, tokenizer.location);
            }
        },
        // todo: should these just do some math to find the start?
        ';' => {
            const start = tokenizer.location;
            try tokenizer.next();
            tokenizer.add_token(.Semicolon, start, tokenizer.location);
        },
        '~' => {
            const start = tokenizer.location;
            try tokenizer.next();
            tokenizer.add_token(.Tilde, start, tokenizer.location);
        },
        '@' => {
            const loc = tokenizer.location;
            try tokenizer.next();
            if (tokenizer.rune == '=') {
                try tokenizer.next();
                tokenizer.add_token(.AtEquals, loc, tokenizer.location);
            } else {
                tokenizer.add_token(.At, loc, tokenizer.location);
            }
        },

        '-' => {
            const loc = tokenizer.location;
            try tokenizer.next();
            if (tokenizer.rune == '=') {
                try tokenizer.next();
                tokenizer.add_token(.MinusEquals, loc, tokenizer.location);
            } else if (tokenizer.rune == '>') {
                try tokenizer.next();
                tokenizer.add_token(.Arrow, loc, tokenizer.location);
            } else if (tokenizer.rune != null and (tokenizer.rune.? == '.' or ('0' <= tokenizer.rune.? and tokenizer.rune.? <= '9'))) {
                try tokenize_number(tokenizer, loc, false);
            } else {
                tokenizer.add_token(.Minus, loc, tokenizer.location);
            }
        },
        '=' => {
            const loc = tokenizer.location;
            try tokenizer.next();
            if (tokenizer.rune == '=') {
                try tokenizer.next();
                tokenizer.add_token(.EqualsEquals, loc, tokenizer.location);
            } else {
                tokenizer.add_token(.Equals, loc, tokenizer.location);
            }
        },
        ',' => {
            const start = tokenizer.location;
            try tokenizer.next();
            tokenizer.add_token(.Comma, start, tokenizer.location);
        },
        ' ', '\t' => {
            var spaces: u32 = 0;
            var tabs: u32 = 0;
            while (tokenizer.rune == ' ' or tokenizer.rune == '\t') {
                if (tokenizer.rune == ' ') {
                    spaces += 1;
                } else {
                    tabs += 1;
                }

                try tokenizer.next();
            }
            return .{ .spaces = spaces, .tabs = tabs };
        },
        '\\' => {
            try tokenizer.next();
            if (tokenizer.rune != '\r' and tokenizer.rune != '\n') {
                return LexError.UnexpectedContinuation;
            }
            if (tokenizer.rune == '\r') {
                try tokenizer.next();
            }
            if (tokenizer.rune == '\n') {
                try tokenizer.next();
            }
        },
        '\r', '\n' => {
            const start = tokenizer.location;

            // handles \r\n, \n, \r<not \n>
            if (rune == '\r') {
                try tokenizer.next();
            }
            if (tokenizer.rune == '\n') {
                try tokenizer.next();
            }
            if (tokenizer.newLineIsLogical and tokenizer.nesting == 0) {
                tokenizer.add_token(.EndOfLine, start, tokenizer.location);
                tokenizer.newLineIsLogical = false;
            } else {
                tokenizer.add_token(.NL, start, tokenizer.location);
                tokenizer.newLineIsLogical = false;
            }
        },
        '#' => {
            const start = tokenizer.location;
            while (tokenizer.rune != '\r' and tokenizer.rune != '\n' and tokenizer.rune != null) {
                try tokenizer.next();
            }
            const before = tokenizer.newLineIsLogical;
            tokenizer.add_token(.Comment, start, tokenizer.location);
            tokenizer.newLineIsLogical = before;
        },
        else => {
            if (tokenizer.getLastToken().type != .Unknown) {
                tokenizer.add_token(.Unknown, tokenizer.location, tokenizer.location);
            }
            try tokenizer.next();
            tokenizer.setLastTokenEnd(tokenizer.location);
        },
    }

    return null;
}

fn xid_continue(char: u21) bool {
    if (char < 128) {
        return switch (char) {
            '0'...'9' => true,
            'A'...'Z' => true,
            '_' => true,
            'a'...'z' => true,
            else => false,
        };
    } else {
        // todo: get rid of this dependency :(
        return ziglyph.core_properties.isXidContinue(char);
    }
}

fn xid_start(char: u21) bool {
    if (char < 128) {
        return switch (char) {
            'A'...'Z' => true,
            'a'...'z' => true,
            else => false,
        };
    } else {
        // todo get rid of this dependency :(
        return ziglyph.core_properties.isXidStart(char);
    }
}

fn tokenize_number(tokenizer: *Tokenizer, start_loc: ?u32, started_as_point: bool) !void {
    const start = if (start_loc != null) start_loc.? else tokenizer.location;
    var float = started_as_point;
    var encountered_e = false;
    var encountered_point = started_as_point;
    var encountered_radix = false;
    while (true) {
        try tokenizer.next();
        if (tokenizer.rune == null) {
            break;
        }
        switch (tokenizer.rune.?) {
            '0'...'9', 'a', 'A', 'c', 'C', 'd', 'D', 'f', 'F' => {
                // continue
            },
            'e', 'E' => {
                if (encountered_radix) {
                    continue;
                }
                if (encountered_e or encountered_radix) {
                    return LexError.InvalidNumber;
                }
                float = true;
                encountered_e = true;
                try tokenizer.next();
                if (tokenizer.rune == null or (('0' > tokenizer.rune.? or tokenizer.rune.? > '9') and (tokenizer.rune.? != '+' and tokenizer.rune.? != '-'))) {
                    return LexError.InvalidNumber;
                }
            },
            '.' => {
                if (encountered_point or encountered_radix) {
                    return LexError.InvalidNumber;
                }
                float = true;
                encountered_point = true;
                try tokenizer.next();
                if (tokenizer.rune == '_') {
                    return LexError.InvalidNumber;
                }
                if (tokenizer.rune == null or ('0' > tokenizer.rune.? or tokenizer.rune.? > '9') and tokenizer.rune != 'e') {
                    break;
                }
            },
            '_' => {
                try tokenizer.next();
                if (tokenizer.rune == null or '0' > tokenizer.rune.? or tokenizer.rune.? > '9') {
                    return LexError.InvalidNumber;
                }
            },
            'x', 'X', 'o', 'O', 'b', 'B' => {
                if ((tokenizer.rune.? == 'b' or tokenizer.rune.? == 'B') and encountered_radix) {
                    continue;
                }

                // todo: check radix of numbers? also that this is right after start..?
                if (float or encountered_radix) {
                    return LexError.InvalidNumber;
                }
                encountered_radix = true;
                try tokenizer.next();
                if (tokenizer.rune == null or (('0' > tokenizer.rune.? or tokenizer.rune.? > '9') and tokenizer.rune.? != '_' and ('a' > tokenizer.rune.? or 'f' < tokenizer.rune.?))) {
                    std.log.debug("{?}", .{tokenizer.rune});
                    return LexError.InvalidNumber;
                }
            },
            else => {
                break;
            },
        }
    }
    if (float) {
        tokenizer.add_token(.Float, start, tokenizer.location);
    } else {
        tokenizer.add_token(.Integer, start, tokenizer.location);
    }
}

fn tokenize_string(tokenizer: *Tokenizer, mode: StringMode, start_loc: u32) (LexError || CharReadError)!void {
    // basically, this consumes a string (including both end quotes) but then
    // (TODO) returns the string contents! (return type: ![]u8)
    // (or maybe not?)

    const start_quote = tokenizer.rune;
    var start = true;
    var multiline_string = false;
    var quote_count: u8 = 0;
    var last_content = tokenizer.location;
    try tokenizer.next();

    while (tokenizer.rune != start_quote or start or multiline_string) {
        if (multiline_string and tokenizer.rune == start_quote) {
            quote_count += 1;
            if (quote_count == 3) {
                break;
            }
        } else if (multiline_string) {
            quote_count = 0;
        }

        if (tokenizer.rune == start_quote and start) {
            // either "" or a multiline string
            try tokenizer.next();
            if (tokenizer.rune == start_quote) {
                multiline_string = true;
            } else {
                return;
            }
        }

        if (tokenizer.rune == null or ((tokenizer.rune == '\n' or tokenizer.rune == '\r') and !multiline_string)) {
            // uh oh
            return LexError.UnterminatedString;
        } else if (tokenizer.rune == '\\') {
            if (mode.format and start) {
                tokenizer.add_token(.FStringStart, start_loc, tokenizer.location);
                last_content = tokenizer.location;
            }
            start = false;

            // skip next char (might be quote)
            try tokenizer.next();
            if (tokenizer.rune == '\r') {
                try tokenizer.next();
                if (tokenizer.rune == '\n') {
                    try tokenizer.next();
                }
            } else {
                try tokenizer.next();
            }
            continue;
        } else if (tokenizer.rune == '{' and mode.format) {
            if (start) {
                tokenizer.add_token(.FStringStart, start_loc, tokenizer.location);
                last_content = tokenizer.location;
            }
            start = false;

            try tokenizer.next();
            if (tokenizer.rune == '{') {
                // escaped {
                try tokenizer.next();
                continue;
            }
            if (last_content != tokenizer.location - 1) {
                tokenizer.add_token(.FStringContent, last_content, tokenizer.location - 1);
            }
            tokenizer.add_token(.LBrace, tokenizer.location - 1, tokenizer.location);
            try fstring_tokenizer(tokenizer);
            last_content = tokenizer.location;
            continue;
        } //else if (tokenizer.rune == '}' and mode.format) {
        // uhhh, well CPython errors so.
        // ... should I?
        //}

        if (start) {
            tokenizer.add_token(.FStringStart, start_loc, tokenizer.location);
            last_content = tokenizer.location;
        }
        try tokenizer.next();
        start = false;
    }

    // last quote
    try tokenizer.next();
    if (multiline_string and mode.format) {
        if (last_content != tokenizer.location - 3) {
            tokenizer.add_token(.FStringContent, last_content, tokenizer.location - 3);
        }
        tokenizer.add_token(.FStringEnd, tokenizer.location - 3, tokenizer.location);
    } else if (mode.format) {
        if (last_content != tokenizer.location - 1) {
            tokenizer.add_token(.FStringContent, last_content, tokenizer.location - 1);
        }
        tokenizer.add_token(.FStringEnd, tokenizer.location - 1, tokenizer.location);
    }
}

fn fstring_tokenizer(tokenizer: *Tokenizer) !void {
    const nesting = tokenizer.nesting;
    // start an f string eval part
    tokenizer.nesting += 1; // make sure no EOL.
    blk: while (true) {
        if (tokenizer.rune == ':' and tokenizer.nesting == nesting + 1) {
            // format specifier
            while (true) {
                while (tokenizer.rune != '{' and tokenizer.rune != '}' and tokenizer.rune != '\n' and tokenizer.rune != null) {
                    try tokenizer.next();
                }
                if (tokenizer.rune == '\n' or tokenizer.rune == null) {
                    return LexError.UnterminatedString;
                }
                if (tokenizer.rune == '}') {
                    try tokenizer.next();
                    tokenizer.nesting -= 1;
                    break :blk;
                }
                // tokenizer.rune == '{'
                try tokenizer.next();
                // nesting
                try fstring_tokenizer(tokenizer);
            }
        }
        if (tokenizer.rune == '}' and tokenizer.nesting == nesting + 1) {
            // end
            tokenizer.nesting -= 1;
            try tokenizer.next();
            tokenizer.add_token(.RBrace, tokenizer.location - 1, tokenizer.location);
            break;
        }
        if (tokenizer.rune == null) {
            return LexError.UnterminatedString;
        }
        _ = try next(tokenizer);
    }
}

// ugh, but at least it works:
fn encoding_cookie_is_utf8(contents: []const u8, start: u8) bool {
    var started_comment = false;
    var coding_idx: u8 = 0;
    var utf_idx: u8 = 0;
    const CODING = "coding";
    const UTF8 = "utf-8";
    var skip_line = false;
    var current_line: u8 = 1;

    for (contents[start..]) |byte| {
        if (byte == '\n') {
            skip_line = false;
            current_line += 1;
            started_comment = false;
            if (current_line == 3) {
                break;
            }
        } else if (skip_line) {} else if (started_comment and coding_idx < 6) {
            if (byte == CODING[coding_idx]) {
                coding_idx += 1;
            } else {
                coding_idx = 0;
            }
        } else if (started_comment and coding_idx == 6) {
            if (byte == ':' or byte == '=') {
                coding_idx += 1;
            } else {
                coding_idx = 0;
            }
        } else if (started_comment and coding_idx == 7 and (byte != ' ' and byte != '\t')) {
            if (byte == UTF8[utf_idx]) {
                utf_idx += 1;
                if (utf_idx == 5) {
                    return true;
                }
            } else {
                return false;
            }
        } else if (byte == '#') {
            started_comment = true;
        } else if (byte != ' ' and byte != '\t' and byte != 0x0c) {
            skip_line = true;
        }
    }

    return true;
}

test "handles `..` well" {
    const tokens = try tokenize("..", std.testing.allocator);
    defer tokens.deinit();
}

// todo: sublime plugin that can update a snapshot test for me?
fn snapshotTest(src: []const u8, against: []const Token) !void {
    const tokens = try tokenize(src, std.testing.allocator);
    defer tokens.deinit();
    std.testing.expectEqualSlices(Token, against, tokens.items) catch |err| {
        std.debug.print("snapshot (until line with EOF):\n&[_]Token{{\n", .{});
        for (tokens.items) |token| {
            std.debug.print("        .{{.type = .@\"{s}\", .start = {d}, .end = {d}}},\n", .{@tagName(token.type), token.start, token.end});
        }
        std.debug.print("    }}\n", .{});
        std.debug.print("EOF\n", .{});
        return err;
    };
}
test "soft keywords" {
    try snapshotTest("type Integer = int", &[_]Token{
        .{.type = .@"type", .start = 0, .end = 4},
        .{.type = .@"Identifier", .start = 5, .end = 12},
        .{.type = .@"Equals", .start = 13, .end = 14},
        .{.type = .@"Identifier", .start = 15, .end = 18},
        .{.type = .@"EndOfFile", .start = 18, .end = 18},
    });
}

test "keywords" {
    try snapshotTest("if True:\n    pass", &[_]Token{
        .{.type = .@"if", .start = 0, .end = 2},
        .{.type = .@"True", .start = 3, .end = 7},
        .{.type = .@"Colon", .start = 7, .end = 8},
        .{.type = .@"EndOfLine", .start = 8, .end = 9},
        .{.type = .@"Indent", .start = 9, .end = 13},
        .{.type = .@"pass", .start = 13, .end = 17},
        .{.type = .@"Dedent", .start = 17, .end = 17},
        .{.type = .@"EndOfFile", .start = 17, .end = 17},
    });
}

test "f-strings" {
    try snapshotTest("f'hello, {4}!'", &[_]Token{
        .{.type = .@"FStringStart", .start = 0, .end = 2},
        .{.type = .@"FStringContent", .start = 2, .end = 9},
        .{.type = .@"LBrace", .start = 9, .end = 10},
        .{.type = .@"Integer", .start = 10, .end = 11},
        .{.type = .@"RBrace", .start = 11, .end = 12},
        .{.type = .@"FStringContent", .start = 12, .end = 13},
        .{.type = .@"FStringEnd", .start = 13, .end = 14},
        .{.type = .@"EndOfFile", .start = 14, .end = 14},
    });
}
