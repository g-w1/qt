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
            try stdout.print("\n[{d}/{d}] def of `{s}`?\n", .{ correct.items.len, incorrect.items.len + lines.items.len, item.term });
            const answer = (try stdin.readUntilDelimiterOrEofAlloc(gpa, '\n', std.math.maxInt(u16))) orelse return;
            defer gpa.free(answer);
            if (std.mem.trim(u8, answer, " \n").len == 0)
                try lines.append(item);
            const trimmed = std.mem.trim(u8, answer, " \t\n");
            if (try matches(gpa, trimmed, item.def)) {
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

// thanks @rafi for this
fn lev(comptime T: type, allocator: *std.mem.Allocator, lhs: []const T, rhs: []const T) !usize {
    // create two work vectors of integer distances
    var v0 = try allocator.alloc(usize, rhs.len);
    defer allocator.free(v0);
    var v1 = try allocator.alloc(usize, rhs.len);
    defer allocator.free(v1);

    // initialize v0 (the previous row of distances)
    // this row is A[0][i]: edit distance for an empty s
    // the distance is just the number of characters to delete from t
    var i: usize = 0;
    while (i < rhs.len) : (i += 1) {
        v0[i] = i;
    }

    i = 0;
    while (i < lhs.len - 1) : (i += 1) {
        // calculate v1 (current row distances) from the previous row v0

        // first element of v1 is A[i+1][0]
        //   edit distance is delete (i+1) chars from s to match empty t
        v1[0] = i + 1;

        // use formula to fill in the rest of the row
        var j: usize = 0;
        while (j < rhs.len - 1) : (j += 1) {
            // calculating costs for A[i+1][j+1]
            const deletionCost: usize = v0[j + 1] + 1;
            const insertionCost: usize = v1[j] + 1;
            const substitutionCost = blk: {
                if (lhs[i] == rhs[j]) {
                    break :blk v0[j];
                } else {
                    break :blk v0[j] + 1;
                }
            };

            const minCost = blk: {
                var min: usize = std.math.maxInt(usize);
                if (deletionCost < min) {
                    min = deletionCost;
                }
                if (insertionCost < min) {
                    min = insertionCost;
                }
                if (substitutionCost < min) {
                    min = substitutionCost;
                }
                break :blk min;
            };
            v1[j + 1] = minCost;
        }

        // copy v1 (current row) to v0 (previous row) for next iteration
        // since data in v1 is always invalidated, a swap without copy could be more efficient
        std.mem.copy(usize, v0, v1);
    }
    return v0[rhs.len - 1];
}

test "lev" {
    var allocator = std.testing.allocator;
    const dist = try lev(u8, allocator, "kitten", "sitting");
    std.testing.expect(dist == 3);
}

pub fn matches(ally: *std.mem.Allocator, guess: []const u8, ans: []const u8) !bool {
    var min: usize = std.math.maxInt(usize);
    var possible = std.mem.tokenize(ans, ";,");
    while (possible.next()) |item| {
        const num: usize = try lev(u8, ally, guess, item);
        if (num < min) min = num;
    }
    return min < 15;
}
