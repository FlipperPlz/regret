const Self = @This();

time: i64,
high: f64,
close: f64,

pub const Row = [6]f64;

pub fn fromRow(row: Row) Self {
    return .{ .time = @trunc(row[0]), .high = row[2], .close = row[4] };
}
