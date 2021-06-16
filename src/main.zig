const std = @import("std");

const TD = struct { term: []const u8, def: []const u8 };

pub fn main() anyerror!void {
    var a = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = a.deinit();
    const gpa = &a.allocator;

    if (std.os.argv.len != 2) {
        fatal("need 2 args pls, fname", .{});
    }

    const r = std.fs.cwd().readFileAlloc(gpa, std.mem.span(std.os.argv[1]), std.math.maxInt(usize)) catch fatal("oof: {s} is not a file that we can read", .{std.mem.span(std.os.argv[1])});
    defer gpa.free(r);

    var lines = std.ArrayList(TD).init(gpa);
    defer lines.deinit();
    var correct = std.ArrayList(TD).init(gpa);
    defer correct.deinit();
    var incorrect = std.ArrayList(TD).init(gpa);
    defer incorrect.deinit();

    var itn = std.mem.tokenize(r, "\n");
    while (itn.next()) |l| {
        var itl = std.mem.tokenize(l, "\t");
        const first = itl.next() orelse fatal("invalid line: \"{s}\"", .{l});
        const second = itl.next() orelse fatal("invalid line: \"{s}\"", .{l});
        try lines.append(.{ .term = first, .def = second });
    }
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.os.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = &prng.random;
    rand.shuffle(TD, lines.items);

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    var start = true;
    while (lines.items.len > 0 or start) {
        while (lines.popOrNull()) |item| {
            try stdout.print("\n[{d}/{d}] def of `{s}`?\n", .{ correct.items.len, incorrect.items.len + lines.items.len + correct.items.len, item.term });
            const answer = (try stdin.readUntilDelimiterOrEofAlloc(gpa, '\n', std.math.maxInt(u16))) orelse return;
            defer gpa.free(answer);
            if (std.mem.trim(u8, answer, " \n").len == 0)
                continue;
            if (std.mem.eql(u8, std.mem.trim(u8, answer, " \t"), item.def)) {
                try stdout.writeAll("correct!\n");
                try correct.append(item);
            } else {
                try stdout.print("wrong!, correct is `{s}`, did you get it correct?", .{item.def});
                const no = (try stdin.readUntilDelimiterOrEofAlloc(gpa, '\n', std.math.maxInt(u16))) orelse return;
                defer gpa.free(no);
                const not = std.mem.trim(u8, no, " \n");
                if (std.mem.eql(u8, not, "y") or std.mem.eql(u8, not, "yes")) {
                    try correct.append(item);
                    try stdout.print("ok, marked as correct", .{});
                } else {
                    try incorrect.append(item);
                }
            }
        }
        var tmp = incorrect;
        incorrect = lines;
        lines = tmp;
        start = false;
    }
}

pub fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.log.emerg(format, args);
    std.process.exit(1);
}
