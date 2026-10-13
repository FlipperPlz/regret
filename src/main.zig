const std = @import("std");
pub const zeit = @import("zeit");
pub const args = @import("args");

const Io = std.Io;
const ArgumentParser = @import("app/ArgumentParser.zig");
const Coinbase = @import("api/Coinbase.zig");
const Report = @import("app/Report.zig");
const time_util = @import("utils/time_util.zig");
const fatal = @import("utils/crash_util.zig").fatal;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    const parsed_arguments = blK: {
        var parser = try args.ArgumentParser.init(gpa, .{
            .name = "regret",
            .version = "0.0.1",
            .description = "Show what an amount of a coin would be worth at its peak USD price since a date, and how much you wasted by spending it since then... (Uses Coinbase API)",
        });
        defer parser.deinit();

        break :blK try ArgumentParser.parse(init, &parser);
    };
    var timezone = if (parsed_arguments.timezone) |name|
        time_util.loadZone(gpa, io, name, init.environ_map.get("TZDIR")) catch
            fatal("Unknown timezone: {s} (use an IANA name like America/New_York)", .{name})
    else
        zeit.local(gpa, io, .{}) catch
            fatal("Could not determine the system timezone; pass one with --tz", .{});
    defer timezone.deinit();

    const now_instant = zeit.instant(.{ .now = io }, &zeit.utc);
    const now: i64 = now_instant.unixTimestamp();
    const current_year: u14 = @intCast(now_instant.time().year);

    const since = time_util.localMidnight(parsed_arguments.since, parsed_arguments.datefmt, current_year, &timezone) orelse
        fatal("Invalid date \"{s}\" for format {s}", .{ parsed_arguments.since, parsed_arguments.datefmt });
    if (since >= now) fatal("Date must be in the past.", .{});

    var api: Coinbase = .init(gpa, io);
    defer api.deinit();

    const summary = api.scan(io, parsed_arguments.coin, parsed_arguments.fiat, .{ .from = since, .to = now }, since) catch |err| switch (err) {
        error.OutOfMemory => return err,
        error.UnknownMarket => fatal("Could not find a market for: {s}-{s}", .{ parsed_arguments.coin, parsed_arguments.fiat }),
        error.HttpStatus => fatal("Coinbase API error: {d} - {s}", .{ @intFromEnum(api.status), api.status.phrase() orelse "" }),
        else => fatal("Network error: {s}", .{@errorName(err)}),
    };

    const peak = summary.peak orelse
        fatal("No price data found for {s} since {s}.", .{ parsed_arguments.coin, parsed_arguments.since });
    const since_candle = summary.since orelse
        fatal("No price data found for {s} on or after {s}.", .{ parsed_arguments.coin, parsed_arguments.since });

    const report = try Report.init(parsed_arguments, peak, since_candle, summary.latest.?);

    var buf: [1024]u8 = undefined;
    var stdout = Io.File.stdout().writer(io, &buf);
    const writer = &stdout.interface;

    try writer.print("{f}", .{report});
    try writer.flush();
}

test {
    _ = @import("types/Currency.zig");
}
