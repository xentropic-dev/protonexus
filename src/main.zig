const std = @import("std");
const builtin = @import("builtin");
const opc = @import("open62541");
const nexlog = @import("nexlog");
const Mediator = @import("conman").Mediator;


// var routes: std.StringHashMap(zap.HttpRequestFn) = undefined;
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

// fn dispatch_routes(r: zap.Request) !void {
//     if (r.path) |the_path| {
//         if (routes.get(the_path)) |foo| {
//             try foo(r);
//             return;
//         }
//     }
//     std.debug.print("No route found for path: {s}\n", .{r.path.?});
// }
// pub fn global_log2(hmm: ?*anyopaque, log_level: c_uint, b: c_uint, msg: [*c]const u8, args: [*c]opc.struct___va_list_tag_13) callconv(.c) void {
//     _ = hmm;
//     // _ = a;
//     _ = b;
//     _ = args;
//
//     if (msg) |format_str| {
//         // This would require proper va_list handling which is complex in Zig
//         // For now, just log the format string
//         const format_slice = std.mem.span(format_str);
//         switch (log_level) {
//             opc.UA_LOGLEVEL_DEBUG => std.log.debug("OPC: {s}", .{format_slice}),
//             opc.UA_LOGLEVEL_INFO => std.log.info("OPC: {s}", .{format_slice}),
//             opc.UA_LOGLEVEL_WARNING => std.log.warn("OPC: {s}", .{format_slice}),
//             opc.UA_LOGLEVEL_ERROR => std.log.err("OPC: {s}", .{format_slice}),
//             else => std.log.err("OPC: {s}", .{format_slice}),
//         }
//     }
// }
//
pub fn opcWorkerThread(logger: *nexlog.Logger) !void {
    var config: opc.UA_ServerConfig = .{};
    const ret_val = opc.UA_ServerConfig_setDefault(&config);
    if (ret_val != opc.UA_STATUSCODE_GOOD) {
        return error.ServerConfigFailed;
    }
    config.applicationDescription.applicationUri = opc.UA_String_fromChars("urn:example:application");
    // config.logging.* = .{
    //     .log = global_log2,
    // };
    // output the application Name
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
// pub fn zapWorkerThread(logger: *nexlog.Logger) !void {
//     try setupRoutes(std.heap.page_allocator);
//     const public_dir = getPublicFolder();
//     var listener = zap.HttpListener.init(.{
//         .port = 3000,
//         .on_request = dispatch_routes,
//         .public_folder = public_dir,
//         .log = true,
//     });
//     try listener.listen();
//
//     logger.info("Listening on 0.0.0.0:3000", .{}, nexlog.here(@src()));
//     logger.info("Serving static files from: {s}", .{public_dir}, nexlog.here(@src()));
//
//     zap.start(.{
//         .threads = 1,
//         .workers = 1,
//     });
// }

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
        try mediator.send_notification(DemoCommand, .{ .id = count, .verb = commands[count % 2] });
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

// fn info(r: zap.Request) !void {
//     const currentTime = std.time.milliTimestamp();
//     const startTime = start_time.load(.seq_cst);
//     const uptimeMillis = currentTime - startTime;
//     const counterValue = counter.load(.seq_cst);
//
//     const response = .{
//         .uptime = uptimeMillis,
//         .count = counterValue,
//     };
//     var string = std.ArrayList(u8).init(std.heap.page_allocator);
//     try std.json.stringify(response, .{}, string.writer());
//     try r.sendJson(string.items);
// }
// fn hello(r: zap.Request) !void {
//     const response = .{
//         .message = "Hello, World!",
//     };
//     var string = std.ArrayList(u8).init(std.heap.page_allocator);
//     try std.json.stringify(response, .{}, string.writer());
//     try r.sendJson(string.items);
// }
//
// fn goodbye(r: zap.Request) !void {
//     const response = .{
//         .message = "Goodbye, World!",
//     };
//     var string = std.ArrayList(u8).init(std.heap.page_allocator);
//     try std.json.stringify(response, .{}, string.writer());
//     try r.sendJson(string.items);
// }
// pub fn setupRoutes(a: std.mem.Allocator) !void {
//     // setup routes
//     routes = std.StringHashMap(zap.HttpRequestFn).init(a);
//     try routes.put("/api/hello", hello);
//     try routes.put("/api/goodbye", goodbye);
//     try routes.put("/api/info", info);
//     std.debug.print("Setup routes:\n", .{});
//
//     var it = routes.iterator();
//     while (it.next()) |item| {
//         std.debug.print("  {s} -> {}\n", .{ item.key_ptr.*, item.value_ptr.* });
//     }
// }

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

var global_logger: *nexlog.Logger = undefined;

pub fn global_log(
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
    .logFn = global_log,
    .log_level = .debug,
};

pub fn HandleRandomNumberQuery(query: RandomNumberQuery) RandomNumberQueryResponse {
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

pub fn main() !void {
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
    // var zapThread = try std.Thread.spawn(.{}, zapWorkerThread, .{logger});
    var myThread = try std.Thread.spawn(.{}, myWorkerThread, .{logger});
    var opcThread = try std.Thread.spawn(.{}, opcWorkerThread, .{logger});
    defer myThread.join();
    // defer zapThread.join();
    defer opcThread.join();
    logger.info("Worker threaders started.", .{}, nexlog.here(@src()));
    std.log.debug("TEST", .{});
    std.log.err("err", .{});
    std.log.warn("warn", .{});
    std.log.info("info", .{});
    std.log.debug("debug", .{});

    // TODO: This needs to be crossplatform
    switch (comptime builtin.target.os.tag)
    {
        .linux => {
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
   const notification_queue = try mediator.register_notification_handler(DemoCommand);

    _ = try mediator.query_registry.register_handler(
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

        try mediator.query_registry.processQueryHandlers(RandomNumberQuery, RandomNumberQueryResponse, HandleRandomNumberQuery);
    }

    logger.info("UNREGISTERING HANDLER", .{}, nexlog.here(@src()));
    mediator.notification_registry.unregister_handler(DemoCommand, notification_queue);

    while (running.load(.seq_cst)) {
        std.Thread.sleep(std.time.ns_per_s);
    }
    logger.info("Main thread exiting...", .{}, nexlog.here(@src()));
}
