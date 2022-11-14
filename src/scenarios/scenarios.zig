const std = @import("std");
const u = @import("../util.zig");
const com = @import("../common.zig");
const Region = @import("../region.zig");
const Hooks = @import("hooks.zig");
const Testing = @import("testing.zig");
const PilotTraining = @import("pilot_training.zig");
const BaseDefense = @import("base_defense.zig");

// all scenarios
pub var initial: Initial = undefined;
pub var testing: Testing = undefined;
pub var pilot_training: PilotTraining = undefined;
pub var base_defense: BaseDefense = undefined;

pub fn initialize(_: std.mem.Allocator, space: *com.Space) *Hooks.Hook {
  Hooks.quit_button = com.Annotation{
    .kind = .button,
    .status = .future,
    .where = .screen,
    .txt = u.str("Quit"),
    .faction = u.str(""),
    .obj = com.Object{
      .id = u.nextId(),
      .start_time = 0,
      .pv = u.Posvel{
        .p = u.Point{.x = -108, .y = 56},
        .r = 0.0,
        .dx = 100.0,
        .dy = 40.0,
        .dr = 0.0,
      },
      .radius = 12.3,
    },
  };

  initial = Initial.init();
  Hooks.initial = &initial.hook;
  testing = Testing.init();
  Hooks.testing = &testing.hook;
  pilot_training = PilotTraining.init();
  Hooks.pilot_training = &pilot_training.hook;
  base_defense = BaseDefense.init();
  Hooks.base_defense = &base_defense.hook;

  //return Hooks.initial.start(space);
  //return Hooks.testing.start(space);
  return Hooks.base_defense.start(space);
}

const Initial = struct {
  const Self = @This();
  hook: Hooks.Hook,
  pilot_training_button: com.Annotation = undefined,
  base_defense_button: com.Annotation = undefined,

  pub fn init() Self {
    return Self{
      .hook = Hooks.Hook{.startFn = myStart, .hookFn = myHook, .annCmdFn = myAnnCmd},
    };
  }

  fn myStart(hook: *Hooks.Hook, space: *com.Space) *Hooks.Hook {
    const self = @fieldParentPtr(Self, "hook", hook);
    space.prng = std.rand.DefaultPrng.init(6);

    space.clear();
    space.info.id = u.nextId();
    space.info.time = 0;
    space.info.half_width = 4000.0;
    space.info.half_height = 4000.0;

    space.annotations.append(Hooks.quit_button) catch unreachable;

    self.pilot_training_button = com.Annotation{
      .kind = .button,
      .status = .active,
      .where = .space,
      .txt = u.str("Pilot Training"),
      .faction = u.str(""),
      .obj = com.Object{
        .id = u.nextId(),
        .start_time = space.info.time,
        .pv = u.Posvel{
          .p = u.Point{.x = -100, .y = 100},
          .r = 0.0,
          .dx = 100.0,
          .dy = 40.0,
          .dr = 0.0,
        },
        .radius = 12.3,
      },
    };
    space.annotations.append(self.pilot_training_button) catch unreachable;

    self.base_defense_button = com.Annotation{
      .kind = .button,
      .status = .active,
      .where = .space,
      .txt = u.str("Base Defense"),
      .faction = u.str(""),
      .obj = com.Object{
        .id = u.nextId(),
        .start_time = space.info.time,
        .pv = u.Posvel{
          .p = u.Point{.x = -100, .y = 0},
          .r = 0.0,
          .dx = 100.0,
          .dy = 40.0,
          .dr = 0.0,
        },
        .radius = 12.3,
      },
    };
    space.annotations.append(self.base_defense_button) catch unreachable;

    {
      var s = com.Cruiser(.red, space.info.time); 
      //s.radar = 5000;
      s.obj.pv = u.Posvel{
        .p = u.Point{.x = -800.0, .y = 10.0, },
        .r = 1.5, .dx = 0.0, .dy = 0.0, .dr = 0.0,
      };
      //std.debug.print("Red Cruiser max speed {d}\n", .{s.maxSpeed()});
      //s.visibility = 1200;
      //s.radar = 2000;
      space.ships.append(s) catch unreachable;
    }

    {
      var s = com.Cruiser(.blue, space.info.time); 
      s.obj.pv = u.Posvel{
        .p = u.Point{.x = -800.0, .y = 200.0, },
        .r = 1.0, .dx = 0.0, .dy = 0.0, .dr = 0.0,
      };
      space.ships.append(s) catch unreachable;
    }
    
    {
      var i: i32 = 0;
      while (i < 20) : (i += 1) {
        var s = com.Fighter(.red, u.str("Red"), space.info.time);
        s.obj.pv = u.Posvel{
          .p = u.Point { .x = -10.0, .y = -25.0, },
          .r = 1.0, .dx = 0.0, .dy = 0.0, .dr = 0.0,
        };
        //std.debug.print("fighter max speed {d}\n", .{s.maxSpeed()});
        s.on_ship_id = space.ships.items[0].obj.id;
        space.ships.append(s) catch unreachable;
      }
    }

    {
      var region = Region{};
      //var c1 = Region.Circle{.p = u.Point{.x = 500, .y = 0}, .r = 400};
      //region.addCircle(&c1);
      var c2 = Region.Circle{.p = u.Point{.x = 1500, .y = 1000}, .r = 2000};
      region.addCircle(&c2);
      //var c3 = Region.Circle{.p = u.Point{.x = 500, .y = 1200}, .r = 400};
      //region.addCircle(&c3);
      var pi = region.getIterator(800);
      while (pi.next()) |p| {
        //std.debug.print("point {d} {d}\n", .{p.x, p.y});
        //std.time.sleep(100 * std.time.ns_per_ms);
        var pv = u.Posvel{
          .p = u.Point{
            .x = p.x + space.randomBetween(-200, 200),
            .y = p.y + space.randomBetween(-200, 200),
          },
          .r = 0.0,
          .dx = 0.0,
          .dy = 0.0,
          .dr = space.randomBetween(-1, 1),
        };
        const mins: f32 = 25;
        const maxs: f32 = 250;
        const size = space.randomBetween(@log(@log(mins)), @log(@log(maxs)));
        var a = com.makeAsteroid(space.info.time, @exp(@exp(size)), pv);
        space.ships.append(a) catch unreachable;
      }
    }

    {
      var region = Region{};
      var c1 = Region.Circle{.p = u.Point{.x = 1500, .y = 0}, .r = 1500};
      region.addCircle(&c1);
      var pi = region.getIterator(450);
      while (pi.next()) |p| {
        var n = com.Nebula{
          .obj = com.Object{
            .id = u.nextId(),
            .start_time = @floatToInt(i64, space.rand() * 100000),
            .pv = u.Posvel{
              .p = u.Point{
                .x = p.x + space.randomBetween(-50, 50),
                .y = p.y + space.randomBetween(-50, 50),
              },
              .r = space.rand(),
              .dx = 0,
              .dy = 0,
              .dr = (space.rand() - 0.5) / 2.0,
            },
            .radius = 300,
          },
        };
        space.nebulas.append(n) catch unreachable;
      }
    }

    {
      var i: i32 = 0;
      while (i < 2) : (i += 1) {
        const spriteKind = com.SpriteKind.@"asteroid";
        const sprite = com.sprites[@enumToInt(spriteKind)];
        const size = space.rand() * 100.0;
        var a = com.Ship.init();
        a.obj = com.Object{
          .id = u.nextId(),
          .start_time = space.info.time,
          .pv = u.Posvel{
            .p = u.Point{
            .x = space.rand() * 100.0 - 100,
            .y = space.rand() * 100.0 - 100},
            .r = space.rand(),
            .dx = space.rand() * 100.0 - 50,
            .dy = space.rand() * 100.0 - 50,
            .dr = space.rand(),
          },
          .radius = size / 2.0 - 4,
        };
        a.sprite = spriteKind;
        a.sprite_scale = size / @intToFloat(f32, sprite.w);
        a.mass = size * size;
        a.maxhp = 100.0;
        a.hp = 100.0;
        a.visibility = 200;
        a.radar = 300;
        a.turn_power = 0;
        a.thrust = 0;
        space.ships.append(a) catch unreachable;
      }
    }

    //{var i: u32 = 0; while (i < 10) : (i += 1) {
    //  var n = com.Nebula{
    //    .obj = com.Object{
    //      .id = u.nextId(),
    //      .start_time = @floatToInt(i64, space.rand() * 100000),
    //      .pv = u.Posvel{
    //        .p = u.Point{
    //        //.x = space.rand() * 100.0 - 100,
    //        //.y = space.rand() * 100.0 - 100},
    //        .x = 400.0 * @intToFloat(f32, i),
    //        .y = 400.0 * @intToFloat(f32, (i % 2))},
    //        .r = space.rand(),
    //        .dx = 0,
    //        .dy = 0,
    //        .dr = space.rand() / 10.0,
    //      },
    //      .radius = 500,
    //    },
    //  };
    //  space.nebulas.append(n) catch unreachable;
    //}}

    return &self.hook;
  }

  fn myHook(hook: *Hooks.Hook, space: *com.Space, updates: *std.ArrayList(com.Message), collider: *com.Collider) *Hooks.Hook {
    const self = @fieldParentPtr(Self, "hook", hook);

    var i: usize = 0;
    while (i < space.players.items.len) : (i += 1) {
      if (space.info.time > 200 and space.findShip(space.players.items[i].on_ship_id) == null) {
        space.players.items[i].faction = space.ships.items[i].faction;
        space.applyChange(com.Message{.player = space.players.items[i]}, updates, collider);
        var m2 = com.Message{.move = com.Move{.id = space.players.items[i].id, .to = space.ships.items[i].obj.id}};
        space.applyChange(m2, updates, collider);
      }
    }

    if (false and u.timeFor(space.info.time, 1000000, 10000)) {
      // restart scenario
      //self.hook.start(space);
    }

    return &self.hook;
  }

  fn myAnnCmd(hook: *Hooks.Hook, ann_cmd: com.AnnotationCommand, space: *com.Space, updates: *std.ArrayList(com.Message)) *Hooks.Hook {
    const self = @fieldParentPtr(Self, "hook", hook);

    if (ann_cmd.id == 0) {
      // player respawn
      if (space.findPlayer(ann_cmd.pid)) |p| {
        if (space.findShip(p.on_ship_id)) |s| {
          if (s.kind == .spacesuit) {
            const m = com.Message{.move = com.Move{.id = p.id, .to = space.ships.items[0].obj.id}};
            space.applyChange(m, updates, null);
          }
        }
      }
    }

    if (ann_cmd.id == self.pilot_training_button.obj.id) {
      std.debug.print("Switching scenario to Pilot Training\n", .{});
      return Hooks.pilot_training.start(space);
    }

    if (ann_cmd.id == self.base_defense_button.obj.id) {
      std.debug.print("Switching scenario to Base Defense\n", .{});
      return Hooks.base_defense.start(space);
    }

    if (ann_cmd.id == Hooks.quit_button.obj.id) {
      std.debug.print("Restarting scenario Initial\n", .{});
      return Hooks.initial.start(space);
    }

    return &self.hook;
  }
};


