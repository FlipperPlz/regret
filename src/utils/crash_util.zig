const std = @import("std");

pub fn fatal(comptime fmt: []const u8, fmt_args: anytype) noreturn {
    std.debug.print(fmt ++ "\n", fmt_args);
    std.process.exit(1);
}