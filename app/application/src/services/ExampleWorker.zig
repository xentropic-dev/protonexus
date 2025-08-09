const std = @import("std");
const nexlog = @import("nexlog");
const conman = @import("conman");
const commands = @import("../commands.zig");
const queries = @import("../queries.zig");

const StopSignal = @import("../control/StopSignal.zig");

const ExampleWorker = @This();

logger: *nexlog.Logger,
stop_signal: *StopSignal,
mediator: *conman.Mediator,

pub fn init(
    logger: *nexlog.Logger,
    stop_signal: *StopSignal,
    mediator: *conman.Mediator,
) ExampleWorker {
    return ExampleWorker{
        .logger = logger,
        .stop_signal = stop_signal,
        .mediator = mediator,
    };
}

pub fn startWithThread(self: *ExampleWorker) !std.Thread {
    return std.Thread.spawn(.{}, start, .{self});
}

pub fn start(self: *ExampleWorker) !void {
    self.logger.info("Worker thread started", .{}, nexlog.here(@src()));
    var count: u64 = 0;
    const command_strings = [_][]const u8{ "speak", "shutup" };
    while (!self.stop_signal.isSet()) {
        // handle requests
        std.time.sleep(1 * std.time.ns_per_s); // simulate work
        try self.mediator.sendNotification(commands.DemoCommand, .{ .id = count, .verb = command_strings[count % 2] });
        count = count + 1;

        self.logger.info("Requesting random number", .{}, nexlog.here(@src()));

        const response = try self.mediator.query_registry.query(
            queries.RandomNumberQuery,
            queries.RandomNumberQuery.Response,
            .{ .min = 0, .max = 100 },
        );

        self.logger.info("Received random number: {d}", .{response.value}, nexlog.here(@src()));
    }
    self.logger.info("Worker thread exiting", .{}, nexlog.here(@src()));
}
