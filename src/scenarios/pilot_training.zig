const std = @import("std");
const u = @import("../util.zig");
const com =  @import("../common.zig");
const Region = @import("../region.zig");
const Hooks = @import("hooks.zig");
const su = @import("util.zig");

const Self = @This();
waypoints: [4]com.Annotation,
end_time: i64 = 120000,
extra_time: i64 = 15000,
faction_i: usize,
done: bool,
hook: Hooks.Hook,

pub fn init() Self {
  return Self{
    .waypoints = undefined,
    .done = false,
    .faction_i = 0,
    .hook = Hooks.Hook{.startFn = myStart, .hookFn = myHook, .annCmdFn = myAnnCmd},
  };
}


fn myStart(hook: *Hooks.Hook, space: *com.Space) *Hooks.Hook {
  const self = @fieldParentPtr(Self, "hook", hook);
  space.prng = std.rand.DefaultPrng.init(std.math.absCast(std.time.timestamp()));
  space.clear();
  space.info.id = u.nextId();
  space.info.time = 0;
  space.info.half_width = 2000.0;
  space.info.half_height = 2000.0;

  space.annotations.append(Hooks.quit_button) catch unreachable;

  self.waypoints[0] = su.waypoint(0, u.str(""), 300, -300, 50, u.str("A"));
  self.waypoints[1] = su.waypoint(0, u.str(""), 300, 300, 50, u.str("B"));
  self.waypoints[2] = su.waypoint(0, u.str(""), -300, -300, 50, u.str("C"));
  self.waypoints[3] = su.waypoint(0, u.str(""), -300, 300, 50, u.str("D"));
  self.done = false;
  self.faction_i = 0;

  for (space.players.items) |*p| {
    p.faction = u.str("");
  }

  {var i: i32 = 0; while (i < 70) : (i += 1) {
    const t = space.randomBetween(0, u.PI2);
    const d = space.randomBetween(1000, 1900);
    var pv = u.Posvel{
      .p = u.Point{
        .x = d * @cos(t),
        .y = d * @sin(t),
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

fn myHook(hook: *Hooks.Hook, space: *com.Space, updates: *std.ArrayList(com.Message), collider: *com.Collider) *Hooks.Hook {
  const self = @fieldParentPtr(Self, "hook", hook);

  if (space.info.time > (self.end_time + self.extra_time)) {
    return self.hook.start(space);
  }

  if (space.info.time > self.end_time and !self.done) {
    self.done = true;

    var quit_visible = Hooks.quit_button;
    quit_visible.status = .active;
    space.applyChange(com.Message{.annotation = quit_visible}, updates, collider);

    var t = su.text(0, u.str(""), false, 0, u.str("Time up!  Restarting in \t"));
    t.obj.start_time = self.end_time + self.extra_time;
    space.applyChange(com.Message{.annotation = t}, updates, collider);

    var line: f32 = 2;
    for (space.players.items) |*p| {
      var player_str: [:0]const u8 = "failed";
      for (space.annotations.items) |*a| {
        if (a.kind == .waypoint and a.status == .future and std.mem.eql(u8, &a.faction, &p.faction)) {
          player_str = "succeeded";
          break;
        }
      }

      var tt = su.text(0, u.str(""), false, line, u.str(""));
      _ = std.fmt.bufPrintZ(&tt.txt, "{s}...{s}", .{u.sliceZ(&p.name), player_str}) catch unreachable;
      space.applyChange(com.Message{.annotation = tt}, updates, collider);

      line += 1;
    }
  }

  if (self.done) {
    return &self.hook;
  }

  for (space.players.items) |*p| {
    if (std.mem.eql(u8, &p.faction, &u.str(""))) {
      self.faction_i += 1;
      _ = std.fmt.bufPrintZ(&p.faction, "Trainer {d}", .{self.faction_i}) catch unreachable;
      space.applyChange(com.Message{.player = p.*}, updates, collider);

      for (self.waypoints) |*w, i| {
        var np = w.*;
        np.obj.id = u.nextId();
        np.faction = p.faction;
        np.status = if (i == 0) .active else .future;
        space.applyChange(com.Message{.annotation = np}, updates, collider);
      }

      var o = su.orders(0, p.faction, u.str("\t Scout Waypoints A B C D"));
      o.obj.start_time = self.end_time;
      space.applyChange(com.Message{.annotation = o}, updates, collider);

      var t = su.text(0, p.faction, true, 0, u.str("Scout your waypoints before time is up!"));
      t.obj.start_time = space.info.time;
      space.applyChange(com.Message{.annotation = t}, updates, collider);
    }

    su.checkWaypoints(space, updates);

    if (space.findShip(p.on_ship_id) == null) {
      newFighter(space, p, updates, collider);
    }
  }

  return &self.hook;
}

fn myAnnCmd(hook: *Hooks.Hook, ann_cmd: com.AnnotationCommand, space: *com.Space, updates: *std.ArrayList(com.Message)) *Hooks.Hook {
  const self = @fieldParentPtr(Self, "hook", hook);

  if (ann_cmd.id == Hooks.quit_button.obj.id) {
    return Hooks.initial.start(space);
  }

  if (ann_cmd.id == 0) {
    // player respawn
    if (space.findPlayer(ann_cmd.pid)) |p| {
      for (space.ships.items) |*s| {
        if (s.kind != .spacesuit and std.mem.eql(u8, &p.faction, &s.faction)) {
          // player's ship still there, just put them back on it
          const m = com.Message{.move = com.Move{.id = p.id, .to = s.obj.id}};
          space.applyChange(m, updates, null);
          break;
        }
      }
      else {
        newFighter(space, p, updates, null);
      }
    }
  }


  return &self.hook;
}

fn newFighter(space: *com.Space, p: *com.Player, updates: *std.ArrayList(com.Message), collider: ?*com.Collider) void {
  var f = com.Fighter(.red, p.faction, space.info.time);
  f.name = p.name;
  f.obj.pv.p.x = space.randomBetween(-100, 100);
  f.obj.pv.p.y = space.randomBetween(-100, 100);
  f.radar = 10000;
  const m = com.Message{.ship = f};
  const m2 = com.Message{.move = com.Move{.id = p.id, .to = f.obj.id}};
  space.applyChange(m, updates, collider);
  space.applyChange(m2, updates, collider);
}

