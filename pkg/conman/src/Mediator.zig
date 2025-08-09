const std = @import("std");
const concurrency = @import("concurrency.zig");
const EventRegistry = @import("EventRegistry.zig");
const QueryRegistry = @import("QueryRegistry.zig");
const Mediator = @This();

notification_registry: EventRegistry,
query_registry: QueryRegistry,
/// The allocator used to provision new queues
allocator: std.mem.Allocator,
queue_size: usize,

pub fn init(allocator: std.mem.Allocator, queue_size: usize) Mediator {
    return Mediator{
        .notification_registry = EventRegistry.init(allocator),
        .query_registry = QueryRegistry.init(allocator),
        .allocator = allocator,
        .queue_size = queue_size,
    };
}

pub fn deinit(self: *Mediator) void {
    self.notification_registry.deinit();
}

pub fn registerNotificationHandler(self: *Mediator, comptime T: type) !*concurrency.RingBufferConcurrentQueue(T) {
    return self.notification_registry.registerHandler(T, self.queue_size);
}

pub fn sendNotification(self: *Mediator, comptime T: type, notification: T) !void {
    try self.notification_registry.send(T, notification);
}
