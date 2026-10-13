const std = @import("std");

const Io = std.Io;

const Self = @This();

value: f64,

pub fn of(value: f64) Self {
    return .{ .value = value };
}

pub fn format(self: Self, w: *Io.Writer) Io.Writer.Error!void {
    const cents: u128 = @round(self.value * 100);

    var digits: [40]u8 = undefined;
    const dollars = std.fmt.bufPrint(&digits, "{d}", .{cents / 100}) catch return error.WriteFailed;

    for (dollars, 0..) |c, i| {
        if (i != 0 and (dollars.len - i) % 3 == 0) try w.writeByte(',');
        try w.writeByte(c);
    }
    try w.print(".{d:0>2}", .{cents % 100});
}