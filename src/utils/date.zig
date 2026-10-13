const std = @import("std");

pub const Date = packed struct {
    month: u4,
    day: u5,
    year: u14,
};

pub fn parse(input: []const u8, pattern: []const u8, current_year: ?u14) ?Date {
    var year: ?u14 = null;
    var month: ?u4 = null;
    var day: ?u5 = null;
    var p: usize = 0;
    var i: usize = 0;

    while (p < pattern.len) {
        const c = std.ascii.toLower(pattern[p]);

        if (c != 'm' and c != 'd' and c != 'y') {
            if (i >= input.len or input[i] != pattern[p]) return null;
            p += 1;
            i += 1;
            continue;
        }

        var run: usize = 0;
        while (p + run < pattern.len and std.ascii.toLower(pattern[p + run]) == c) run += 1;
        if (i + run > input.len) return null;

        const digits = input[i..][0..run];
        for (digits) |d| if (!std.ascii.isDigit(d)) return null;

        switch (c) {
            'm' => {
                if (run != 2 or month != null) return null;
                month = std.fmt.parseUnsigned(u4, digits, 10) catch return null;
            },
            'd' => {
                if (run != 2 or day != null) return null;
                day = std.fmt.parseUnsigned(u5, digits, 10) catch return null;
            },
            'y' => {
                if ((run != 2 and run != 4) or year != null) return null;
                const n = std.fmt.parseUnsigned(u14, digits, 10) catch return null;
                year = if (run == 4) n else blk: {
                    const cur = current_year orelse return null;
                    break :blk nearestCentury(cur) + n;
                };
            },
            else => unreachable,
        }
        p += run;
        i += run;
    }

    if (i != input.len) return null;

    const m = month orelse return null;
    const d = day orelse return null;
    if (m < 1 or m > 12 or d < 1 or d > 31) return null;

    return .{
        .year = year orelse (current_year orelse return null),
        .month = m,
        .day = d,
    };
}

fn nearestCentury(year: u14) u14 {
    return @divFloor(year + 50, 100) * 100;
}
