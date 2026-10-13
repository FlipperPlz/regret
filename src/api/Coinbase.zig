const std = @import("std");
const http = std.http;
const json = std.json;
const time_util = @import("../utils/time_util.zig");

const Io = std.Io;
const Allocator = std.mem.Allocator;
const Candle = @import("../types/Candle.zig");
const Summary = @import("../types/Summary.zig");
const Span = @import("../types/Span.zig");

const Self = @This();

const base_url = "https://api.exchange.coinbase.com";
const user_agent = "regret/1.0";
const request_delay_ms = 200;

pub const max_candles_per_request = 300;

gpa: Allocator,
client: http.Client,
status: http.Status = .ok,

pub fn init(gpa: Allocator, io: Io) Self {
    return .{
        .gpa = gpa,
        .client = .{ .allocator = gpa, .io = io },
    };
}

pub fn deinit(self: *Self) void {
    self.client.deinit();
}

pub fn scan(
    self: *Self,
    io: Io,
    coin: []const u8,
    fiat: []const u8,
    span: Span,
    target_time: i64,
) !Summary {
    var summary: Summary = .{};
    var chunks = span.chunks(max_candles_per_request * time_util.day_s);

    while (chunks.next()) |chunk| {
        const rows = try self.dailyCandles(coin, fiat, chunk);
        defer rows.deinit();

        for (rows.value) |row| summary.add(.fromRow(row), target_time);
        try io.sleep(.fromMilliseconds(request_delay_ms), .awake);
    }

    return summary;
}

fn dailyCandles(
    self: *Self,
    coin: []const u8,
    fiat: []const u8,
    span: Span,
) !json.Parsed([]const Candle.Row) {
    var from_buf: [32]u8 = undefined;
    var to_buf: [32]u8 = undefined;

    const url = try std.fmt.allocPrint(
        self.gpa,
        "{s}/products/{s}-{s}/candles?granularity=86400&start={s}&end={s}",
        .{
            base_url,
            coin,
            fiat,
            try time_util.utcIso(&from_buf, span.from),
            try time_util.utcIso(&to_buf, span.to),
        },
    );
    defer self.gpa.free(url);

    var body: Io.Writer.Allocating = .init(self.gpa);
    defer body.deinit();

    const result = try self.client.fetch(.{
        .location = .{ .url = url },
        .headers = .{ .user_agent = .{ .override = user_agent } },
        .response_writer = &body.writer,
    });

    switch (result.status) {
        .ok => {},
        .not_found => return error.UnknownMarket,
        else => {
            self.status = result.status;
            return error.HttpStatus;
        },
    }

    return json.parseFromSlice([]const Candle.Row, self.gpa, body.written(), .{});
}
