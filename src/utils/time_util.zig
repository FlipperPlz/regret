const std = @import("std");
const builtin = @import("builtin");
const zeit = @import("../main.zig").zeit;

const date = @import("date.zig");

const Io = std.Io;
const Allocator = std.mem.Allocator;

const unix_zoneinfo_dirs = [_][]const u8{
    "/usr/share/zoneinfo",
    "/usr/share/lib/zoneinfo",
    "/usr/lib/locale/TZ",
    "/share/zoneinfo",
    "/etc/zoneinfo",
};

pub const day_s: i64 = 86_400;

fn utcOffset(tz: *const zeit.TimeZone, ts: i64) i64 {
    return tz.adjust(ts).timestamp - ts;
}

pub fn localMidnight(
    input: []const u8,
    fmt: []const u8,
    current_year: ?u14,
    tz: *const zeit.TimeZone,
) ?i64 {
    const parsed = date.parse(input, fmt, current_year) orelse return null;

    const month: zeit.Month = @enumFromInt(parsed.month);
    if (parsed.day > month.lastDay(@intCast(parsed.year))) return null;

    const wall = (zeit.Time{
        .year = parsed.year,
        .month = month,
        .day = parsed.day,
    }).instant().unixTimestamp();

    const before = utcOffset(tz, wall - day_s);
    const after = utcOffset(tz, wall + day_s);
    const t_before = wall - before;
    const t_after = wall - after;

    if (utcOffset(tz, t_before) == before) return t_before;
    if (utcOffset(tz, t_after) == after) return t_after;
    return t_before;
}

pub fn utcIso(buf: []u8, ts: i64) ![]const u8 {
    const t = zeit.instant(.{ .unix_timestamp = ts }, &zeit.utc).time();

    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}", .{
        @as(u32, @intCast(t.year)),
        @intFromEnum(t.month),
        t.day,
    });
}

pub fn loadZone(gpa: Allocator, io: Io, name: []const u8, tzdir: ?[]const u8) !zeit.TimeZone {
    if (builtin.os.tag == .windows) {
        const loc = std.meta.stringToEnum(zeit.Location, name) orelse return error.UnknownTimezone;
        return zeit.loadTimeZone(gpa, io, loc, .{});
    }

    if (name.len == 0 or name[0] == '/' or std.mem.indexOf(u8, name, "..") != null)
        return error.UnknownTimezone;

    if (tzdir) |dir| {
        if (try loadFromDir(gpa, io, dir, name)) |tz| return tz;
    }

    for (unix_zoneinfo_dirs) |dir| {
        if (try loadFromDir(gpa, io, dir, name)) |tz| return tz;
    }
    return error.UnknownTimezone;

}

fn loadFromDir(gpa: Allocator, io: Io, dir_path: []const u8, name: []const u8) !?zeit.TimeZone {
    var dir = Io.Dir.cwd().openDir(io, dir_path, .{}) catch return null;
    defer dir.close(io);

    const file = dir.openFile(io, name, .{}) catch return null;
    defer file.close(io);

    var buf: [2048]u8 = undefined;
    var reader = file.reader(io, &buf);

    const info = zeit.timezone.TZInfo.parse(gpa, &reader.interface) catch return error.UnknownTimezone;
    return .{ .tzinfo = info };
}
