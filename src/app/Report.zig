const std = @import("std");
const time_util = @import("../utils/time_util.zig");

const Io = std.Io;
const ArgumentParser = @import("../app/ArgumentParser.zig");
const Candle = @import("../types/Candle.zig");
const Currency = @import("../types/Currency.zig");

const Self = @This();

cli: ArgumentParser,
peak: Candle,
peak_day: [10]u8,
since: Candle,
since_day: [10]u8,
latest: Candle,

pub fn init(cli: ArgumentParser, peak: Candle, since: Candle, latest: Candle) !Self {
    var report: Self = .{
        .cli = cli,
        .peak = peak,
        .peak_day = undefined,
        .since = since,
        .since_day = undefined,
        .latest = latest,
    };
    _ = try time_util.utcIso(&report.peak_day, peak.time);
    _ = try time_util.utcIso(&report.since_day, since.time);
    return report;
}

pub fn format(self: Self, writer: *Io.Writer) Io.Writer.Error!void {
    const amount = self.cli.amount;
    const coin = self.cli.coin;
    const fiat = self.cli.fiat;

    const since_value = amount * self.since.close;
    const peak_value = amount * self.peak.high;
    const latest_value = amount * self.latest.close;

    try writer.print("Coin:             {s}\n", .{coin});
    try writer.print("Amount:           {d} {s}\n", .{ amount, coin });
    try writer.print("Since:            {s}\n", .{self.cli.since});
    try writer.print("Price at date:    {f} {s} //price of 1 {s} on {s}\n", .{ Currency.unit(self.since.close), fiat, coin, self.since_day });
    try writer.print("Value at date:    {f} {s}\n", .{ Currency.of(since_value), fiat });
    try writer.print("Highest price:    {f} {s} //price of 1 {s} on {s}\n", .{ Currency.unit(self.peak.high), fiat, coin, self.peak_day });
    try writer.print("Value at peak:    {f} {s}\n", .{ Currency.of(peak_value), fiat });
    try writer.print("Current value:    {f} {s} (@ {f} {s})\n", .{ Currency.of(latest_value), fiat, Currency.unit(self.latest.close), fiat });
    try writer.print("Missed profits:   {f} {s}\n", .{ Currency.of(peak_value - since_value), fiat });
}

