//! Maintains a hashmap of types to concurrent queues, allowing for creation
//! Of channels for commands, queries, and notifications within a Mediator
//! Context.
const std = @import("std");
const concurrency = @import("concurrency.zig");

const QueueRegistry = @This();

/// A hashmap of stringified types to corresonding queues
registries: std.StringHashMap(std.ArrayList(*anyopaque)),

/// The allocator used to provision new queues
allocator: std.mem.Allocator,

mutex: std.Thread.Mutex,
pub fn init(allocator: std.mem.Allocator) QueueRegistry {
    return QueueRegistry{ .registries = std.StringHashMap(std.ArrayList(*anyopaque)).init(allocator), .allocator = allocator, .mutex = std.Thread.Mutex{} };
}

pub fn register_handler(self: *QueueRegistry, comptime T: type, capacity: usize) !*concurrency.RingBufferConcurrentQueue(T) {
    // TODO: I think this needs be cleaned up in deinit with self.allocator.destroy
    self.mutex.lock();
    defer self.mutex.unlock();
    const queue = try self.allocator.create(concurrency.RingBufferConcurrentQueue(T));
    const key = @typeName(T);
    queue.* = try concurrency.RingBufferConcurrentQueue(T).init(self.allocator, capacity);
    const list = try self.registries.getOrPut(key);
    if (!list.found_existing) {
        list.value_ptr.* = std.ArrayList(*anyopaque).init(self.allocator);
    }
    try list.value_ptr.append(@constCast(queue));
    return queue;
}

/// Unregisters the queue and destroys the pointer.  Pointer will be freed!
pub fn unregister_handler(self: *QueueRegistry, comptime T: type, handler_queue: *concurrency.RingBufferConcurrentQueue(T)) void {
    self.mutex.lock();
    defer self.mutex.unlock();
    const key = @typeName(T);
    var maybe_list = self.registries.getPtr(key) orelse return;

    for (maybe_list.items, 0..) |queue_ptr, index| {
        const typed_ptr: *concurrency.RingBufferConcurrentQueue(T) = @ptrCast(@alignCast(queue_ptr));
        if (typed_ptr == handler_queue) {
            _ = maybe_list.swapRemove(index);
            self.allocator.destroy(handler_queue);
            return;
        }
    }
}

pub fn send(self: *QueueRegistry, comptime T: type, message: T) !void {
    self.mutex.lock();
    defer self.mutex.unlock();
    const key = @typeName(T);

    const maybe_queue = self.registries.getPtr(key);

    if (maybe_queue) |queue| {
        if (queue.items.len == 0) {
            std.debug.print("No handlers registered for type.  noop!\n", .{});
            return;
        }
        for (queue.items) |queue_ptr| {
            var typed_queue: *concurrency.RingBufferConcurrentQueue(T) = @ptrCast(@alignCast(queue_ptr));
            try typed_queue.enqueue(message);
        }
    } else {
        std.debug.print("No handlers registered for type.  noop!\n", .{});
    }
}

pub fn deinit(self: *QueueRegistry) void {
    self.registries.deinit();
}
