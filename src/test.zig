const std = @import("std");

const Interface = struct {
  // can call directly: iface.tickFn(iface)
  tickFn: fn(*Interface) *Interface,

  // allows calling: iface.tick()
  pub fn tick(iface: *Interface) *Interface {
    return iface.tickFn(iface);
  }
};

const First = struct {
  // data specific to First
  count: u8,

  interface: Interface,

  fn init() First{
    return .{
      .count = 10,
      .interface = Interface{ .tickFn = myTick }
    };
  }

  fn myTick(iface: *Interface) *Interface {
    const self = @fieldParentPtr(First, "interface", iface);
    self.count += 1;
    std.debug.print("First myTick count {d}\n", .{self.count});

    if (self.count > 11) {
      // switch to Second
      return &second.interface;
    }

    return iface;
  }
};

const Second = struct {
  // data specific to Second
  toggle: bool,

  interface: Interface,

  fn init() Second {
    return .{
      .toggle = true,
      .interface = Interface{ .tickFn = myTick }
    };
  }

  fn myTick(iface: *Interface) *Interface {
    const self = @fieldParentPtr(Second, "interface", iface);
    self.toggle = !self.toggle;
    std.debug.print("Second myTick toggle {}\n", .{self.toggle});

    if (self.toggle) {
      // switch to First
      return &first.interface;
    }

    return iface;
  }
};

var first = First.init();
var second = Second.init();

pub fn main() !void {
  var scenario = &first.interface;

  // example of how copying an interface is wrong
  //var junk: [100]u8 = [_]u8{200} ** 100;
  //var iface = first.interface;
  //var scenario = &iface;

  var i: u8 = 0;
  while (i < 6) : (i += 1) {
    // could call directly:
    // scenario = scenario.tickFn(scenario);

    // this is a bit nicer
    scenario = scenario.tick();
  }
} 

