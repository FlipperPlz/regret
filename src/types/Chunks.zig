const Span = @import("Span.zig");

const Self = @This();

cursor: i64,
end: i64,
max_len: i64,

pub fn next(self: *Self) ?Span {
    if (self.cursor >= self.end) return null;

    const from = self.cursor;
    self.cursor = @min(from + self.max_len, self.end);
    return .{ .from = from, .to = self.cursor };
}
