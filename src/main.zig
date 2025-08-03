const std = @import("std");
const builtin = @import("builtin");
const zap = @import("zap");
const queue = @import("concurrent_queue.zig");
const opc = @import("open62541");

var routes: std.StringHashMap(zap.HttpRequestFn) = undefined;
var running = std.atomic.Value(bool).init(false);
var start_time = std.atomic.Value(i64).init(0);
var counter = std.atomic.Value(u64).init(0);
var my_queue = queue.ConcurrentQueue([]const u8).init(std.heap.page_allocator);

fn dispatch_routes(r: zap.Request) !void {
    if (r.path) |the_path| {
        if (routes.get(the_path)) |foo| {
            try foo(r);
            return;
        }
    }
    std.debug.print("No route found for path: {s}\n", .{r.path.?});
}

pub fn opcWorkerThread() !void {
    var config: opc.UA_ServerConfig = .{};
    const ret_val = opc.UA_ServerConfig_setDefault(&config);
    if (ret_val != opc.UA_STATUSCODE_GOOD) {
        return error.ServerConfigFailed;
    }
    config.applicationDescription.applicationUri = opc.UA_String_fromChars("urn:example:application");
    // output the application Name
    std.debug.print("Application Uri: {s}\n", .{config.applicationDescription.applicationUri.data});
    const config_ptr: [*c]opc.UA_ServerConfig = @ptrCast(&config);
    const server = opc.UA_Server_newWithConfig(config_ptr);

    std.debug.print("Creating OPC UA server...\n", .{});
    if (server) |s| {
        var status: opc.UA_StatusCode = 0;
        defer status = opc.UA_Server_delete(s);
        var opc_running: opc.UA_Boolean = true;
        status = opc.UA_Server_run(s, &opc_running);
        if (status != opc.UA_STATUSCODE_GOOD) {
            return error.ServerRunFailed;
        }

        std.debug.print("Server is running...\n", .{});

        while (running.load(.seq_cst)) {
            // no op
            std.Thread.sleep(1 * std.time.ns_per_s);
        }
    } else {
        return error.ServerCreationFailed;
    }

    std.debug.print("Opc thread exiting\n", .{});
}

fn getPublicFolder() []const u8 {
    if (builtin.mode == .Debug) return "client/protonexus/dist";
    return "public";
}
pub fn zapWorkerThread() !void {
    try setupRoutes(std.heap.page_allocator);
    const public_dir = getPublicFolder();
    var listener = zap.HttpListener.init(.{
        .port = 3000,
        .on_request = dispatch_routes,
        .public_folder = public_dir,
        .log = true,
    });
    try listener.listen();

    std.debug.print("Listening on 0.0.0.0:3000\n", .{});
    std.debug.print("Serving static files from {s}", .{public_dir});
    zap.start(.{
        .threads = 1,
        .workers = 1,
    });
}

pub fn myWorkerThread() !void {
    while (running.load(.seq_cst)) {
        // handle requests
        std.time.sleep(1 * std.time.ns_per_s); // simulate work
        std.debug.print("Worker thread is running...\n", .{});
        // increment a counter
        var value = counter.load(.seq_cst);
        value += 1;
        counter.store(value, .seq_cst);
        try my_queue.enqueue("Test");
        try my_queue.enqueue("Safe travels my friend");
    }
    std.debug.print("Worker thread is exiting..\n", .{});
}

fn info(r: zap.Request) !void {
    const currentTime = std.time.milliTimestamp();
    const startTime = start_time.load(.seq_cst);
    const uptimeMillis = currentTime - startTime;
    const counterValue = counter.load(.seq_cst);

    const response = .{
        .uptime = uptimeMillis,
        .count = counterValue,
    };
    var string = std.ArrayList(u8).init(std.heap.page_allocator);
    try std.json.stringify(response, .{}, string.writer());
    try r.sendJson(string.items);
}
fn hello(r: zap.Request) !void {
    const response = .{
        .message = "Hello, World!",
    };
    var string = std.ArrayList(u8).init(std.heap.page_allocator);
    try std.json.stringify(response, .{}, string.writer());
    try r.sendJson(string.items);
}

fn goodbye(r: zap.Request) !void {
    const response = .{
        .message = "Goodbye, World!",
    };
    var string = std.ArrayList(u8).init(std.heap.page_allocator);
    try std.json.stringify(response, .{}, string.writer());
    try r.sendJson(string.items);
}
pub fn setupRoutes(a: std.mem.Allocator) !void {
    // setup routes
    routes = std.StringHashMap(zap.HttpRequestFn).init(a);
    try routes.put("/api/hello", hello);
    try routes.put("/api/goodbye", goodbye);
    try routes.put("/api/info", info);
    std.debug.print("Setup routes:\n", .{});

    var it = routes.iterator();
    while (it.next()) |item| {
        std.debug.print("  {s} -> {}\n", .{ item.key_ptr.*, item.value_ptr.* });
    }
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

pub fn main() !void {
    // start worker threads
    // start new thread
    running.store(true, .seq_cst);
    start_time.store(std.time.milliTimestamp(), .seq_cst);
    var zapThread = try std.Thread.spawn(.{}, zapWorkerThread, .{});
    var myThread = try std.Thread.spawn(.{}, myWorkerThread, .{});
    var opcThread = try std.Thread.spawn(.{}, opcWorkerThread, .{});
    defer myThread.join();
    defer zapThread.join();
    defer opcThread.join();
    std.debug.print("Worker threads started.\n", .{});

    const action = std.posix.Sigaction{
        .handler = .{ .handler = handleSigInter },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &action, null);
    while (running.load(.seq_cst)) {
        std.time.sleep(100 * std.time.ns_per_ms); // sleep to reduce CPU usage
        while (my_queue.count() > 0) {
            const msg = try my_queue.dequeue();
            std.debug.print("{s}\n", .{msg});
        }
    }
    std.debug.print("Main thread exiting...\n", .{});
}
