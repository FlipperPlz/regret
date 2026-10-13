const Candle = @import("Candle.zig");

const Self = @This();

peak: ?Candle = null,
since: ?Candle = null,
latest: ?Candle = null,

pub fn add(self: *Self, candle: Candle, target_time: i64) void {
    if (self.peak == null or candle.high > self.peak.?.high) self.peak = candle;

    if (candle.time >= target_time) {
        if (self.since == null or candle.time < self.since.?.time) self.since = candle;
    }

    if (self.latest == null or candle.time > self.latest.?.time) self.latest = candle;
}