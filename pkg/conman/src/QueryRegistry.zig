const std = @import("std");
const concurrency = @import("concurrency.zig");

const QueryRegistry = @This();
allocator: std.mem.Allocator,
registries: std.StringHashMap(std.ArrayList(*anyopaque)),
mutex: std.Thread.Mutex,

pub fn init(allocator: std.mem.Allocator) QueryRegistry {
    return QueryRegistry{
        .registries = std.StringHashMap(std.ArrayList(*anyopaque)).init(allocator),
        .allocator = allocator,
        .mutex = std.Thread.Mutex{},
    };
}

pub fn query(
    self: *QueryRegistry,
    comptime T: type,
    comptime R: type,
    q: T,
) !R {
    const key = @typeName(QueryContext(T, R));
    const maybe_queue_array = self.registries.getPtr(key);
    if (maybe_queue_array) |queue_array| {
        // TODO: More complex logic here, could configure a strategy
        // round robin, load balancing, etc, for now assume first queue in array
        if (queue_array.items.len == 0) return error.NoRegisteredQueue;
        const queue_ptr = queue_array.items[0];
        const handler_queue: *concurrency.RingBufferConcurrentQueue(
            QueryContext(T, R),
        ) = @ptrCast(
            @alignCast(queue_ptr),
        );
        var response_queue = try concurrency.RingBufferConcurrentQueue(R).init(self.allocator, 1);
        defer response_queue.deinit(self.allocator);

        const context = QueryContext(T, R){
            .query = q,
            .response_queue = &response_queue,
        };

        try handler_queue.enqueue(context);
        // TODO: Make timeout configurable
        // TODO: Add cancellation tokens for app-wide shutdown
        const deadline = std.time.milliTimestamp() + std.time.ms_per_s * 5;
        while (true) {
            if (std.time.milliTimestamp() > deadline)
                return error.Timeout;

            if (response_queue.count() > 0) break;

            std.time.sleep(10 * std.time.ns_per_ms);
        }

        return response_queue.dequeue() catch error.ResponseMissing;
    } else {
        return error.NoRegisteredQueue;
    }
}

pub fn registerHandler(
    self: *QueryRegistry,
    comptime T: type,
    comptime R: type,
    capacity: usize,
) !*concurrency.RingBufferConcurrentQueue(QueryContext(T, R)) {
    self.mutex.lock();
    defer self.mutex.unlock();
    const queue = try self.allocator.create(concurrency.RingBufferConcurrentQueue(QueryContext(T, R)));
    const key = @typeName(QueryContext(T, R));

    queue.* = try concurrency.RingBufferConcurrentQueue(QueryContext(T, R)).init(
        self.allocator,
        capacity,
    );

    const list = try self.registries.getOrPut(key);

    if (!list.found_existing) {
        list.value_ptr.* = std.ArrayList(*anyopaque).init(self.allocator);
    }

    try list.value_ptr.append(@constCast(queue));
    return queue;
}

pub fn processQueryHandlers(
    self: *QueryRegistry,
    comptime T: type,
    comptime R: type,
    comptime handler: fn (request: T) R,
) !void {
    const key = @typeName(QueryContext(T, R));
    const maybe_queue_array = self.registries.getPtr(key);
    if (maybe_queue_array) |queue_array| {
        if (queue_array.items.len == 0) return error.NoRegisteredQueue;

        const queue_ptr = queue_array.items[0];
        const queue: *concurrency.RingBufferConcurrentQueue(QueryContext(T, R)) =
            @ptrCast(@alignCast(queue_ptr));

        while (queue.count() > 0) {
            const ctx = queue.dequeue() catch return error.QueueEmpty;
            const result = handler(ctx.query);
            if (ctx.response_queue) |response_queue| {
                try response_queue.enqueue(result);
            }
        }
    } else {
        return error.NoRegisteredQueue;
    }
}

pub fn QueryContext(comptime QueryType: type, comptime ResonseType: type) type {
    return struct {
        query: QueryType,
        response_queue: ?*concurrency.RingBufferConcurrentQueue(ResonseType),
    };
}

pub fn deinit(self: *QueryRegistry) void {
    self.registries.deinit();
}
