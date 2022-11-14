const std = @import("std");
const u = @import("../util.zig");
const com =  @import("../common.zig");
const Region = @import("../region.zig");
const Hooks = @import("hooks.zig");
const su = @import("util.zig");

const Self = @This();
hook: Hooks.Hook,
station_id: u64 = 0,
station_p: u.Point = u.Point{.x = 0, .y = 0},
phase: u8 = 1,
phase_start: i64 = 0,

pub fn init() Self {
  return Self{
    .hook = Hooks.Hook{.startFn = myStart, .hookFn = myHook, .annCmdFn = myAnnCmd},
  };
}


const goodFaction = u.str("Blue");

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
    p.faction = goodFaction;
  }

  {
    var region = Region{};
    var c1 = Region.Circle{.p = u.Point{.x = 2200, .y = 2200}, .r = 2200};
    region.addCircle(&c1);
    var c2 = Region.Circle{.p = u.Point{.x = -1100, .y = 3000}, .r = 1800};
    region.addCircle(&c2);
    var c3 = Region.Circle{.p = u.Point{.x = -2600, .y = 3500}, .r = 1500};
    region.addCircle(&c3);
    var c4 = Region.Circle{.p = u.Point{.x = 3000, .y = -500}, .r = 1800};
    region.addCircle(&c4);
    var c5 = Region.Circle{.p = u.Point{.x = 3400, .y = -2200}, .r = 1500};
    region.addCircle(&c5);
    var pi = region.getIterator(650);
    while (pi.next()) |p| {
      var n = com.Nebula{
        .obj = com.Object{
          .id = u.nextId(),
          .start_time = @floatToInt(i64, space.rand() * 100000),
          .pv = u.Posvel{
            .p = u.Point{
              .x = p.x + space.randomBetween(-90, 90),
              .y = p.y + space.randomBetween(-90, 90),
            },
            .r = space.rand(),
            .dx = 0,
            .dy = 0,
            .dr = (space.rand() - 0.5) / 2.0,
          },
          .radius = 500,
        },
      };
      space.nebulas.append(n) catch unreachable;
    }
  }

  var station = com.Station(.blue, goodFaction, space.info.time);
  self.station_id = station.obj.id;
  station.hp = 10;
  station.obj.pv.p.x = -1200;
  station.obj.pv.p.y = -1300;
  station.obj.pv.dr = 0.1;
  station.radar = 10000;  // TEMP
  self.station_p = station.obj.pv.p;
  space.ships.append(station) catch unreachable;

  self.phase = 1;
  self.phase_start = space.info.time;

  return &self.hook;
}

fn myHook(hook: *Hooks.Hook, space: *com.Space, updates: *std.ArrayList(com.Message), collider: *com.Collider) *Hooks.Hook {
  const self = @fieldParentPtr(Self, "hook", hook);

  for (space.players.items) |*p| {
    if (std.mem.eql(u8, &p.faction, &u.str(""))) {
      p.faction = goodFaction;
      space.applyChange(com.Message{.player = p.*}, updates, collider);
      self.newFighter(space, p, updates, collider);
    }
  }

  if (self.phase == 255) {
    return &self.hook;
  }

  var mstation: ?*com.Ship = null;
  if (space.findShip(self.station_id)) |s| {
    mstation = s;
  }
  else {
    // failure, clean up any text/orders
    for (space.annotations.items) |*a| {
      a.obj.alive = false;
      space.applyChange(com.Message{.annotation = a.*}, updates, collider);
    }

    self.phase = 255;
    self.phase_start = space.info.time;

    var t = su.text(self.phase, goodFaction, false, 0, u.str("Station destroyed. Mission failed. Good luck next time!"));
    space.applyChange(com.Message{.annotation = t}, updates, collider);

    var quit_visible = Hooks.quit_button;
    quit_visible.status = .active;
    space.applyChange(com.Message{.annotation = quit_visible}, updates, collider);

    return &self.hook;
  }
    
  const station: *com.Ship = mstation orelse unreachable;

  if (self.phase == 1) {
    if (u.timeFor(space.info.time, self.phase_start + 2000)) {
      var o = su.orders(self.phase, goodFaction, u.str("Scout Waypoints"));
      space.applyChange(com.Message{.annotation = o}, updates, collider);
      var wp = su.waypoint(self.phase, goodFaction, 1300, -1200, 100, u.str("A"));
      wp.status = .active;
      space.applyChange(com.Message{.annotation = wp}, updates, collider);
      space.applyChange(com.Message{.annotation = su.waypoint(self.phase, goodFaction, 400, 600, 100, u.str("B"))}, updates, collider);
      space.applyChange(com.Message{.annotation = su.waypoint(self.phase, goodFaction, -1800, 1800, 100, u.str("C"))}, updates, collider);

      var liner = su.Liner.init("We've been getting some weird readings from the nebula. Scout just inside the edge and keep your eyes open.");
      while (liner.next()) {
        var a = su.text(self.phase, goodFaction, true, liner.linenum, u.str(liner.line));
        a.obj.start_time = space.info.time;
        space.applyChange(com.Message{.annotation = a}, updates, collider);
      }
    }
    
    if (u.timeFor(space.info.time, self.phase_start + 3000)) {
      // clean up phase 1 stuff
      for (space.annotations.items) |*a| {
        if (a.phase == 1) {
          a.obj.alive = false;
          space.applyChange(com.Message{.annotation = a.*}, updates, collider);
        }
      }

      self.phase = 2;
      self.phase_start = space.info.time;
    }
  }

  if (self.phase == 2) {
    if (u.timeFor(space.info.time, self.phase_start)) {
      var o = su.orders(self.phase, goodFaction, u.str("Defend Station"));
      space.applyChange(com.Message{.annotation = o}, updates, collider);

      var liner = su.Liner.init("Raiding party incoming! Fall back and defend the station.");
      while (liner.next()) {
        var a = su.text(self.phase, goodFaction, true, liner.linenum, u.str(liner.line));
        a.obj.start_time = space.info.time;
        space.applyChange(com.Message{.annotation = a}, updates, collider);
      }

      var s = com.Fighter(.red, u.str("Red"), space.info.time);
      s.obj.pv.p.x = 0;
      s.obj.pv.p.y = 0;
      s.ai = true;
      s.ai_strat[0] = com.Ship.AIStrat{
        .kind = .scout,
        .p = station.obj.pv.p,
      };
      space.applyChange(com.Message{.ship = s}, updates, collider);
    }
  }

  su.checkWaypoints(space, updates);

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
      p.faction = u.str("");
      space.applyChange(com.Message{.player = p.*}, updates, null);
    }
  }

  return &self.hook;
}

fn newFighter(self: *Self, space: *com.Space, p: *com.Player, updates: *std.ArrayList(com.Message), collider: *com.Collider) void {
  var f = com.Fighter(.blue, p.faction, space.info.time);
  f.name = p.name;
  f.obj.pv.p.x = self.station_p.x + space.randomBetween(100, 200);
  f.obj.pv.p.y = self.station_p.y + space.randomBetween(100, 200);
  f.radar = 500;  // TEMP
  const m = com.Message{.ship = f};
  const m2 = com.Message{.move = com.Move{.id = p.id, .to = f.obj.id}};
  space.applyChange(m, updates, collider);
  space.applyChange(m2, updates, collider);
}

