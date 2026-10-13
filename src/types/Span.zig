const Chunks = @import("Chunks.zig");

const Self = @This();

from: i64,
to: i64,

pub fn chunks(self: Self, max_len: i64) Chunks {
    return .{ .cursor = self.from, .end = self.to, .max_len = max_len };
}
