//! Re-export submodules

pub const concurrency = @import("concurrency.zig");
pub const QueryRegistry = @import("QueryRegistry.zig");
pub const EventRegistry = @import("EventRegistry.zig");
pub const Mediator = @import("Mediator.zig");

test {
    _ = @import("concurrency.zig");
}
