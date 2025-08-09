const std = @import("std");
const builtin = @import("builtin");
const nexlog = @import("nexlog");
const Mediator = @import("conman").Mediator;
const tk = @import("tokamak");

const commands = @import("application").commands;
const queries = @import("application").queries;
const OpcService = @import("infrastructure").OpcService;
const StopSignal = @import("application").control.StopSignal;

var stop_signal: StopSignal = StopSignal.init();

const static_path = if (builtin.mode == .Debug) "client/protonexus/dist" else "public";

const App = struct {
    server: tk.Server,
    server_opts: tk.ServerOptions = .{
        .listen = .{
            .port = 42069,
        }
    },
    routes: []const tk.Route = &.{
        .get("/*", tk.static.dir(static_path, .{})),
        .get("/api/hello", hello),
    },

    fn hello() ![]const u8 {
        return "Hello, world!";
    }
};

var start_time = std.atomic.Value(i64).init(0);
var counter = std.atomic.Value(u64).init(0);
var mediator: Mediator = Mediator.init(std.heap.page_allocator, 1024);




fn getPublicFolder() []const u8 {
    if (builtin.mode == .Debug) return "client/protonexus/dist";
    return "public";
}

pub fn myWorkerThread(logger: *nexlog.Logger) !void {
    logger.info("Worker thread started", .{}, nexlog.here(@src()));
    var count: u64 = 0;
    const command_strings = [_][]const u8{ "speak", "shutup" };
    while (!stop_signal.isSet()) {
        // handle requests
        std.time.sleep(1 * std.time.ns_per_s); // simulate work
        // increment a counter
        var value = counter.load(.seq_cst);
        value += 1;
        counter.store(value, .seq_cst);
        try mediator.sendNotification(commands.DemoCommand, .{ .id = count, .verb = command_strings[count % 2] });
        count = count + 1;

        logger.info("Requesting random number", .{}, nexlog.here(@src()));

        const response = try mediator.query_registry.query(
            queries.RandomNumberQuery,
            queries.RandomNumberQuery.Response,
            .{ .min = 0, .max = 100 },
        );

        logger.info("Received random number: {d}", .{response.value}, nexlog.here(@src()));
    }
    logger.info("Worker thread exiting", .{}, nexlog.here(@src()));
}

pub fn handleSigInter(sig_num: c_int) callconv(.C) void {
    if (sig_num != std.posix.SIG.INT) {
        return;
    }
    if (stop_signal.isSet()) {
        return; // already shutting down
    }
    std.debug.print("Received SIGINT: {}\n", .{sig_num});
    std.debug.print("Received SIGINT, shutting down...\n", .{});
    stop_signal.requestStop();
}

// SAFETY: global_logger is initialized early in main() before use,
// and is never accessed before being assigned a valid pointer.
var global_logger: *nexlog.Logger = undefined;

pub fn globalLog(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = scope;
    switch (message_level) {
        std.log.Level.debug => global_logger.debug(format, args, nexlog.here(@src())),
        std.log.Level.info => global_logger.info(format, args, nexlog.here(@src())),
        std.log.Level.warn => global_logger.warn(format, args, nexlog.here(@src())),
        std.log.Level.err => global_logger.err(format, args, nexlog.here(@src())),
    }
}

pub const std_options: std.Options = .{
    .logFn = globalLog,
    .log_level = .debug,
};

pub fn handleRandomNumberQuery(query: queries.RandomNumberQuery) queries.RandomNumberQuery.Response {
    const min = query.min;
    const max = query.max;

    if (min > max) {
        return .{ .value = min, .ok = false };
    }

    const rand = std.crypto.random;
    const range: i32 = @intCast(max - min + 1);
    const r = rand.intRangeAtMost(i32, 0, range - 1) + min;

    return .{ .value = r, .ok = true };
}

pub fn start() !void {
    // start worker threads
    // start new thread
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try nexlog.Logger.init(allocator, .{ .min_level = .info });
    global_logger = logger;
    defer logger.deinit();
    start_time.store(std.time.milliTimestamp(), .seq_cst);

    const ct = try tk.Container.init(gpa.allocator(), &.{App});
    defer ct.deinit();

    const server = try ct.injector.get(*tk.Server);
    // const port = server.http.config.port.?;
    const apiThread = try server.http.listenInNewThread();
    defer apiThread.join();

    var opc_service = OpcService.init(logger, &stop_signal);

    var myThread = try std.Thread.spawn(.{}, myWorkerThread, .{logger});
    var opcThread = try opc_service.startWithThread();
    defer myThread.join();
    defer opcThread.join();
    logger.info("Worker threaders started.", .{}, nexlog.here(@src()));
    std.log.debug("TEST", .{});
    std.log.err("err", .{});
    std.log.warn("warn", .{});
    std.log.info("info", .{});
    std.log.debug("debug", .{});

    // TODO: This needs to be crossplatform
    switch (comptime builtin.target.os.tag) {
        .linux, .macos => {
            const action = std.posix.Sigaction{
                .handler = .{ .handler = handleSigInter },
                .mask = std.posix.empty_sigset,
                .flags = 0,
            };
            std.posix.sigaction(std.posix.SIG.INT, &action, null);
        },
        .windows => {
            // TODO: Handle windows term
        },
        else => @compileError("Unsupported OS"),
    }
    const notification_queue = try mediator.registerNotificationHandler(commands.DemoCommand);

    _ = try mediator.query_registry.registerHandler(
        queries.RandomNumberQuery,
        queries.RandomNumberQuery.Response,
        1024,
    );

    var verbosity: u64 = 0;
    var messages_to_read: u64 = 5;
    while (!stop_signal.isSet() and messages_to_read > 0) {
        std.time.sleep(100 * std.time.ns_per_ms); // sleep to reduce CPU usage
        if (notification_queue.count() > 0) {
            if (verbosity == 1) {
                logger.info("VERBOSITY IS ON.  Processing commands", .{}, nexlog.here(@src()));
            }

            while (notification_queue.count() > 0) {
                const command = try notification_queue.dequeue();

                messages_to_read = messages_to_read - 1;
                logger.info("Received command: id={d} msg={s}", .{ command.id, command.verb }, nexlog.here(@src()));

                if (std.mem.eql(u8, command.verb, "speak")) {
                    verbosity = 1;
                    logger.info("Speak command received.  Verbosity turned ON", .{}, nexlog.here(@src()));
                }
                if (std.mem.eql(u8, command.verb, "shutup")) {
                    verbosity = 0;
                    logger.info("Shutup command received.  Verbosity turned OFF", .{}, nexlog.here(@src()));
                }
            }
        }

        try mediator.query_registry.processQueryHandlers(
            queries.RandomNumberQuery,
            queries.RandomNumberQuery.Response,
            handleRandomNumberQuery,
        );
    }

    logger.info("UNREGISTERING HANDLER", .{}, nexlog.here(@src()));
    mediator.notification_registry.unregisterHandler(commands.DemoCommand, notification_queue);

    while (!stop_signal.isSet()) {
        std.Thread.sleep(std.time.ns_per_s);
    }
    logger.info("Main thread exiting...", .{}, nexlog.here(@src()));

    server.stop();
}
