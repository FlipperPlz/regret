const std = @import("std");
const args = @import("../main.zig").args;
const fatal = @import("../utils/crash_util.zig").fatal;

const Self = @This();

amount: f64,
coin: []const u8,
fiat: []const u8,
since: []const u8,
datefmt: []const u8,
timezone: ?[]const u8,

pub fn parse(init: std.process.Init, parser: *args.ArgumentParser) !Self {
    const arena = init.arena.allocator();

    try parser.addPositional("amount", .{
        .help = "How much of the coin you held",
        .value_type = .float,
        .metavar = "AMOUNT",
    });
    try parser.addPositional("coin", .{
        .help = "What currency type is your input",
        .metavar = "COIN",
    });
    try parser.addPositional("date", .{
        .help = "When did you buy the coins, date is interpreted as midnight in --tz (see --datefmt and --tz, Default: MM/DD/YYYY at system timezone)",
        .metavar = "DATE",
    });
    try parser.addPositional("fiat", .{
        .help = "What currency you want the results to show in. Default: USD",
        .metavar = "FIAT",
        .default = "USD",
        .required = false,
    });
    try parser.addOption("datefmt", .{
        .help = "Input date format, e.g. MM/DD/YYYY, mm/dd/yy, MM/DD (current year). Default: MM/DD/YYYY",
        .metavar = "FMT",
        .aliases = &.{"dateformat"},
        .required = false,
    });
    try parser.addOption("tz", .{
        .help = "IANA timezone for dates, e.g. America/New_York. Default: system timezone",
        .metavar = "TZ",
        .aliases = &.{"timezone"},
        .required = false,
    });

    var parsed = parser.parseProcess(init) catch |err| {
        parser.printHelp() catch {};
        fatal("{s}", .{@errorName(err)});
    };
    defer parsed.deinit();

    const amount = parsed.getFloat("amount") orelse fatal("Missing amount", .{});
    if (!std.math.isFinite(amount) or amount <= 0) fatal("Invalid amount: {d}", .{amount});

    return .{
        .amount = amount,
        .coin = try std.ascii.allocUpperString(arena, parsed.getString("coin") orelse fatal("Missing coin", .{})),
        .fiat = try std.ascii.allocUpperString(arena, parsed.getString("fiat") orelse fatal("Missing fiat", .{})),
        .since = try arena.dupe(u8, parsed.getString("date") orelse fatal("Missing date", .{})),
        .datefmt = try arena.dupe(u8, parsed.getString("datefmt") orelse "MM/DD/YYYY"),
        .timezone = if (parsed.getString("tz")) |t| try arena.dupe(u8, t) else null,
    };
}
