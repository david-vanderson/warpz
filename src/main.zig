const std = @import("std");
const client = @import("client.zig");
const server = @import("server.zig");
const gui_test = @import("gui-test.zig");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

pub fn main() !void {

  var run_server: bool = true;
  var run_client: bool = true;
  var run_gui: bool = false;

  var it = std.process.argsWithAllocator(gpa) catch unreachable;
  defer it.deinit();

  while (it.next()) |arg| {
    if (std.mem.eql(u8, arg, "server")) {
      run_client = false;
    }
    else if (std.mem.eql(u8, arg, "client")) {
      run_server = false;
    }
    else if (std.mem.eql(u8, arg, "gui")) {
      run_gui = true;
    }
  }

  if (run_gui) {
    gui_test.main();
    return;
  }

  // load ships so everyone knows the sizes
  // TODO: encode sizes into a resource file
  try client.setup();

  if (run_server and run_client) {
    //const server_thread = try std.Thread.spawn(runServer, {});
    _ = try std.Thread.spawn(.{}, runServer, .{});
    try client.run();
    //serverThread.wait();
  }
  else if (run_client) {
    try client.run();
  }
  else if (run_server) {
    var act = std.os.Sigaction{
        .handler = .{ .sigaction = server.handleSigInt },
        .mask = std.os.empty_sigset,
        .flags = (std.os.SA.SIGINFO | std.os.SA.RESTART | std.os.SA.RESETHAND),
    };

    try std.os.sigaction(std.os.SIG.INT, &act, null);
    try runServer();
  }
}

fn runServer() !void {
  try server.run();
}

