//! StopSignal provides a thread-safe, atomic boolean flag used to
//! cooperatively Signal cancellation or stopping of long-running or concurrent
//! operations.
const std = @import("std");

const StopSignal = @This();

/// The atomic boolean flag indicating whether stop has been requested.
flag: std.atomic.Value(bool),

/// Creates and returns a new StopSignal with the stop flag set to false.
pub fn init() StopSignal {
    return StopSignal{
        .flag = std.atomic.Value(bool).init(false),
    };
}

/// Atomically sets the stop flag to true, signaling that operations
/// should stop. This operation is idempotent and safe to call
/// concurrently from multiple threads.
pub fn requestStop(self: *StopSignal) void {
    self.flag.store(true, .seq_cst);
}

/// Resets the stop flag to false, allowing reuse of this StopSignal.
/// Use with caution: concurrent access without external synchronization
/// may cause race conditions.
pub fn reset(self: *StopSignal) void {
    self.flag.store(false, .seq_cst);
}

/// Returns true if a stop request has been made (the stop flag is set).
/// This method is safe to call concurrently from multiple threads.
pub fn isSet(self: *const StopSignal) bool {
    return self.flag.load(.seq_cst);
}

pub const WaitForStopOptions = struct {
    /// Time in milliseconds to wait for stop.  undefined for never
    timeout: ?i64 = undefined,
};

/// Blocks by spinning until a stop request is detected.
/// Useful for simple wait loops or testing, but consider more
/// efficient waiting mechanisms for production code.
pub fn waitForStop(self: *const StopSignal, options: WaitForStopOptions) !void {
    var timeout_enabled = false;
    var deadline = std.time.milliTimestamp();

    if (options.timeout) |timeout| {
        timeout_enabled = true;
        deadline = deadline + timeout;
    }

    while (!self.isSet()) {
        std.Thread.sleep(0);
        if (timeout_enabled and std.time.milliTimestamp() > deadline)
            return error.Timeout;
    }
}

test "StopSignal initializes unset" {
    var sig = StopSignal.init();
    try std.testing.expect(!sig.isSet());
}

test "requestStop sets the flag" {
    var sig = StopSignal.init();
    sig.requestStop();
    try std.testing.expect(sig.isSet());
}

test "reset clears the flag" {
    var sig = StopSignal.init();
    sig.requestStop();
    try std.testing.expect(sig.isSet());
    sig.reset();
    try std.testing.expect(!sig.isSet());
}

test "isSet returns correct state after multiple calls" {
    var sig = StopSignal.init();
    try std.testing.expect(!sig.isSet());
    sig.requestStop();
    try std.testing.expect(sig.isSet());
    sig.reset();
    try std.testing.expect(!sig.isSet());
}

fn test_thread_fn(stop_signal: *StopSignal) void {
    std.Thread.sleep(10 * std.time.ns_per_ms);
    stop_signal.requestStop();
}

test "waitForStop returns after requestStop" {
    var sig = StopSignal.init();

    var thread = try std.Thread.spawn(.{}, test_thread_fn, .{&sig});
    defer thread.join();

    try sig.waitForStop(.{
        .timeout = std.time.ns_per_ms*10,
    });
}
