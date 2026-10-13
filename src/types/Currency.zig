const std = @import("std");

const Io = std.Io;

const Self = @This();

pub const Mode = enum {
    total,
    unit
};

const max_fixed: f64 = 1e15;
const min_fixed_unit: f64 = 1e-10;
const unit_sig_digits = 4;

value: f64,
mode: Mode = .total,

pub fn of(value: f64) Self {
    return .{ .value = value };
}

pub fn unit(value: f64) Self {
    return .{ .value = value, .mode = .unit };
}

fn decimals(self: Self, v: f64) usize {
    if (self.mode == .total or v >= 1 or v == 0) return 2;
    const leading_zeros: usize = @intFromFloat(-@floor(@log10(v)) - 1);
    return leading_zeros + unit_sig_digits;
}

pub fn format(self: Self, w: *Io.Writer) Io.Writer.Error!void {
    var v = self.value;
    if (std.math.isNan(v)) return w.writeAll("NaN");
    if (v < 0) {
        try w.writeByte('-');
        v = -v;
    }
    if (std.math.isInf(v)) return w.writeAll("inf");
    if (v >= max_fixed or (self.mode == .unit and v > 0 and v < min_fixed_unit))
        return w.print("{e}", .{v});

    var buf: [64]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d:.[1]}", .{ v, self.decimals(v) }) catch return error.WriteFailed;

    const dot = std.mem.indexOfScalar(u8, text, '.') orelse text.len;
    const whole = text[0..dot];
    var frac = text[dot..];
    if (self.mode == .unit) while (frac.len > 3 and frac[frac.len - 1] == '0') {
        frac = frac[0 .. frac.len - 1];
    };

    for (whole, 0..) |c, i| {
        if (i != 0 and (whole.len - i) % 3 == 0) try w.writeByte(',');
        try w.writeByte(c);
    }
    try w.writeAll(frac);
}

// Start testing section -----------------------------------------------------------------------------------------------
fn expectFmt(expected: []const u8, c: Self) !void {
    var buf: [128]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try c.format(&w);
    try std.testing.expectEqualStrings(expected, w.buffered());
}

test "totals use 2 decimals and thousands separators" {
    try expectFmt("1,234,567.89", .of(1234567.891));
    try expectFmt("0.50", .of(0.5));
    try expectFmt("0.00", .of(0));
    try expectFmt("1.00", .of(0.999999));
    try expectFmt("-1,234.50", .of(-1234.5));
    try expectFmt("999,999,999,999,999.00", .of(999_999_999_999_999));
}

test "huge or non-finite values do not crash" {
    try expectFmt("1e300", .of(1e300));
    try expectFmt("1.5e15", .of(1.5e15));
    try expectFmt("inf", .of(std.math.inf(f64)));
    try expectFmt("-inf", .of(-std.math.inf(f64)));
    try expectFmt("NaN", .of(std.math.nan(f64)));
}

test "unit prices keep significant digits for sub-1 prices" {
    try expectFmt("43,210.50", .unit(43210.5));
    try expectFmt("2.00", .unit(2));
    try expectFmt("0.50", .unit(0.5));
    try expectFmt("0.03456", .unit(0.03456));
    try expectFmt("0.004", .unit(0.004));
    try expectFmt("0.00001234", .unit(0.00001234));
    try expectFmt("0.0000000123", .unit(0.0000000123));
    try expectFmt("1.23e-11", .unit(1.23e-11));
    try expectFmt("0.00", .unit(0));
}