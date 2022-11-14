const std = @import("std");
const u = @import("../util.zig");
const com = @import("../common.zig");
const Hooks = @import("hooks.zig");
const su = @import("util.zig");


const Self = @This();
hook: Hooks.Hook,

pub fn init() Self {
  return Self{
    .hook = Hooks.Hook{.startFn = myStart, .hookFn = myHook, .annCmdFn = myAnnCmd},
  };
}


fn myStart(hook: *Hooks.Hook, space: *com.Space) *Hooks.Hook {
  const self = @fieldParentPtr(Self, "hook", hook);
  space.prng = std.rand.DefaultPrng.init(std.math.absCast(std.time.timestamp()));
  space.clear();
  space.info.id = u.nextId();
  space.info.time = 0;
  space.info.half_width = 4000.0;
  space.info.half_height = 4000.0;

  space.annotations.append(Hooks.quit_button) catch unreachable;

  for (space.players.items) |*p| {
    p.faction = u.str("");
  }

  //space.ships.append(makeAsteroid(space.info.time, 50.0, .{.p = Point{.x = -1100, .y = -1100}})) catch unreachable;
  //space.ships.append(makeAsteroid(space.info.time, 50.0, .{.p = Point{.x = 100, .y = 100}})) catch unreachable;
  //space.ships.append(makeAsteroid(space.info.time, 50.0, .{.p = Point{.x = 1100, .y = 1100}})) catch unreachable;

  {var i: i32 = 0; while (i < 1000) : (i += 1) {
    var pv = u.Posvel{
      .p = u.Point{
        .x = space.randomBetween(-space.info.half_width, space.info.half_width),
        .y = space.randomBetween(-space.info.half_height, space.info.half_height),
      },
      .r = 0.0,
      .dx = space.randomBetween(-100, 100),
      .dy = space.randomBetween(-100, 100),
      .dr = space.randomBetween(-1, 1),
    };
    var a = com.makeAsteroid(space.info.time, 45.0, pv);
    space.ships.append(a) catch unreachable;
  }}

  return &self.hook;
}

fn myHook(hook: *Hooks.Hook, _: *com.Space, _: *std.ArrayList(com.Message), _: *com.Collider) *Hooks.Hook {
  const self = @fieldParentPtr(Self, "hook", hook);

  return &self.hook;
}

fn myAnnCmd(hook: *Hooks.Hook, ann_cmd: com.AnnotationCommand, space: *com.Space, _: *std.ArrayList(com.Message)) *Hooks.Hook {
  const self = @fieldParentPtr(Self, "hook", hook);

  if (ann_cmd.id == Hooks.quit_button.obj.id) {
    return Hooks.initial.start(space);
  }

  return &self.hook;
}

