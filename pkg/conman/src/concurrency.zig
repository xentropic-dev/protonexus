//! Concurrency generic types for thread-safe communication
//! Eventually, abstract these into an interface so that different back-ends
//! Can be plugged into Conman's Mediator, allowing support for IPC over
//! RabbitMQ, Redis, etc.

const std = @import("std");
const testing = std.testing;

/// A basic thread-safe FIFO queue backed by an ArrayList.
/// Enqueue is a constant time operation but dequeue is O(n).
pub fn ArrayListConcurrentQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        queue: std.ArrayList(T),
        mutex: std.Thread.Mutex,
        semaphore: std.Thread.Semaphore,

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .queue = std.ArrayList(T).init(allocator),
                .mutex = std.Thread.Mutex{},
                .semaphore = std.Thread.Semaphore{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.queue.deinit();
        }

        /// Appends an item to the end of the queue. Returns an allocation
        /// error on failure.
        pub fn enqueue(self: *Self, item: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.queue.append(item);
            self.semaphore.post();
        }

        /// Removes an item at the beginning of the queue and returns it.
        /// Blocks an waits for the semaphore to post. Calling this on any
        /// empty queue should block until an item is added. In theory,
        /// this can return an error if the queue is empty, but in practice,
        /// the semaphore will prevent that case. Call count() first if blocking
        /// is undesired.
        pub fn dequeue(self: *Self) !T {
            self.semaphore.wait();
            self.mutex.lock();
            defer self.mutex.unlock();

            const item = self.queue.orderedRemove(0);
            return item;
        }

        /// Returns the count of items in the queue
        pub fn count(self: *Self) u64 {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.queue.items.len;
        }
    };
}

/// A basic thread-safe FIFO queue backed by a RingBuffer
/// Has O(1) Enqueue and Dequeue but requires a known capacity
pub fn RingBufferConcurrentQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        ring: std.RingBuffer,
        mutex: std.Thread.Mutex,
        semaphore: std.Thread.Semaphore,

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            return Self{
                .ring = try std.RingBuffer.init(allocator, capacity * @sizeOf(T)),
                .mutex = std.Thread.Mutex{},
                .semaphore = std.Thread.Semaphore{},
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.ring.deinit(allocator);
        }

        /// Appends an item to the end of the queue. Returns an allocation
        /// error on failure.
        pub fn enqueue(self: *Self, item: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.ring.isFull()) return error.QueueFull;

            const data = std.mem.asBytes(&item);
            try self.ring.writeSlice(data);
            self.semaphore.post();
        }

        /// Removes an item at the beginning of the queue and returns it.
        /// Blocks an waits for the semaphore to post. Calling this on any
        /// empty queue should block until an item is added. In theory,
        /// this can return an error if the queue is empty, but in practice,
        /// the semaphore will prevent that case. Call count() first if blocking
        /// is undesired.
        pub fn dequeue(self: *Self) !T {
            self.semaphore.wait();
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.ring.isEmpty()) return error.QueueEmpty;

            // SAFETY: The semaphore ensures there is an item available in the queue,
            // so reading uninitialized `item` bytes here is safe as they will be
            // immediately overwritten by `readFirst`.
            var item: T = undefined;
            const itemBytes = std.mem.asBytes(&item);

            try self.ring.readFirst(itemBytes, @sizeOf(T));

            return item;
        }

        /// Returns the count of items in the queue
        pub fn count(self: *Self) u64 {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.ring.len() / @sizeOf(T);
        }
    };
}

// =============================================================================
// ArrayList Concurrent Queue Tests
// =============================================================================

test "ArrayListConcurrentQueue: basic enqueue and dequeue" {
    var queue = ArrayListConcurrentQueue(i32).init(testing.allocator);
    defer queue.deinit();

    try testing.expectEqual(@as(u64, 0), queue.count());

    try queue.enqueue(42);
    try testing.expectEqual(@as(u64, 1), queue.count());

    const item = try queue.dequeue();
    try testing.expectEqual(@as(i32, 42), item);
    try testing.expectEqual(@as(u64, 0), queue.count());
}

// =============================================================================
// RingBuffer Concurrent Queue Tests
// =============================================================================

test "RingBufferConcurrentQueue: basic enqueue and dequeue" {
    var queue = try RingBufferConcurrentQueue(i32).init(testing.allocator, 10);
    defer queue.deinit(testing.allocator);

    try testing.expectEqual(@as(u64, 0), queue.count());

    try queue.enqueue(42);
    try testing.expectEqual(@as(u64, 1), queue.count());

    const item = try queue.dequeue();
    try testing.expectEqual(@as(i32, 42), item);
    try testing.expectEqual(@as(u64, 0), queue.count());
}

// =============================================================================
// Performance Comparison Tests
// =============================================================================

fn profileArrayListQueue(item_count: u32) !u64 {
    var queue = ArrayListConcurrentQueue(i32).init(testing.allocator);
    defer queue.deinit();

    const start = std.time.nanoTimestamp();

    // Single-threaded performance test
    for (0..item_count) |i| {
        try queue.enqueue(@intCast(i));
    }

    for (0..item_count) |_| {
        _ = try queue.dequeue();
    }

    const end = std.time.nanoTimestamp();
    return @intCast(end - start);
}

fn profileRingBufferQueue(item_count: u32, capacity: usize) !u64 {
    var queue = try RingBufferConcurrentQueue(i32).init(testing.allocator, capacity);
    defer queue.deinit(testing.allocator);

    const start = std.time.nanoTimestamp();

    // Single-threaded performance test
    for (0..item_count) |i| {
        try queue.enqueue(@intCast(i));
        // Dequeue immediately to stay within capacity
        if (i >= capacity - 1) {
            _ = try queue.dequeue();
        }
    }

    // Dequeue remaining items
    while (queue.count() > 0) {
        _ = try queue.dequeue();
    }

    const end = std.time.nanoTimestamp();
    return @intCast(end - start);
}

test "Performance comparison: ArrayList vs RingBuffer" {
    const item_counts = [_]u32{ 1000, 5000, 10000 };
    const ring_capacity = 1000;

    std.debug.print("\n=== Queue Performance Comparison ===\n", .{});
    std.debug.print("{s:>8} {s:>15} {s:>15} {s:>8}\n", .{ "Items", "ArrayList(ns)", "RingBuffer(ns)", "Speedup" });
    std.debug.print("{s:>8} {s:>15} {s:>15} {s:>8}\n", .{ "-----", "------------", "-------------", "-------" });

    for (item_counts) |count| {
        const arraylist_time = try profileArrayListQueue(count);
        const ringbuffer_time = try profileRingBufferQueue(count, ring_capacity);

        const speedup = @as(f64, @floatFromInt(arraylist_time)) / @as(f64, @floatFromInt(ringbuffer_time));

        std.debug.print("{d:>8} {d:>15} {d:>15} {d:>7.2}x\n", .{ count, arraylist_time, ringbuffer_time, speedup });
    }
    std.debug.print("\n", .{});
}
