const std = @import("std");
const builtin = @import("builtin");
const opc = @import("open62541");
const nexlog = @import("nexlog");
const Mediator = @import("conman").Mediator;
const tk = @import("tokamak");
const StopSignal = @import("application").control.StopSignal;

const OpcService = @This();

logger: *nexlog.Logger,
stop_signal: *StopSignal,

pub fn init(logger: *nexlog.Logger, stop_signal: *StopSignal) OpcService {
    return OpcService{
        .logger = logger,
        .stop_signal = stop_signal,
    };
}

pub fn startWithThread(self: *OpcService) !std.Thread {
    return std.Thread.spawn(.{}, start, .{self});
}

pub fn start(self: *OpcService) !void {
    var config: opc.UA_ServerConfig = .{};
    const ret_val = opc.UA_ServerConfig_setDefault(&config);
    if (ret_val != opc.UA_STATUSCODE_GOOD) {
        return error.ServerConfigFailed;
    }
    config.applicationDescription.applicationUri = opc.UA_String_fromChars("urn:example:application");
    self.logger.info("Application Uri: {s}", .{config.applicationDescription.applicationUri.data}, nexlog.here(@src()));
    const config_ptr: [*c]opc.UA_ServerConfig = @ptrCast(&config);
    const server = opc.UA_Server_newWithConfig(config_ptr);

    self.logger.info("Creating OPC UA server.", .{}, nexlog.here(@src()));
    if (server) |s| {
        var status: opc.UA_StatusCode = 0;
        defer status = opc.UA_Server_delete(s);
        status = opc.UA_Server_run_startup(s);
        if (status != opc.UA_STATUSCODE_GOOD) {
            return error.ServerRunFailed;
        }

        self.logger.info("OPC server is running", .{}, nexlog.here(@src()));

        while (!self.stop_signal.isSet()) {
            // Run one iteration of the server event loop
            const wait_internal = opc.UA_Server_run_iterate(s, true);

            if (status != opc.UA_STATUSCODE_GOOD) {
                self.logger.err("Server iterate failed with status: {}", .{status}, nexlog.here(@src()));
                break;
            }

            // Small sleep to prevent busy waiting
            const sleep_interval: u64 = @intCast(wait_internal);
            std.Thread.sleep(sleep_interval);
            // std.Thread.sleep(@cwait_internal * std.time.ns_per_ms);
        }

        status = opc.UA_Server_run_shutdown(s);
        self.logger.info("OPC server shutdown", .{}, nexlog.here(@src()));
    } else {
        return error.ServerCreationFailed;
    }

    self.logger.info("OPC thread is exiting", .{}, nexlog.here(@src()));
}
