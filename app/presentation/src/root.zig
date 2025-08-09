const std = @import("std");
const builtin = @import("builtin");
const opc = @import("open62541");
const nexlog = @import("nexlog");
const Mediator = @import("conman").Mediator;
const tk = @import("tokamak");

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

var running = std.atomic.Value(bool).init(false);
var start_time = std.atomic.Value(i64).init(0);
var counter = std.atomic.Value(u64).init(0);
var mediator: Mediator = Mediator.init(std.heap.page_allocator, 1024);

const DemoCommand = struct {
    id: u64,
    verb: []const u8,
};

const RandomNumberQuery = struct {
    min: i32,
    max: i32,
};

const RandomNumberQueryResponse = struct {
    value: i32,
    ok: bool,
};

pub fn opcWorkerThread(logger: *nexlog.Logger) !void {
    var config: opc.UA_ServerConfig = .{};
    const ret_val = opc.UA_ServerConfig_setDefault(&config);
    if (ret_val != opc.UA_STATUSCODE_GOOD) {
        return error.ServerConfigFailed;
    }
    config.applicationDescription.applicationUri = opc.UA_String_fromChars("urn:example:application");
    logger.info("Application Uri: {s}", .{config.applicationDescription.applicationUri.data}, nexlog.here(@src()));
    const config_ptr: [*c]opc.UA_ServerConfig = @ptrCast(&config);
    const server = opc.UA_Server_newWithConfig(config_ptr);

    logger.info("Creating OPC UA server.", .{}, nexlog.here(@src()));
    if (server) |s| {
        var status: opc.UA_StatusCode = 0;
        defer status = opc.UA_Server_delete(s);
        status = opc.UA_Server_run_startup(s);
        if (status != opc.UA_STATUSCODE_GOOD) {
            return error.ServerRunFailed;
        }

        logger.info("OPC server is running", .{}, nexlog.here(@src()));

        while (running.load(.seq_cst)) {
            // Run one iteration of the server event loop
            const wait_internal = opc.UA_Server_run_iterate(s, true);

            if (status != opc.UA_STATUSCODE_GOOD) {
                logger.err("Server iterate failed with status: {}", .{status}, nexlog.here(@src()));
                break;
            }

            // Small sleep to prevent busy waiting
            const sleep_interval: u64 = @intCast(wait_internal);
            std.Thread.sleep(sleep_interval);
            // std.Thread.sleep(@cwait_internal * std.time.ns_per_ms);
        }

        status = opc.UA_Server_run_shutdown(s);
        logger.info("OPC server shutdown", .{}, nexlog.here(@src()));
    } else {
        return error.ServerCreationFailed;
    }

    logger.info("OPC thread is exiting", .{}, nexlog.here(@src()));
}

fn getPublicFolder() []const u8 {
    if (builtin.mode == .Debug) return "client/protonexus/dist";
    return "public";
}

pub fn myWorkerThread(logger: *nexlog.Logger) !void {
    logger.info("Worker thread started", .{}, nexlog.here(@src()));
    var count: u64 = 0;
    const commands = [_][]const u8{ "speak", "shutup" };
    while (running.load(.seq_cst)) {
        // handle requests
        std.time.sleep(1 * std.time.ns_per_s); // simulate work
        // increment a counter
        var value = counter.load(.seq_cst);
        value += 1;
        counter.store(value, .seq_cst);
        try mediator.sendNotification(DemoCommand, .{ .id = count, .verb = commands[count % 2] });
        count = count + 1;

        logger.info("Requesting random number", .{}, nexlog.here(@src()));

        const response = try mediator.query_registry.query(
            RandomNumberQuery,
            RandomNumberQueryResponse,
            RandomNumberQuery{ .min = 0, .max = 100 },
        );

        logger.info("Received random number: {d}", .{response.value}, nexlog.here(@src()));
    }
    logger.info("Worker thread exiting", .{}, nexlog.here(@src()));
}

pub fn handleSigInter(sig_num: c_int) callconv(.C) void {
    if (sig_num != std.posix.SIG.INT) {
        return;
    }
    if (!running.load(.seq_cst)) {
        return; // already shutting down
    }
    std.debug.print("Received SIGINT: {}\n", .{sig_num});
    std.debug.print("Received SIGINT, shutting down...\n", .{});
    running.store(false, .seq_cst);
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

pub fn handleRandomNumberQuery(query: RandomNumberQuery) RandomNumberQueryResponse {
    const min = query.min;
    const max = query.max;

    if (min > max) {
        return RandomNumberQueryResponse{ .value = min, .ok = false };
    }

    const rand = std.crypto.random;
    const range: i32 = @intCast(max - min + 1);
    const r = rand.intRangeAtMost(i32, 0, range - 1) + min;

    return RandomNumberQueryResponse{ .value = r, .ok = true };
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
    running.store(true, .seq_cst);
    start_time.store(std.time.milliTimestamp(), .seq_cst);

    const ct = try tk.Container.init(gpa.allocator(), &.{App});
    defer ct.deinit();

    const server = try ct.injector.get(*tk.Server);
    // const port = server.http.config.port.?;
    const apiThread = try server.http.listenInNewThread();
    defer apiThread.join();

    var myThread = try std.Thread.spawn(.{}, myWorkerThread, .{logger});
    var opcThread = try std.Thread.spawn(.{}, opcWorkerThread, .{logger});
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
    const notification_queue = try mediator.registerNotificationHandler(DemoCommand);

    _ = try mediator.query_registry.registerHandler(
        RandomNumberQuery,
        RandomNumberQueryResponse,
        1024,
    );

    var verbosity: u64 = 0;
    var messages_to_read: u64 = 5;
    while (running.load(.seq_cst) and messages_to_read > 0) {
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
            RandomNumberQuery,
            RandomNumberQueryResponse,
            handleRandomNumberQuery,
        );
    }

    logger.info("UNREGISTERING HANDLER", .{}, nexlog.here(@src()));
    mediator.notification_registry.unregisterHandler(DemoCommand, notification_queue);

    while (running.load(.seq_cst)) {
        std.Thread.sleep(std.time.ns_per_s);
    }
    logger.info("Main thread exiting...", .{}, nexlog.here(@src()));

    server.stop();
}
