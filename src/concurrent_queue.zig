const std = @import("std");

pub fn ConcurrentQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        queue: std.ArrayList(T),
        mutex: std.Thread.Mutex,
        semaphore: std.Thread.Semaphore,

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{ .queue = std.ArrayList(T).init(allocator), .mutex = std.Thread.Mutex{}, .semaphore = std.Thread.Semaphore{} };
        }

        pub fn enqueue(self: *Self, item: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.queue.append(item);
            self.semaphore.post();
        }

        pub fn dequeue(self: *Self) !T {
            self.semaphore.wait();
            self.mutex.lock();
            defer self.mutex.unlock();

            const item = self.queue.orderedRemove(0); // TODO: This is O(n)
            return item;
        }

        pub fn count(self: *Self) u64 {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.queue.items.len;
        }
    };
}
