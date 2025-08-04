const std = @import("std");
const concurrency = @import("concurrency.zig");
const QueueRegistry = @import("QueueRegistry.zig");
const Mediator = @This();

notification_registry: QueueRegistry,
/// The allocator used to provision new queues
allocator: std.mem.Allocator,
queue_size: usize,
mutex: std.Thread.Mutex,

pub fn init(allocator: std.mem.Allocator, queue_size: usize) Mediator {
    return Mediator{ .notification_registry = QueueRegistry.init(allocator), .allocator = allocator, .queue_size = queue_size, .mutex = std.Thread.Mutex{} };
}

pub fn deinit(self: *Mediator) void {
    self.notification_registry.deinit();
}

pub fn register_notification_handler(self: *Mediator, comptime T: type) !*concurrency.RingBufferConcurrentQueue(T) {
    return try self.notification_registry.register_handler(T, self.queue_size);
}

pub fn send_notification(self: *Mediator, comptime T: type, notification: T) !void {
    try self.notification_registry.send(T, notification);
}
