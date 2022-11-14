const std = @import("std");
const c = @import("c.zig");
const u = @import("util.zig");
pub const RingBuffer = @import("ring_buffer.zig");


const Sprite = struct {
  frames: []*c.SDL_Texture,
  w: i32,
  h: i32,
  num_players: u8,
  num_frames: u8,
};

pub var sprites: [@typeInfo(SpriteKind).Enum.fields.len]Sprite = undefined;

pub fn loadShips(renderer: *c.SDL_Renderer, gpa: std.mem.Allocator) !void {
  var names: [sprites.len][:0]const u8 = undefined;
  inline for (@typeInfo(SpriteKind).Enum.fields) |field, i| {
    names[i] = field.name[0..:0];
  }
  var fi: u8 = 0;
  while (fi < names.len) : (fi += 1) {
    const name = names[fi];
    if (std.mem.eql(u8, name, "none")) {
      continue;
    }
    var tex: ?*c.SDL_Texture = undefined;
    var frames: [100]*c.SDL_Texture = undefined;
    var f: u8 = 0;
    var players: u8 = 0;
    var frame: u8 = 0;

    // static
    tex = try loadSprite(renderer, name, 0, 0);
    if (tex) |t| {
      frames[f] = t;
      f = 1;
      frame = 1;
    }
    else {
      // animation
      frame = 1;
      while (true) : (frame += 1) {
        tex = try loadSprite(renderer, name, 0, frame);
        if (tex) |t| {
          frames[f] = t;
          f += 1;
        }
        else {
          break;
        }
      }

      if (f == 0) {
        // player and animation
        players = 1;
        outer: while (true) : (players += 1) {
          var ff: u8 = 1;
          while (true) : (ff += 1) {
            tex = try loadSprite(renderer, name, players, ff);
            if (tex) |t| {
              frames[f] = t;
              f += 1;
              frame = ff;
            }
            else if (ff == 1) {
              players -= 1;
              break :outer;
            }
            else {
              break;
            }
          }
        } 
      }
    }

    if (f == 0) {
      std.debug.print("found no sprites with name {s}\n", .{name});
      continue;
    }

    var w: i32 = undefined;
    var h: i32 = undefined;
    _ = c.SDL_QueryTexture(frames[0], 0, 0, &w, &h);
    var sprite = Sprite {
      .frames = try gpa.alloc(*c.SDL_Texture, f),
      .w = w, .h = h, .num_players = players, .num_frames = frame};
    var i: u8 = 0;
    while (i < f) : (i += 1) {
      sprite.frames[i] = frames[i];
    }
    sprites[fi] = sprite;

    //std.debug.print("loaded sprite {s} w/h {d},{d} frames {d}\n", .{name, w, h, sprite.frames.len});
  }
}

fn loadSprite(renderer: *c.SDL_Renderer, name: [:0] const u8, players: u8, frame: u8) !?*c.SDL_Texture {
  var buf = std.mem.zeroes([100:0]u8);
  var fbs = std.io.fixedBufferStream(&buf);
  try fbs.writer().print("images/{s}", .{name});
  if (players > 0) {
    try fbs.writer().print("-p{d}", .{players});
  }
  if (frame > 0) {
    try fbs.writer().print("-{d}", .{frame});
  }
  try fbs.writer().print(".png", .{});
  return loadSpriteFile(renderer, buf[0..:0]);
}

fn loadSpriteFile(renderer: *c.SDL_Renderer, filename: [:0]const u8) ?*c.SDL_Texture {
  const texture: *c.SDL_Texture = c.IMG_LoadTexture(renderer, filename)
    orelse {
    //std.debug.print("Failed to create texture: {s}\n", .{c.SDL_GetError()});
    return null;
  };

  return texture;
}

pub const NewClient = struct {
  const Self = @This();
  id: u64,
  name: [u.STR_LEN]u8,

  pub fn init() Self {
    return Self{
      .id = 0,
      .name = u.str(""),
    };
  }

  pub fn format(self: *const Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try std.fmt.format(writer, "NewClient{{ .id = {}, .name = \"{s}\" }}", .{self.id, self.name});
  }
};


pub const PBolt = struct {
  const Self = @This();
  // id of player who sent this command (overwritten by server)
  pid: u64 = 0,
  // id of the ship the player was on when they sent this command
  ship_id: u64 = 0,
  // angle from center of ship where the plasma starts
  ship_a: f32,
  // drection the plasma is flying
  a: f32,

  pub fn init() Self {
    return Self{
      .ship_a = 0.123456,
      .a = 0.123456,
    };
  }
};

pub const Missile = struct {
  const Self = @This();
  // id of player who sent this command (overwritten by server)
  pid: u64 = 0,
  // id of the ship the player was on when they sent this command
  ship_id: u64 = 0,
  // absolute drection the missile is shot
  a: f32,

  pub fn init() Self {
    return Self{
      .a = 0.123456,
    };
  }
};

pub const Move = struct {
  const Self = @This();
  id: u64 = 0,
  // id of the ship the player was on when they sent this command (if moving player)
  ship_id: u64 = 0,
  to: u64,

  pub fn init() Self {
    return Self {
      .to = 0,
    };
  }
};

pub const RemoteControl = struct {
  const Self = @This();
  // id of player who sent this command (overwritten by server)
  pid: u64 = 0,
  // id of the thing this player is now controlling (0 means nothing)
  rcid: u64,

  pub fn init() Self {
    return Self {
      .rcid = 0,
    };
  }
};

pub const Damage = struct {
  const Self = @This();
  id: u64,
  damage: f32,
  dmgfx: bool,

  pub fn init() Self {
    return Self {
      .id = 0,
      .damage = 1.23,
      .dmgfx = false,
    };
  }
};

pub const Motion = struct {
  const Self = @This();
  id: u64,
  pv: u.Posvel,

  pub fn init() Self {
    return Self {
      .id = 0,
      .pv = u.Posvel.init(),
    };
  }
};

pub const Hold = struct {
  const Self = @This();
  // player id overwritten by server
  // or ship id if being done by ai
  id: u64 = 0,
  held: u8 = 0,
  updown: enum(u8) {
    none = 0,
    down = 1,
    up = 2,
  } = .none,

  pub fn init() Self {
    return Self {
    };
  }
};

pub const Launch = struct {
  const Self = @This();
  pid: u64,

  pub fn init() Self {
    return Self {
      .pid = 0,
    };
  }
};

pub const AnnotationCommand = struct {
  const Self = @This();
  pid: u64 = 0,
  id: u64,

  pub fn init() Self {
    return Self {
      .id = 0,
    };
  }
};

pub const Remove = struct {
  const Self = @This();
  id: u64,

  pub fn init() Self {
    return Self {
      .id = 0,
    };
  }
};

pub const HeartBeat = struct {
  const Self = @This();
  pad: u8 = 0,

  pub fn init() Self {
    return Self{};
  }
};

pub const Message = union(enum(u8)) {
  new_client: NewClient,
  space_info: SpaceInfo,
  update: SpaceInfo,
  player: Player,
  heartbeat: HeartBeat,
  hold: Hold,
  move: Move,
  ship: Ship,
  nebula: Nebula,
  explosion: Explosion,
  pbolt: PBolt,
  missile: Missile,
  plasma: Plasma,
  damage: Damage,
  remove: Remove,
  motion: Motion,
  launch: Launch,
  remote_control: RemoteControl,
  annotation: Annotation,
  ann_cmd: AnnotationCommand,
};

pub const SpriteKind = enum(u8) {
  @"none",
  @"missile",
  @"red-station",
  @"red-cruiser",
  @"red-fighter",
  @"blue-station",
  @"blue-cruiser",
  @"blue-fighter",
  @"asteroid",
  @"engine-rings",
  @"engine-red-fire",
  @"warping",
  @"plasma",
  @"spacesuit",
  @"circle",
  @"circle-outline",
  @"circle-fade",
  @"corner",
  @"nebula",
};

pub const Object = struct {
  const Self = @This();
  // unique id for each game object
  id: u64,
  // millis since space start for age-related stuff (animations, fading, dying)
  start_time: i64,
  // usually true but set to false when an Object needs to be removed
  alive: bool = true,
  // position and velocity info 
  pv: u.Posvel,
  // radius for collisions
  radius: f32,
  // transient: how far inside a nebula this thing is (0 is fully inside, 1 is fully outside)
  in_nebula: f32 = 0.5,
  
  drag_xy: f32 = 0.0,

  pub fn init() Self {
    return Self{
      .id = 0,
      .start_time = 0,
      .pv = u.Posvel.init(),
      .radius = 12.3,
    };
  }

  pub fn drag(dv: f32, dt: f32, coef: f32) f32 {
    const base = 1.0 - coef;
    const newdv = dv * @exp(@log(base) * dt);
    return if (@fabs(newdv) < 0.01) 0.0 else newdv;
  }

  pub fn physics(self: *Self, dt: f32) void {
    self.pv.p.x += dt * self.pv.dx;
    self.pv.p.y += dt * self.pv.dy;
    self.pv.r = u.angleNorm(self.pv.r + dt * self.pv.dr);
  
    if (self.drag_xy != 0.0) {
      self.pv.dx = drag(self.pv.dx, dt, self.drag_xy);
      self.pv.dy = drag(self.pv.dy, dt, self.drag_xy);
    }
  }

  pub fn pushBack(self: *Self, space: *Space, dt: f32) void {
    const thrust = 10.0;
    if (self.pv.p.x > space.info.half_width) {
      self.pv.dx -= thrust * dt * (self.pv.p.x - space.info.half_width);
    }
    else if (self.pv.p.x < -space.info.half_width) {
      self.pv.dx -= thrust * dt * (self.pv.p.x + space.info.half_width);
    }

    if (self.pv.p.y > space.info.half_height) {
      self.pv.dy -= thrust * dt * (self.pv.p.y - space.info.half_height);
    }
    else if (self.pv.p.y < -space.info.half_height) {
      self.pv.dy -= thrust * dt * (self.pv.p.y + space.info.half_height);
    }
  }
};


fn serializeStruct(st: anytype, writer: RingBuffer.Writer) !void {
  //std.debug.print("serializing {}\n", .{st});
  inline for (@typeInfo(@TypeOf(st)).Struct.fields) |f| {
    switch (f.field_type) {
      bool => {
        try writer.writeByte(if (@field(st, f.name)) 1 else 0);
      },
      u8, i8, u16, i16, u32, i32, u64, i64 => {
        try writer.writeIntBig(f.field_type, @field(st, f.name));
      },
      f32 => {
        const x = @bitCast(u32, @field(st, f.name));
        try writer.writeIntBig(@TypeOf(x), x);
      },
      f64 => {
        const x = @bitCast(u64, @field(st, f.name));
        try writer.writeIntBig(@TypeOf(x), x);
      },
      else => {
        switch (@typeInfo(f.field_type)) {
          .Enum => |t| {
            try writer.writeIntBig(t.tag_type, @enumToInt(@field(st, f.name)));
          },
          .Array => |t| {
            if (t.child == u8) {
              _ = try writer.write(&@field(st, f.name));
            }
            else if (@typeInfo(t.child) == .Struct) {
              var i: usize = 0;
              while (i < t.len) : (i += 1) {
                try serializeStruct(@field(st, f.name)[i], writer);
              }
            }
            else {
              unreachable;
            }
          },
          .Struct => {
            try serializeStruct(@field(st, f.name), writer);
          },
          else => {},
        }
      },
    }
  }
}

pub fn serializeMessage(m: Message, writer: RingBuffer.Writer) !void {
  const enum_int = @enumToInt(m);
  try writer.writeByte(enum_int);
  inline for (@typeInfo(@typeInfo(Message).Union.tag_type.?).Enum.fields) |f| {
    if (enum_int == f.value) {
      try serializeStruct(@field(m, f.name), writer);
      return;
    }
  }
}

pub fn deserializeStruct(st: anytype, reader: RingBuffer.Reader, num_bytes: *u32) !void {
  inline for (@typeInfo(@TypeOf(st.*)).Struct.fields) |f| {
    switch (f.field_type) {
      bool => {
        const b: u8 = try reader.readByte();
        @field(st.*, f.name) = if (b == 1) true else false;
        num_bytes.* += 1;
      },
      u8, i8, u16, i16, u32, i32, u64, i64 => {
        @field(st.*, f.name) = try reader.readIntBig(f.field_type);
        num_bytes.* += @sizeOf(f.field_type);
      },
      f32 => {
        @field(st.*, f.name) = @bitCast(f.field_type, try reader.readIntBig(u32));
        num_bytes.* += @sizeOf(f.field_type);
      },
      f64 => {
        @field(st.*, f.name) = @bitCast(f.field_type, try reader.readIntBig(u64));
        num_bytes.* += @sizeOf(f.field_type);
      },
      else => {
        switch (@typeInfo(f.field_type)) {
          .Enum => |t| {
            @field(st.*, f.name) = @intToEnum(f.field_type, try reader.readIntBig(t.tag_type));
            num_bytes.* += @sizeOf(f.field_type);
          },
          .Array => |t| {
            if (t.child == u8) {
              _ = try reader.read(&@field(st, f.name));
              num_bytes.* += t.len;
            }
            else if (@typeInfo(t.child) == .Struct) {
              var i: usize = 0;
              while (i < t.len) : (i += 1) {
                try deserializeStruct(&@field(st, f.name)[i], reader, num_bytes);
              }
            }
            else {
              unreachable;
            }
          },
          .Struct => {
            try deserializeStruct(&@field(st, f.name), reader, num_bytes);
          },
          else => {},
        }
      },
    }
  }
  //std.debug.print("deserialized {}\n", .{st});
}

pub fn deserializeMessage(reader: RingBuffer.Reader, num_bytes: *u32) !Message {
  const sk = try reader.readByte();
  num_bytes.* += 1;
  inline for (@typeInfo(@typeInfo(Message).Union.tag_type.?).Enum.fields) |f, i| {
    if (sk == f.value) {
      var ret = @unionInit(Message, f.name, @typeInfo(Message).Union.fields[i].field_type.init());
      try deserializeStruct(&@field(ret, f.name), reader, num_bytes);
      return ret;
    }
  }

  unreachable;
}

pub const Player = struct {
  const Self = @This();
  pub const Held = enum(u8) {
    none = 0,
    go = 1,
    left = 2,
    right = 4,
  };

  name: [u.STR_LEN]u8,
  faction: [u.STR_LEN]u8,
  id: u64,
  on_ship_id: u64,
  rcid: u64,

  // bitfield of ORed together Helds
  held: u8,

  // time this player last shot a plasma (used for cooldown)
  plasma_last_time: i64,


  pub fn init() Self {
    return Self{
      .name = u.str(""),
      .faction = u.str(""),
      .id = 0,
      .on_ship_id = 0,
      .rcid = 0,
      .held = 0,
      .plasma_last_time = 0,
      };
  }

  pub fn format(self: *const Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try std.fmt.format(writer, "Player{{ .name = \"{s}\", .id = {}, .on_ship_id = {}, .held = {} }}", .{self.name, self.id, self.on_ship_id, self.held});
  }
};

pub const Engine = struct {
  // offset from ship center and rotation
  x: f32 = 0.0,
  y: f32 = 0.0,
  r: f32 = 0.0,

  // scale is multiplied on top of ship's sprite_scale
  sprite: SpriteKind = .none,
  sprite_scale: f32 = 1.0,
};

pub const Ship = struct {
  const Self = @This();
  pub const ShipKind = enum(u8) {
    ship = 0,
    spacesuit = 1,
    missile = 2,
  };
  pub const AIStrat = struct {
    kind: enum(u8) {
      none = 0,
      scout = 1,
      attack = 2,
      retreat = 3,
    } = .none,
    time: i64 = 0,
    id: u64 = 0,
    p: u.Point = u.Point{.x = 0, .y = 0},
  };
  kind: ShipKind = .ship,
  name: [u.STR_LEN]u8 = u.str(""),
  faction: [u.STR_LEN]u8 = u.str(""),
  obj: Object,
  on_ship_id: u64 = 0,
  sprite: SpriteKind,
  sprite_scale: f32 = 1.0,
  engines: [3]Engine,
  mass: f32,
  maxhp: f32,
  hp: f32,
  // distance this ship can always see
  visibility: f32,
  // distance this ship can see when not in a nebula
  // also used by ai for how far it looks for stuff
  radar: f32,
  invincible: bool = false,
  thrust: f32 = 0.0,
  turn_power: f32 = 0.0,
  dmgfx: f32 = 0.0,
  pbolt_power: f32 = 0.0,
  missile_duration: i64 = 0,
  missile_hp: f32 = 0.0,
  hangar: bool = false,
  duration: i64 = 0,
  ai: bool = false,
  ai_time: i64 = 0,
  ai_freq: i64 = 1000,
  ai_held: u8 = 0,
  ai_strat: [5]AIStrat,

  pub fn init() Self {
    return Self{
      .obj = Object.init(),
      .sprite = SpriteKind.circle,
      .engines = .{
        Engine{},
        Engine{},
        Engine{},
      },
      .mass = 12.3,
      .maxhp = 12.3,
      .hp = 12.3,
      .visibility = 12.3,
      .radar = 123.4,
      .ai_strat = .{
        AIStrat{},
        AIStrat{},
        AIStrat{},
        AIStrat{},
        AIStrat{},
      },
    };
  }

  pub fn maxSpeed(self: *Self) f32 {
    const dt = u.TICK / 1000.0;
    return (self.thrust * dt) / (1 - @exp(@log(1 - self.obj.drag_xy) * dt));
  }

  pub fn flying(self: *Self) bool {
    if (self.obj.alive and (self.on_ship_id == 0)) {
      return true;
    }
    else {
      return false;
    }
  }

  pub fn fowFor(self: *Ship, faction: *[u.STR_LEN]u8) bool {
    if (self.flying()
        and (self.kind == .ship or self.kind == .spacesuit)
        and std.mem.eql(u8, &self.faction, faction)) {
      return true;
    }

    return false;
  }

  pub fn steer(self: *Ship, space: *Space, dt: f32, add_effect: bool) void {
    if (self.turn_power > 0) {
      // ships that can turn don't spin freely
      self.obj.pv.dr = 0.0;
    }

    var count_engine: u8 = undefined;
    if (self.kind == .missile) {
      count_engine = 1;
    }
    else {
      count_engine = space.countHeld(self, Player.Held.go);
    }

    var count_left: i32 = space.countHeld(self, Player.Held.left);
    var count_right: i32 = space.countHeld(self, Player.Held.right);

    if (self.thrust > 0 and count_engine > 0) {
      const ddx = self.thrust * @cos(self.obj.pv.r);
      const ddy = self.thrust * @sin(self.obj.pv.r);
      self.obj.pv.dx += ddx * dt;
      self.obj.pv.dy += ddy * dt;
      //std.debug.print("speed {d}\n", .{speed(self.obj.pv)});
      if (add_effect and self.kind == .missile) {
        // add engine effect
        const freq: i64 = if (self.kind == .missile) 200 else 800;
        const age = space.info.time - self.obj.start_time;
        if (u.timeForRepeat(age, freq, 0)) {
          var e = Effect{
            .obj = Object {
              .id = 0,
              .start_time = space.info.time,
              .pv = self.obj.pv,
              .radius = 1.5,
            },
            .duration = if (self.kind == .missile) 200 else 1000,
          };

          e.obj.pv.p.x -= self.obj.radius * @cos(e.obj.pv.r);
          e.obj.pv.p.y -= self.obj.radius * @sin(e.obj.pv.r);
          if (self.kind == .missile) {
            e.obj.pv.dx = -20.0 * @cos(e.obj.pv.r);
            e.obj.pv.dy = -20.0 * @sin(e.obj.pv.r);
          }
          else {
            e.obj.pv.dx *= -1.0;
            e.obj.pv.dy *= -1.0;
          }
          space.backEffects.append(e) catch unreachable;
        }
      }
    }

    if (self.turn_power > 0) {
      // overwrite what we had before, we aren't integrating this
      self.obj.pv.dr = @intToFloat(f32, count_left - count_right) * self.turn_power;
    }
  }

  pub fn format(self: *const Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try std.fmt.format(writer, "Ship{{ .kind = \"{}\", .faction = \"{s}\", .id = {}, .alive = {} }}", .{self.kind, self.faction, self.obj.id, self.obj.alive});
  }

  //pub fn runAIStrat(self: *Self, space: *Space, updates: *std.ArrayList(Message), collider: *Collider) void {
  //  //std.debug.print("ai strat: {}\n", .{self.ai_strat});
  //}

  fn missileAIPathHeld(space: *Space, held: u8) u8 {
    var h: u8 = held;
    h |= @enumToInt(Player.Held.go);  // missiles always go
    const r = space.rand();
    if (r < 0.33) {
      h |= @enumToInt(Player.Held.left);
      h &= ~@enumToInt(Player.Held.right);
    }
    else if (r < 0.66) {
      h |= @enumToInt(Player.Held.right);
      h &= ~@enumToInt(Player.Held.left);
    }
    else {
      h &= ~@enumToInt(Player.Held.right);
      h &= ~@enumToInt(Player.Held.left);
    }

    return h;
  }

  pub fn missileAIFitness(self: *Self, space: *Space, ship_idxs: []usize, fitness: *f32) bool {
    for (ship_idxs) |idx| {
      const s = &space.ships.items[idx];
      const d = u.distance(self.obj.pv.p, s.obj.pv.p);
      if (d > self.radar) {
        continue;
      }

      var foe: bool = true;
      if (std.mem.eql(u8, &self.faction, &s.faction)) {
        foe = false;
      }

      const hitd = self.obj.radius + s.obj.radius;
      const maxd = s.radar; //hitd + 50.0;
      if (d < maxd) {
        var f = (maxd - d) * (maxd - d);
        if (d < hitd) {
          f *= 10;
        }

        if (foe) {
          fitness.* += f;
        }
        else {
          fitness.* -= f;
        }

        if (d < hitd) {
          return true;
        }
      }
    }

    return false;
  }

  pub const Viz = struct {
    p: u.Point,
    f: f32,
    next: ?*Viz = null,
  };

  pub fn runAIPilot(self: *Self, space: *Space, arena: std.mem.Allocator, updates: ?*std.ArrayList(Message), collider: *Collider) ?*Viz {
    const Path = struct {
      pv: u.Posvel,
      orig_held: u8 = 0,
      held: u8 = 0,
      fitness: f32 = 0.0,
      length: f32 = 0.0,
      done: bool = false,
    };

    var ret: ?*Viz = null;

    var ship_idxs = arena.alloc(usize, space.ships.items.len) catch unreachable;
    var iter = collider.near(self.obj.pv.p, self.radar);
    var num_ships: usize = 0;
    while (iter.next()) |e| {
      if (e.kind == .ship and space.ships.items[e.idx].obj.id != self.obj.id) {
        ship_idxs[num_ships] = e.idx;
        num_ships += 1;
      }
    }

    ship_idxs.len = num_ships;

    // save posvels we are about to mess with
    var original_pv = self.obj.pv;
    var original_pvs = arena.alloc(u.Posvel, ship_idxs.len) catch unreachable;
    for (ship_idxs) |idx, i| {
      original_pvs[i] = space.ships.items[idx].obj.pv;
    }

    const orig_held = self.ai_held;

    const predict_freq: i64 = self.ai_freq;
    const predict_time: i64 = self.obj.start_time + self.duration;

    var paths: [16]Path = undefined;
    for (paths) |*p, i| {
      p.* = Path{.pv = self.obj.pv};
      if (i == 0) {
        // first path is always stay the course
        p.orig_held = self.ai_held;
      }
      else {
        p.orig_held = missileAIPathHeld(space, p.held);
      }
      p.held = p.orig_held;
    }

    var time: i64 = space.info.time;
    const dt: f32 = @intToFloat(f32, predict_freq) / 1000.0;
    while (time < predict_time) {
      // predict everybody else forward
      for (ship_idxs) |idx| {
        space.ships.items[idx].obj.physics(dt);
        //var v = arena.create(Viz) catch unreachable;
        //v.next = ret;
        //ret = v;
        //v.p = s.obj.pv.p;
        //v.f = 0.0;
      }

      for (paths) |*p, pi| {
        if (p.done) {
          continue;
        }

        self.obj.pv = p.pv;  // start where we left off
        self.ai_held = p.held;

        // predict us forward
        var i: i32 = 0;
        while (i < 5) : (i += 1) {
          self.obj.physics(dt / 5.0);
          self.steer(space, dt / 5.0, false);
        }

        // run fitness and record in path
        p.done = self.missileAIFitness(space, ship_idxs, &p.fitness);
        p.length += 1;

        //var v = arena.create(Viz) catch unreachable;
        //v.next = ret;
        //ret = v;
        //v.p = self.obj.pv.p;
        //v.f = p.fitness;

        p.pv = self.obj.pv;  // save where we ended
        if (pi != 0) {
          // first path doesn't change
          p.held = missileAIPathHeld(space, p.held);  // perturb future path
        }
      }

      time += predict_freq;
    }
    
    // reset posvels back to before we messed with them
    self.obj.pv = original_pv;
    for (ship_idxs) |idx, i| {
      space.ships.items[idx].obj.pv = original_pvs[i];
    }

    self.ai_held = orig_held;

    // pick best path
    var best_fitness = paths[0].fitness / paths[0].length;
    var best_held = paths[0].orig_held;
    for (paths) |*p| {
      const f = p.fitness / p.length;
      if (f > best_fitness) {
        best_fitness = f;
        best_held = p.orig_held;
      }
    }

    if (best_held != self.ai_held and updates != null) {
      const m = Message{.hold = Hold{.id = self.obj.id, .held = best_held}};
      space.applyChange(m, updates, collider);
    }

    return ret;
  }
};

pub const Annotation = struct {
  const Self = @This();
  kind: enum(u8) {
    button = 0,
    waypoint = 1,
    orders = 2,
    text = 3,
  },
  status: enum(u8) {
    active = 0,  // for text, means fade
    future = 1,  // for text, means no fade
    done = 2,
  },
  where: enum(u8) {
    space = 0,
    // button: x/y are pixels from topleft if positive, botleft if negative
    // text: x/y are fractions of screen
    screen = 1,
    message_queue = 2, // for text, put in message queue
  },
  phase: u8 = 0,
  txt: [u.STR_LEN]u8,
  faction: [u.STR_LEN]u8,
  obj: Object,

  pub fn init() Self {
    return Self{
      .kind = .button,
      .status = .active,
      .where = .space,
      .txt = u.str(""),
      .faction = u.str(""),
      .obj = Object.init(),
    };
  }
};

pub const Plasma = struct {
  const Self = @This();
  obj: Object,

  pub fn init() Self {
    return Self{
      .obj = Object.init(),
    };
  }

  pub fn tick(self: *Self, space: *const Space, dt: f32) void {
    const age = space.info.time - self.obj.start_time;
    if (age > 3000) {
      self.obj.radius -= 1.0 * dt;
    }
  }

  pub fn energyToRadius(e: f32) f32 {
    return 2.0 * @sqrt(e);
  }

  pub fn energy(self: *const Self) f32 {
    const r = self.obj.radius / 2.0;
    return r * r;
  }

  pub fn dead(self: *const Self) bool {
    return self.obj.radius < 1.0;
  }

  pub fn frac(now: i64, last_time: i64) f32 {
    const f = 1.0 - u.linearFade(i64, now, last_time, last_time + 1000);
    return f * f;
  }
};

pub const Explosion = struct {
  const Self = @This();
  obj: Object,
  // maximum radius
  maxradius: f32,
  // how fast radius grows per sec
  expand: f32,
  // damage things take per sec when within radius
  dmg: f32,

  pub fn init() Self {
    return Self{
      .obj = Object.init(),
      .maxradius = 1.23,
      .expand = 1.23,
      .dmg = 1.23,
    };
  }

  pub fn fade(self: *Self) f32 {
    return u.linearFade(f32, self.obj.radius, self.maxradius * 0.33, self.maxradius);
  }

  pub fn damage(self: *Self) f32 {
    return self.dmg * self.fade();
  }

  pub fn dead(self: *Self) bool {
    return self.fade() == 0;
  }
};

pub const Nebula = struct {
  const Self = @This();
  obj: Object,

  pub fn init() Self {
    return Self{
      .obj = Object.init(),
    };
  }
};

pub const Effect = struct {
  const Self = @This();
  obj: Object,
  duration: i32,

  pub fn dead(self: *Self, space: *Space) bool {
    return (space.info.time - self.obj.start_time) > self.duration;
  }
};

pub const Entity = struct {
  const Kind = enum {
    player,
    ship,
    plasma,
    explosion,
    nebula,
  };
  kind: Kind,
  idx: usize,
  next: ?*Entity = null,

  pub fn id(self: *Entity, space: *Space) u64 {
    return switch (self.kind) {
      .player => space.players.items[self.idx].id,
      .ship => space.ships.items[self.idx].obj.id,
      .plasma => space.plasmas.items[self.idx].obj.id,
      .explosion => space.explosions.items[self.idx].obj.id,
      .nebula => space.nebulas.items[self.idx].obj.id,
    };
  }

  pub fn priority(self: *Entity) u8 {
    return switch (self.kind) {
      .nebula => 0,
      .explosion => 1,
      .plasma => 2,
      .ship => 3,
      .player => unreachable,
    };
  }

  pub fn obj(self: *const Entity, space: *Space) *Object {
    return switch (self.kind) {
      .player => unreachable,
      .ship => &space.ships.items[self.idx].obj,
      .plasma => &space.plasmas.items[self.idx].obj,
      .explosion => &space.explosions.items[self.idx].obj,
      .nebula => &space.nebulas.items[self.idx].obj,
    };
  }
};

pub const EntityPair = struct {
  a: Entity,
  b: Entity,
};

pub const SpaceInfo = struct {
  const Self = @This();
  // unique id to disambiguate when we switch spaces
  id: u64,
  // millis since space start
  time: i64,
  half_width: f32,
  half_height: f32,

  pub fn init() Self {
    return Self{
      .id = 0,
      .time = 0,
      .half_width = 0,
      .half_height = 0,
    };
  }

  pub fn minZoom(self: *const Self, screen_width: f32, screen_height: f32) f32 {
    return std.math.min(screen_width / (2.0 * self.half_width * 1.25),
                        screen_height / (2.0 * self.half_height * 1.25));
  }
};

pub const Space = struct {
  const Self = @This();

  info: SpaceInfo,

  prng: std.rand.DefaultPrng,

  players: std.ArrayList(Player),
  ships: std.ArrayList(Ship),
  nebulas: std.ArrayList(Nebula),
  plasmas: std.ArrayList(Plasma),
  explosions: std.ArrayList(Explosion),
  annotations: std.ArrayList(Annotation),
  // only populated on client
  backEffects: std.ArrayList(Effect),
  effects: std.ArrayList(Effect),

  pub fn rand(self: *Self) f32 {
    return self.prng.random().float(f32);
  }

  pub fn randomBetween(self: *Self, a: f32, b: f32) f32 {
    return a + (b - a) * self.rand();
  }

  pub fn init(gpa: std.mem.Allocator) Self {
    return Self{
      .info = SpaceInfo.init(),
      .prng = std.rand.DefaultPrng.init(0),
      .players = std.ArrayList(Player).init(gpa),
      .ships = std.ArrayList(Ship).init(gpa),
      .nebulas = std.ArrayList(Nebula).init(gpa),
      .plasmas = std.ArrayList(Plasma).init(gpa),
      .explosions = std.ArrayList(Explosion).init(gpa),
      .annotations = std.ArrayList(Annotation).init(gpa),
      .backEffects = std.ArrayList(Effect).init(gpa),
      .effects = std.ArrayList(Effect).init(gpa),
    };
  }

  pub fn copyFrom(self: *Self, from: *Self) !void {
    self.info = from.info;
    try self.players.appendSlice(from.players.items);
    try self.ships.appendSlice(from.ships.items);
    try self.nebulas.appendSlice(from.nebulas.items);
    try self.plasmas.appendSlice(from.plasmas.items);
    try self.explosions.appendSlice(from.explosions.items);
    try self.annotations.appendSlice(from.annotations.items);
    try self.backEffects.appendSlice(from.backEffects.items);
    try self.effects.appendSlice(from.effects.items);
  }

  pub fn deinit(self: *Self) void {
    self.players.deinit();
    self.ships.deinit();
    self.nebulas.deinit();
    self.plasmas.deinit();
    self.explosions.deinit();
    self.annotations.deinit();
    self.backEffects.deinit();
    self.effects.deinit();
  }

  pub fn clear(self: *Self) void {
    // don't wipe players
    self.ships.clearAndFree();
    self.nebulas.clearAndFree();
    self.plasmas.clearAndFree();
    self.explosions.clearAndFree();
    self.annotations.clearAndFree();
    self.backEffects.clearAndFree();
    self.effects.clearAndFree();
  }

  pub fn serialize(self: *Self, writer: RingBuffer.Writer) !void {
    try serializeMessage(Message{.space_info = self.info}, writer);
    for (self.players.items) |p| {
      try serializeMessage(Message{.player = p}, writer);
    }
    for (self.ships.items) |s| {
      try serializeMessage(Message{.ship = s}, writer);
    }
    for (self.nebulas.items) |n| {
      try serializeMessage(Message{.nebula = n}, writer);
    }
    for (self.plasmas.items) |p| {
      try serializeMessage(Message{.plasma = p}, writer);
    }
    for (self.explosions.items) |e| {
      try serializeMessage(Message{.explosion = e}, writer);
    }
    for (self.annotations.items) |a| {
      try serializeMessage(Message{.annotation = a}, writer);
    }
  }

  pub fn findPlayer(self: *Self, id: u64) ?*Player {
    for (self.players.items) |*o| {
      if (o.id == id) {
        return o;
      } 
    }

    return null;
  }

  pub fn findShip(self: *Self, id: u64) ?*Ship {
    for (self.ships.items) |*o| {
      if (o.obj.id == id) {
        return o;
      } 
    }

    return null;
  }

  pub fn findTopShip(self: *Self, s: *Ship) *Ship {
    var topShip = s;
    while (topShip.on_ship_id != 0) {
      topShip = self.findShip(topShip.on_ship_id).?;
    }
    return topShip;
  }
  
  pub fn findId(self: *Self, id: u64) ?Entity {
    if (id == 0) {
      return null;
    }

    for (self.players.items) |*o, i| {
      if (o.id == id) {
        return Entity{.kind = .player, .idx = i};
      } 
    }

    for (self.ships.items) |*o, i| {
      if (o.obj.id == id) {
        return Entity{.kind = .ship, .idx = i};
      } 
    }

    for (self.plasmas.items) |*o, i| {
      if (o.obj.id == id) {
        return Entity{.kind = .plasma, .idx = i};
      } 
    }

    return null;
  }

  pub fn countHeld(self: *Self, ship: *Ship, held: Player.Held) u8 {
    var count: u8 = 0;
    for (self.players.items) |*p| {
      if (p.rcid == ship.obj.id or
          (p.rcid == 0 and p.on_ship_id == ship.obj.id)) {
        if ((p.held & @enumToInt(held)) > 0) {
          count += 1;
        }
      }
    }

    if (ship.ai and (ship.ai_held & @enumToInt(held)) > 0) {
      count += 1;
    }

    return count;
  }

  pub fn playerCleanup(self: *Self, p: *Player, updates: *std.ArrayList(Message), collider: ?*Collider) void {
    // remote control message will turn off player holds
    // and detonate missiles/cannonballs if needed
    const m = Message{.remote_control = RemoteControl{.pid = p.id, .rcid = 0}};
    self.applyChange(m, updates, collider);
  }

  pub fn inNebula(self: *Self, p: u.Point) f32 {
    var neb: f32 = 1.0;  // assume outside nebula
    for (self.nebulas.items) |*n| {
      const d = u.distance2(p, n.obj.pv.p);
      const nr = n.obj.radius * n.obj.radius;
      const newneb = 1.0 - u.linearFade(f32, d, 0.6 * nr, 0.9 * nr);
      neb = std.math.min(neb, newneb);
    }
    return neb;
  }

  pub fn setInNebula(self: *Self) void {
    for (self.ships.items) |*s| {
      s.obj.in_nebula = self.inNebula(s.obj.pv.p);
    }
    for (self.plasmas.items) |*p| {
      p.obj.in_nebula = self.inNebula(p.obj.pv.p);
    }
    for (self.explosions.items) |*e| {
      e.obj.in_nebula = self.inNebula(e.obj.pv.p);
    }
    for (self.backEffects.items) |*e| {
      e.obj.in_nebula = self.inNebula(e.obj.pv.p);
    }
    for (self.effects.items) |*e| {
      e.obj.in_nebula = self.inNebula(e.obj.pv.p);
    }
  }

  pub fn tick(self: *Self, updates: ?*std.ArrayList(Message), collider: *Collider) !void {
    self.info.time += u.TICK;
    const dt: f32 = u.TICK / 1000.0;

    for (self.ships.items) |*s, i| {
      s.obj.physics(dt);
      s.steer(self, dt, updates == null);
      s.obj.pushBack(self, dt);
      s.dmgfx = std.math.max(0.0, s.dmgfx - 20.0 * dt);
      if (s.flying()) {
        collider.add(Entity{.kind = .ship, .idx = i});
      }
    }

    for (self.nebulas.items) |*s| {
      s.obj.physics(dt);
    }

    for (self.plasmas.items) |*p, i| {
      p.obj.physics(dt);
      p.obj.pushBack(self, dt);
      p.tick(self, dt);
      if (p.dead()) {
        p.obj.alive = false;
      }
      else {
        collider.add(Entity{.kind = .plasma, .idx = i});
      }
    }

    for (self.explosions.items) |*e, i| {
      e.obj.radius += e.expand * dt;
      if (e.dead()) {
        e.obj.alive = false;
      }
      else {
        collider.add(Entity{.kind = .explosion, .idx = i});
      }
    }

    for (self.backEffects.items) |*e| {
      e.obj.physics(dt);
      if (e.dead(self)) {
        e.obj.alive = false;
      }
    }

    for (self.effects.items) |*e| {
      e.obj.physics(dt);
      if (e.dead(self)) {
        e.obj.alive = false;
      }
    }

    var iter = collider.collide();
    while (iter.next()) |pair| {
      var a = pair.a;
      var b = pair.b;
      if (!a.obj(self).alive or !b.obj(self).alive) {
        continue;
      }
      if (b.priority() < a.priority()) {
        a = pair.b;
        b = pair.a;
      }

      // TODO: adjust mine acceleration if they are close to ships

      if (updates) |ups| {
        try self.collide(a, b, ups, collider);
      }
    }
  }

  pub fn collide(self: *Self, a: Entity, b: Entity, updates: *std.ArrayList(Message), collider: *Collider) !void {
    // a priority is always <= b
    switch (a.kind) {
      .player,
      .nebula,
      => unreachable,
      .explosion => {
        var e = &self.explosions.items[a.idx];
        if (!e.obj.alive) {
          return;
        }
        const dt: f32 = u.TICK / 1000.0;
        const dam = e.dmg * dt * e.fade();
        switch (b.kind) {
          .player,
          .nebula,
          => unreachable,
          .explosion => {},  // no explosion-explosion interaction
          .plasma => {
            var p = &self.plasmas.items[b.idx];
            if (!p.obj.alive) {
              return;
            }
            const m = Message{.damage = Damage{.id = p.obj.id, .damage = dam, .dmgfx = false}};
            self.applyChange(m, updates, collider);
          },
          .ship => {
            var s = &self.ships.items[b.idx];
            if (!s.flying() or s.kind == .spacesuit) {
              // explosions don't hit spacesuits
              return;
            }
            const m = Message{.damage = Damage{.id = s.obj.id, .damage = dam, .dmgfx = true}};
            self.applyChange(m, updates, collider);
          },
        }
      },
      .plasma => {
        var p = &self.plasmas.items[a.idx];
        switch (b.kind) {
          .player,
          .nebula,
          .explosion,
          => unreachable,
          .plasma => {},  // no plasma-plasma interaction
          .ship => {
            var s = &self.ships.items[b.idx];
            if (!s.flying() or s.kind == .spacesuit) {
              // plasmas don't hit spacesuits
              return;
            }

            const damage = p.energy();
            const m = Message{.damage = Damage{.id = p.obj.id, .damage = damage, .dmgfx = false}};
            const m2 = Message{.damage = Damage{.id = s.obj.id, .damage = damage, .dmgfx = false}};
            self.applyChange(m, updates, collider);
            self.applyChange(m2, updates, collider);
          },
        }
      },
      .ship => {
        var s = &self.ships.items[a.idx];
        if (!s.flying()) {
          return;
        }
        switch (b.kind) {
          .player,
          .nebula,
          .explosion,
          .plasma,
          => unreachable,
          .ship => {
            var o = &self.ships.items[b.idx];
            if (!o.flying()) {
              return;
            }
            // get relative velocity of o with respect to s
            const vx = o.obj.pv.dx - s.obj.pv.dx;
            const vy = o.obj.pv.dy - s.obj.pv.dy;

            // get position vector from s to o
            const px = o.obj.pv.p.x - s.obj.pv.p.x;
            const py = o.obj.pv.p.y - s.obj.pv.p.y;

            // only collide ships if they are moving towards each other
            const dot = (vx * px) + (vy * py);
            if (dot <= 0.0) {

              if (s.kind == .missile or o.kind == .missile) {
                if (s.kind == .missile and o.kind == .missile) {
                  const dam = s.maxhp + o.maxhp;
                  const m = Message{.damage = Damage{.id = s.obj.id, .damage = dam, .dmgfx = false}};
                  const m2 = Message{.damage = Damage{.id = o.obj.id, .damage = dam, .dmgfx = false}};
                  self.applyChange(m, updates, collider);
                  self.applyChange(m2, updates, collider);
                }
                else if (s.kind == .missile and o.kind == .ship) {
                  const m = Message{.damage = Damage{.id = s.obj.id, .damage = s.maxhp, .dmgfx = false}};
                  const m2 = Message{.damage = Damage{.id = o.obj.id, .damage = s.maxhp, .dmgfx = true}};
                  self.applyChange(m, updates, collider);
                  self.applyChange(m2, updates, collider);
                }
                else if (o.kind == .missile and s.kind == .ship) {
                  const m = Message{.damage = Damage{.id = o.obj.id, .damage = o.maxhp, .dmgfx = false}};
                  const m2 = Message{.damage = Damage{.id = s.obj.id, .damage = o.maxhp, .dmgfx = true}};
                  self.applyChange(m, updates, collider);
                  self.applyChange(m2, updates, collider);
                }

                return;
              }

              if (std.mem.eql(u8, &s.faction, &o.faction)) {
                if (s.kind == .spacesuit and o.kind == .spacesuit) {
                  // they'll bump off each other
                }
                else if (s.kind == .spacesuit) {
                  for (self.players.items) |*p| {
                    if (p.on_ship_id == s.obj.id) {
                      const m = Message{.move = Move{.id = p.id, .to = o.obj.id}};
                      self.applyChange(m, updates, collider);
                      return;
                    }
                  }
                }
                else if (o.kind == .spacesuit) {
                  for (self.players.items) |*p| {
                    if (p.on_ship_id == o.obj.id) {
                      const m = Message{.move = Move{.id = p.id, .to = s.obj.id}};
                      self.applyChange(m, updates, collider);
                      return;
                    }
                  }
                }
                // try to dock
                else if (s.hangar and (s.mass > o.mass)) {
                  const m = Message{.move = Move{.id = o.obj.id, .to = s.obj.id}};
                  self.applyChange(m, updates, collider);
                  return;
                }
                else if (o.hangar and (o.mass > s.mass)) {
                  const m = Message{.move = Move{.id = s.obj.id, .to = o.obj.id}};
                  self.applyChange(m, updates, collider);
                  return;
                }
              }

              self.collideShips(updates, collider, s, o);
            }
          },
        }
      },
    }
  }

  pub fn collideShips(self: *Self, updates: *std.ArrayList(Message), collider: *Collider, s: *Ship, o: *Ship) void {
    var s_speed = u.speed(s.obj.pv);
    var o_speed = u.speed(o.obj.pv);
    if (s_speed == 0.0 and o_speed == 0.0) {
      // both ships aren't moving but somehow collided
      // maybe they were launched on top of each other?
      // change velocity of less massive one to move towards
      // other so collision code will work

      var s1: *Ship = s;
      var s2: *Ship = o;
      if (s2.mass < s1.mass) {
        std.mem.swap(*Ship, &s1, &s2);
      }

      // s1 new fake velocity as if it came from just touching
      // to where it is right now over 0.2 seconds
      const phi = u.angle(s1.obj.pv.p, s2.obj.pv.p);
      const new_speed = 5.0 * ((s1.obj.radius + s2.obj.radius) - u.distance(s1.obj.pv.p, s2.obj.pv.p));
      s1.obj.pv.dx = new_speed * @cos(phi);
      s1.obj.pv.dy = new_speed * @sin(phi);

      s_speed = u.speed(s.obj.pv);
      o_speed = u.speed(o.obj.pv);
    }

    const phi = u.angle(s.obj.pv.p, o.obj.pv.p);
    const o_phi = u.angle(o.obj.pv.p, s.obj.pv.p);
    const s_velAngle = u.velAngle(s.obj.pv);
    const o_velAngle = u.velAngle(o.obj.pv);
    const perpv1 = u.perpv(phi, s_speed, s_velAngle, s.mass, o_speed, o_velAngle, o.mass);
    const perpv2 = -u.perpv(o_phi, o_speed, o_velAngle, o.mass, s_speed, s_velAngle, s.mass);

    const cosphi = @cos(phi);
    const sinphi = @sin(phi);
    const cosphi2 = @cos(phi + std.math.pi / 2.0);
    const sinphi2 = @sin(phi + std.math.pi / 2.0);
    const s_sin = @sin(s_velAngle - phi);
    const o_sin = @sin(o_velAngle - phi);

    const oldsdx = s.obj.pv.dx;
    const oldsdy = s.obj.pv.dy;
    const oldodx = o.obj.pv.dx;
    const oldody = o.obj.pv.dy;
    s.obj.pv.dx = ((perpv1 * cosphi) + (s_speed * s_sin * cosphi2));
    s.obj.pv.dy = ((perpv1 * sinphi) + (s_speed * s_sin * sinphi2));
    o.obj.pv.dx = ((perpv2 * cosphi) + (o_speed * o_sin * cosphi2));
    o.obj.pv.dy = ((perpv2 * sinphi) + (o_speed * o_sin * sinphi2));

    const m = Message{.motion = Motion{.id = s.obj.id, .pv = s.obj.pv}};
    updates.append(m) catch unreachable;
    const m2 = Message{.motion = Motion{.id = o.obj.id, .pv = o.obj.pv}};
    updates.append(m2) catch unreachable;

    // damage ships by how much their velocities changed
    const sdxch = s.obj.pv.dx - oldsdx;
    const sdych = s.obj.pv.dy - oldsdy;
    const sdam = @sqrt((sdxch * sdxch) + (sdych * sdych)) / 4.0;
    const sm = Message{.damage = Damage{.id = s.obj.id, .damage = sdam, .dmgfx = true}};

    const odxch = o.obj.pv.dx - oldodx;
    const odych = o.obj.pv.dy - oldody;
    const odam = @sqrt((odxch * odxch) + (odych * odych)) / 4.0;
    const om = Message{.damage = Damage{.id = o.obj.id, .damage = odam, .dmgfx = true}};

    self.applyChange(sm, updates, collider);
    self.applyChange(om, updates, collider);
  }

  pub fn cull(self: *Self) void {
    var i: usize = 0;
    while (i < self.ships.items.len) {
      if (self.ships.items[i].obj.alive) {
        i += 1;
      }
      else {
        _ = self.ships.swapRemove(i);
      }
    }

    i = 0;
    while (i < self.plasmas.items.len) {
      if (self.plasmas.items[i].obj.alive) {
        i += 1;
      }
      else {
        _ = self.plasmas.swapRemove(i);
      }
    }

    i = 0;
    while (i < self.explosions.items.len) {
      if (self.explosions.items[i].obj.alive) {
        i += 1;
      }
      else {
        _ = self.explosions.swapRemove(i);
      }
    }

    i = 0;
    while (i < self.backEffects.items.len) {
      if (self.backEffects.items[i].obj.alive) {
        i += 1;
      }
      else {
        _ = self.backEffects.swapRemove(i);
      }
    }

    i = 0;
    while (i < self.effects.items.len) {
      if (self.effects.items[i].obj.alive) {
        i += 1;
      }
      else {
        _ = self.effects.swapRemove(i);
      }
    }

    i = 0;
    while (i < self.annotations.items.len) {
      if (self.annotations.items[i].obj.alive) {
        i += 1;
      }
      else {
        _ = self.annotations.swapRemove(i);
      }
    }
  }


  // apply change from Message m to space while recording all
  // changes that should be sent to clients in updates
  // clients call this with null for updates
  pub fn applyChange(self: *Self, message: Message, updates: ?*std.ArrayList(Message), collider: ?*Collider) void {
    switch (message) {
      .heartbeat => unreachable,
      .player => {
        // new player being added or player info updated
        if (updates) |ups| {
          ups.append(message) catch unreachable;
        }
        for (self.players.items) |*p| {
          if (p.id == message.player.id) {
            p.* = message.player;
            return;
          }
        }
        else {
          self.players.append(message.player) catch unreachable;
        }
      },
      .ship => {
        if (updates) |ups| {
          ups.append(message) catch unreachable;
        }
        self.ships.append(message.ship) catch unreachable;
        if (collider) |col| {
          col.add(Entity{.kind = .ship, .idx = self.ships.items.len - 1});
        }
      },
      .nebula => {
        if (updates) |ups| {
          ups.append(message) catch unreachable;
        }
        self.nebulas.append(message.nebula) catch unreachable;
      },
      .plasma => {
        if (updates) |ups| {
          ups.append(message) catch unreachable;
        }
        self.plasmas.append(message.plasma) catch unreachable;
        if (collider) |col| {
          col.add(Entity{.kind = .plasma, .idx = self.plasmas.items.len - 1});
        }
      },
      .explosion => {
        if (updates) |ups| {
          ups.append(message) catch unreachable;
        }
        self.explosions.append(message.explosion) catch unreachable;
        if (collider) |col| {
          col.add(Entity{.kind = .explosion, .idx = self.explosions.items.len - 1});
        }
      },
      .annotation => {
        if (updates) |ups| {
          ups.append(message) catch unreachable;
        }
        for (self.annotations.items) |*a| {
          if (a.obj.id == message.annotation.obj.id
              or (message.annotation.kind == .orders
                  and a.kind == .orders
                  and std.mem.eql(u8, &a.faction, &message.annotation.faction))) {
            a.* = message.annotation;
            break;
          }
        }
        else {
          self.annotations.append(message.annotation) catch unreachable;
        }
      },
      .hold => |h| {
        if (updates) |ups| {
          ups.append(message) catch unreachable;
        }
        if (self.findId(h.id)) |eid| {
          switch (eid.kind) {
            .plasma,
            .nebula,
            .explosion,
            => unreachable,
            .player => {
              var p = &self.players.items[eid.idx];
              switch (h.updown) {
                .none => p.held = h.held,
                .down => p.held |= h.held,
                .up => p.held &= ~h.held,
              }
            },
            .ship => {
              var s = &self.ships.items[eid.idx];
              s.ai_held = h.held;
            },
          }
        }
      },
      .move => |mm| {
        if (self.findId(mm.id)) |eid| {
          switch (eid.kind) {
            .plasma,
            .nebula,
            .explosion,
            => unreachable,
            .player => {
              var p = &self.players.items[eid.idx];
              
              if (mm.to == (std.math.maxInt(u64) - 1)) {
                // player jumping into spacesuit
                if (self.findShip(p.on_ship_id)) |s| {
                  if (!s.flying()) {
                    std.debug.print("server dropping {} (player tried to jump but ship wasn't flying)\n", .{mm});
                  }
                  else {
                    const ss = makeSpacesuit(self, p.faction, s);
                    const m = Message{.ship = ss};
                    const m2 = Message{.move = Move{.id = p.id, .ship_id = p.on_ship_id, .to = ss.obj.id}};
                    self.applyChange(m, updates, collider);
                    self.applyChange(m2, updates, collider);
                  }
                }
                else {
                  std.debug.print("server dropping {} (player tried to jump but wasn't on a ship)\n", .{mm});
                }
                return;
              }
              
              // normal move
              var killid: u64 = 0;
              if (updates) |_| {
                if (self.findShip(p.on_ship_id)) |s| {
                  if (s.kind == .spacesuit) {
                    // player is moving from a spacesuit so kill it after
                    killid = s.obj.id;
                  }
                }
              }

              p.on_ship_id = mm.to;

              if (updates) |ups| {
                //std.debug.print("player {d} moved to ship {d}\n", .{p.id, mm.to});
                ups.append(message) catch unreachable;
                self.playerCleanup(p, ups, collider);
                if (killid != 0) {
                  const m = Message{.remove = Remove{.id = killid}};
                  self.applyChange(m, updates, collider);
                }
              }
            },
            .ship => {
              var sfrom = &self.ships.items[eid.idx];
              if (self.findShip(mm.to)) |s| {
                // dock sfrom onto s
                sfrom.on_ship_id = s.obj.id;
                // reset position so we'll know if we forget to set it on launch
                sfrom.obj.pv.p = u.Point{.x = 1.23, .y = 1.23};
                if (updates) |ups| {
                  ups.append(message) catch unreachable;
                  for (self.players.items) |*p| {
                    if (p.on_ship_id == sfrom.obj.id) {
                      self.playerCleanup(p, ups, collider);
                    }
                  }
                }
              }
            },
          }
        }
      },
      .remove => |rm| {
        if (updates) |ups| {
          ups.append(message) catch unreachable;
        }
        if (self.findId(rm.id)) |eid| {
          switch (eid.kind) {
            .ship => { 
              self.ships.items[eid.idx].obj.alive = false;
            },
            .player => {
              // remove player
              for (self.players.items) |*q, i| {
                if (rm.id == q.id) {
                  _ = self.players.swapRemove(i);
                  break;
                }
              }
              if (updates) |ups| {
                ups.append(message) catch unreachable;
              }
            },
            else => {
              std.debug.print("don't know how to remove this kind of thing {}\n", .{eid});
            }
          }
        }
      },
      .remote_control => |rc| {
        if (updates) |ups| {
          ups.append(message) catch unreachable;
        }
        if (self.findPlayer(rc.pid)) |p| {
          const old_rcid = p.rcid;
          p.rcid = rc.rcid;

          if (updates) |_| {
            // for any change in rc, reset all holds
            const mhold = Message{.hold = Hold{.id = p.id}};
            self.applyChange(mhold, updates, collider);

            if (rc.rcid == 0) {
              // player is stopping rc, might need to blow up missile
              if (self.findShip(old_rcid)) |s| {
                if (s.kind == .missile) {
                  const m = Message{.damage = Damage{.id = s.obj.id, .damage = s.maxhp, .dmgfx = false}};
                  self.applyChange(m, updates, collider);
                }
              }
              // TODO: might need to blow up cannonball
            }

          }
        }
        else {
          std.debug.print("server dropping {} (couldn't find player)\n", .{rc});
        }
      },
      .pbolt => |pb| {
        // TODO: check if ship is flying
        // TODO: check if ship has pbolt
        if (self.findPlayer(pb.pid)) |player| {
          const frac = Plasma.frac(self.info.time, player.plasma_last_time);
          //std.debug.print("frac {d}\n", .{frac});
          player.plasma_last_time = self.info.time;
          if (player.on_ship_id != pb.ship_id) {
            std.debug.print("server dropping {} (ship_id {d} doesn't match player.on_ship_id {d})\n", .{pb, pb.ship_id, player.on_ship_id});
          }
          else if (self.findShip(player.on_ship_id)) |s| {
            // start with same posvel as ship
            var p = Plasma{
              .obj = Object{
                .id = u.nextId(),
                .start_time = self.info.time,
                .pv = s.obj.pv,
                .radius = Plasma.energyToRadius(std.math.clamp(s.pbolt_power * frac, 1.0, s.pbolt_power)),
              },
            };

            // push position to front of ship and add speed
            const d = s.obj.radius + p.obj.radius;
            p.obj.pv.p.x += d * @cos(pb.ship_a);
            p.obj.pv.p.y += d * @sin(pb.ship_a);
            p.obj.pv.dx += u.PLASMA_SPEED * @cos(pb.a);
            p.obj.pv.dy += u.PLASMA_SPEED * @sin(pb.a);
            p.obj.pv.dr = 0;

            const m = Message{.plasma = p};
            self.applyChange(m, updates, collider);
          }
          else {
            std.debug.print("server dropping {} (player not on a ship)\n", .{pb});
          }
        }
        else {
          std.debug.print("server dropping {} (couldn't find player)\n", .{pb});
        }
      },
      .missile => |m| {
        // TODO: check if ship is flying
        // TODO: check if ship has missile
        if (self.findPlayer(m.pid)) |player| {
          if (player.on_ship_id != m.ship_id) {
            std.debug.print("server dropping {} (ship_id {d} doesn't match player.on_ship_id {d})\n", .{m, m.ship_id, player.on_ship_id});
          }
          else if (self.findShip(player.on_ship_id)) |s| {
            var missile = makeMissile(s, self.info.time);
            missile.obj.pv = s.obj.pv;
            missile.obj.pv.p.x += (s.obj.radius + missile.obj.radius) * @cos(m.a);
            missile.obj.pv.p.y += (s.obj.radius + missile.obj.radius) * @sin(m.a);
            missile.obj.pv.r = m.a;
            missile.obj.pv.dx = missile.maxSpeed() * 0.5 * @cos(m.a);
            missile.obj.pv.dy = missile.maxSpeed() * 0.5 * @sin(m.a);

            const msg = Message{.ship = missile};
            const rcmsg = Message{.remote_control = RemoteControl{.pid = player.id, .rcid = missile.obj.id}};

            self.ships.append(missile) catch unreachable;

            // send missile to clients
            updates.?.append(msg) catch unreachable;

            self.applyChange(rcmsg, updates, collider);
          }
          else {
            std.debug.print("server dropping {} (player not on a ship)\n", .{m});
          }
        }
        else {
          std.debug.print("server dropping {} (couldn't find player)\n", .{m});
        }
      },
      .damage => |dam| {
        if (updates) |ups| {
          ups.append(message) catch unreachable;
        }
        if (self.findId(dam.id)) |entity| {
          switch (entity.kind) {
            .player,
            .nebula,
            .explosion,
            => unreachable,
            .plasma => {
              var p = &self.plasmas.items[entity.idx];
              const orig_radius = p.obj.radius;
              p.obj.radius -= Plasma.energyToRadius(dam.damage);
              if (p.dead()) {
                p.obj.alive = false;
              }
                
              if (updates == null) {
                const e = Effect{
                  .obj = Object {
                    .id = 0,
                    .start_time = self.info.time,
                    .pv = u.Posvel{
                      .p = u.Point { .x = p.obj.pv.p.x, .y = p.obj.pv.p.y },
                      .r = 0.0, .dx = 0.0, .dy = 0.0, .dr = 0.0, },
                    .radius = orig_radius,
                  },
                  .duration = 300,
                };
                self.effects.append(e) catch unreachable;
              }
            },
            .ship => {
              var s = &self.ships.items[entity.idx];
              var sid = s.obj.id;
              if (!s.invincible) {
                s.hp -= dam.damage;

                if (updates == null and dam.dmgfx) {
                  s.dmgfx = std.math.min(12.0, s.dmgfx + dam.damage);
                }
              }

              if (s.hp <= 0) {
                s.obj.alive = false;

                if (updates) |_| {
                  // TODO: dump cargo

                  // kill any ships on this ship (recursively)
                  for (self.ships.items) |*o| {
                    if (o.on_ship_id == sid) {
                      const m = Message{.damage = Damage{.id = o.obj.id, .damage = o.maxhp, .dmgfx = false}};
                      self.applyChange(m, updates, collider);
                      s = &self.ships.items[entity.idx];
                    }
                  }

                  // players on the ship need to be booted onto spacesuits
                  for (self.players.items) |*p| {
                    if (p.on_ship_id == sid) {
                      var topShip = self.findTopShip(s);

                      const ss = makeSpacesuit(self, p.faction, topShip);
                      const m = Message{.ship = ss};
                      const m2 = Message{.move = Move{.id = p.id, .ship_id = p.on_ship_id, .to = ss.obj.id}};
                      self.applyChange(m, updates, collider);
                      self.applyChange(m2, updates, collider);
                      s = &self.ships.items[entity.idx];
                    }
                  }

                  if (s.on_ship_id == 0) {
                    if (s.kind == .missile) {
                      var e = Explosion{
                        .obj = Object {
                          .id = u.nextId(),
                          .start_time = self.info.time,
                          .pv = s.obj.pv,
                          .drag_xy = 0.5,
                          .radius = 2.0,
                        },
                        .maxradius = s.maxhp * 2.0,
                        .expand = 50.0,
                        .dmg = s.maxhp * 4.0,
                      };

                      // explosions don't move
                      e.obj.pv.dx = 0.0;
                      e.obj.pv.dy = 0.0;
                      self.applyChange(Message{.explosion = e}, updates, collider);
                    }
                    else {
                      var energy = s.maxhp;
                      while (energy > 5.0) {
                        const ee = self.randomBetween(5.0, std.math.min(25.0, energy));
                        energy -= ee;
                        const an = self.randomBetween(0.0, u.PI2);
                        const sp = self.randomBetween(10.0, 50.0);

                        var np = Plasma{
                          .obj = Object{
                            .id = u.nextId(),
                            .start_time = self.info.time,
                            .pv = s.obj.pv,
                            .radius = Plasma.energyToRadius(ee),
                          },
                        };

                        np.obj.pv.dx += sp * @cos(an);
                        np.obj.pv.dy += sp * @sin(an);
                        np.obj.pv.dr = 0;

                        const m = Message{.plasma = np};
                        self.applyChange(m, updates, collider);
                      }
                    }
                  }
                }
                else {
                  if (s.on_ship_id == 0 and s.kind != .missile) {
                    const e = Effect{
                      .obj = Object {
                        .id = 0,
                        .start_time = self.info.time,
                        .pv = s.obj.pv,
                        .radius = s.obj.radius,
                      },
                      .duration = 1000,
                    };
                    self.effects.append(e) catch unreachable;
                  }
                }
              }
            },
          }
        }
      },
      .motion => |motion| {
        if (updates) |ups| {
          ups.append(message) catch unreachable;
        }
        if (self.findId(motion.id)) |entity| {
          switch (entity.kind) {
            .player,
            .plasma,
            .explosion,
            .nebula,
            => unreachable,
            .ship => {
              var s = &self.ships.items[entity.idx];
              const old_on_ship_id = s.on_ship_id;
              s.on_ship_id = 0;
              s.obj.pv = motion.pv;

              if (old_on_ship_id != 0) {
                // add to collider because we just launched
                if (collider) |col| {
                  col.add(entity);
                }
              }
            },
          }
        }
      },
      .launch => |lm| blk: {
        const playerOp = self.findId(lm.pid);
        if (playerOp == null) {
          std.debug.print("server dropping {} (couldn't find player)\n", .{lm});
          break :blk;
        }
        const player = &self.players.items[playerOp.?.idx];
        if (player.on_ship_id == 0) {
          std.debug.print("server dropping {} (player not on ship)\n", .{lm});
          break :blk;
        }
        const ship = self.findId(player.on_ship_id);
        if (ship == null) {
          std.debug.print("server dropping {} (can't find ship)\n", .{lm});
          break :blk;
        }
        const mship = self.findId(self.ships.items[ship.?.idx].on_ship_id);
        if (mship == null) {
          std.debug.print("server dropping {} (can't find mothership)\n", .{lm});
          break :blk;
        }

        const s = &self.ships.items[ship.?.idx];
        const ms = &self.ships.items[mship.?.idx];
        const r = u.angleNorm(ms.obj.pv.r + u.PI);
        const d = s.obj.radius + ms.obj.radius + self.randomBetween(9, 11);
        const pv = u.Posvel{
          .p = u.Point { .x = ms.obj.pv.p.x + d * @cos(r),
                       .y = ms.obj.pv.p.y + d * @sin(r), },
          .r = r, 
          .dx = ms.obj.pv.dx + 2.0 * @cos(r),
          .dy = ms.obj.pv.dy + 2.0 * @sin(r),
          .dr = 0.0, };

        const m = Message{.motion = Motion{.id = s.obj.id, .pv = pv}};
        self.applyChange(m, updates, collider);
      },
      .space_info,
      .update,
      .ann_cmd,
      .new_client => unreachable,
    }
  }
};

pub const Collider = struct {
  const Self = @This();
  const square_size: f32 = 200.0;

  arena: std.mem.Allocator,
  space: *Space,
  cols: u32,
  rows: u32,
  squares: []?*Entity,

  pub fn init(arena: std.mem.Allocator, space: *Space) Self {
    const rows = @floatToInt(u32, (space.info.half_height * 2) / square_size);
    const cols = @floatToInt(u32, (space.info.half_width * 2) / square_size);
    //std.debug.print("collider took {d} bytes\n", .{rows * cols * @sizeOf(?*Entity)});
    var ret = Self{
      .arena = arena,
      .space = space,
      .cols = cols,
      .rows = rows,
      .squares = arena.alloc(?*Entity, cols * rows) catch unreachable,
    };
    for (ret.squares) |_, i| {
      ret.squares[i] = null;
    }
    return ret;
  }

  fn pointToSquare(self: *Self, p: u.Point) u32 {
    const y = std.math.max(0, std.math.min(self.space.info.half_height * 2 - 1.0, p.y + self.space.info.half_height));
    const x = std.math.max(0, std.math.min(self.space.info.half_width * 2 - 1.0, p.x + self.space.info.half_width));
    const row = @floatToInt(u32, y / square_size);
    const col = @floatToInt(u32, x / square_size);
    return row * self.cols + col;
  }

  pub fn add(self: *Self, entity: Entity) void {
    const p: u.Point = entity.obj(self.space).pv.p;
    const si = self.pointToSquare(p);

    var e = self.arena.create(Entity) catch unreachable;
    e.* = entity;
    e.next = self.squares[si];
    self.squares[si] = e;
  }

  pub fn debug(self: *Self) void {
    for (self.squares) |s, i| {
      std.debug.print("square {d} {}\n", .{i, s});
    }
  }

  pub fn collide(self: *Self) CollideIterator {
    return .{.collider = self,
             .as = 0,
             .ae = null,
             .bs = 0,
             .be = null};
  }

  pub fn near(self: *Self, p: u.Point, r: f32) NearIterator {
    return .{.collider = self,
             .start = self.pointToSquare(p),
             .size = @floatToInt(i32, @ceil(r / square_size)),
            };
  }
};

pub const NearIterator = struct {
  const Self = @This();
  collider: *Collider,
  start: u32,
  size: i32,
  as: u32 = 0,
  ae: ?*Entity = null,

  pub fn next(self: *Self) ?*Entity {
    //std.debug.print("step\n", .{});
    if (self.ae != null and self.ae.?.next != null) {
      self.ae = self.ae.?.next.?;
      return self.ae;
    }

    // we are at the beginning or ran out of Entities in the list
    // start looking at self.as or greater
    const col = @intCast(i32, self.start % self.collider.cols);
    const row = @intCast(i32, self.start / self.collider.cols);
    var rr = std.math.max(0, row - self.size);
    while (rr <= row+self.size and rr < self.collider.rows) : (rr += 1) {
      var cc = std.math.max(0, col - self.size);
      while (cc <= col+self.size and cc < self.collider.cols) : (cc += 1) {
        //std.debug.print("  rr {d} cc {d}\n", .{rr, cc});
        var si = @intCast(u32, rr) * self.collider.cols + @intCast(u32, cc);
        //std.debug.print("  as {d} si {d}\n", .{self.as, si});
        if (si >= self.as) {
          if (self.collider.squares[si]) |ae| {
            self.ae = ae;
            self.as = si + 1;
            return self.ae;
          }
        }
      }
    }

    return null;
  }
};

pub const CollideIterator = struct {
  const Self = @This();
  collider: *Collider,
  as: u32,
  ae: ?*Entity,
  bs: u32,
  be: ?*Entity,

  fn stepA(self: *Self) void {
    //std.debug.print("stepA\n", .{});
    if (self.ae) |ae| {
      if (ae.next) |n| {
        self.ae = n;
        return;
      }

      self.ae = null;
      self.as += 1;
      //std.debug.print("  as {d}\n", .{self.as});
    }

    while (self.as < self.collider.squares.len and
           self.collider.squares[self.as] == null) {
      self.as += 1;
    }

    if (self.as < self.collider.squares.len) {
      self.ae = self.collider.squares[self.as].?;
      //std.debug.print("  as {d}\n", .{self.as});
      return;
    }
  }

  fn stepB(self: *Self) void {
    //std.debug.print("stepB\n", .{});
    if (self.be == null) {
      // start from a
      self.bs = self.as;
      //std.debug.print("  from a {d}\n", .{self.bs});
      if (self.ae.?.next) |n| {
        self.be = n;
        return;
      }
    }

    if (self.be != null and self.be.?.next != null) {
      self.be = self.be.?.next.?;
      return;
    }

    // we are done with bs
    self.be = null;

    const col = @intCast(i32, self.as % self.collider.cols);
    const row = @intCast(i32, self.as / self.collider.cols);
    //std.debug.print("  row {d} col {d}\n", .{row, col});
    var rr = row;
    while (rr <= row+1 and rr < self.collider.rows) : (rr += 1) {
      var cc = std.math.max(0, col - 1);
      while (cc <= col+1 and cc < self.collider.cols) : (cc += 1) {
        //std.debug.print("  rr {d} cc {d}\n", .{rr, cc});
        var si = @intCast(u32, rr) * self.collider.cols + @intCast(u32, cc);
        //std.debug.print("  bs {d} si {d}\n", .{self.bs, si});
        if (si > self.bs) {
          self.bs = si;
          //std.debug.print("  bs {d}\n", .{self.bs});
          if (self.collider.squares[self.bs]) |be| {
            self.be = be;
            return;
          }
        }
      }
    }

    return;
  }

  pub fn next(self: *Self) ?EntityPair {
    while (true) {
      if (self.ae == null) {
        self.stepA();
        if (self.ae == null) {
          return null;
        }
      }

      self.stepB();
      while (self.be == null) {
        self.stepA();
        if (self.ae == null) {
          return null;
        }
        self.stepB();
      }

      //std.debug.print("collide {d} {d}\n", .{self.as, self.bs});
      const d = self.ae.?.obj(self.collider.space).radius + self.be.?.obj(self.collider.space).radius;
      if (u.distance2(self.ae.?.obj(self.collider.space).pv.p, self.be.?.obj(self.collider.space).pv.p) < (d * d)) {
        return EntityPair{.a = self.ae.?.*, .b = self.be.?.*};
      }
    }
  }
};


pub fn makeSpacesuit(space: *Space, faction: [u.STR_LEN]u8, ship: *Ship) Ship {
  const spriteKind = SpriteKind.@"spacesuit";
  const sprite = sprites[@enumToInt(spriteKind)];
  var ss = Ship.init();
  ss.kind = .spacesuit;
  ss.faction = faction;
  ss.obj = Object {
    .id = u.nextId(),
    .start_time = space.info.time,
    .pv = ship.obj.pv,
    .drag_xy = 0.5,
    .radius = @intToFloat(f32, std.math.max(sprite.w, sprite.h)) / 2.0 - 4,
  };
  ss.sprite = spriteKind;
  ss.mass = 1.0;
  ss.maxhp = 1.0;
  ss.hp = 1.0;
  ss.visibility = 150;
  ss.radar = 150;
  ss.invincible = true;
  ss.thrust = 0.0;
  ss.turn_power = 0.0;

  const r = space.randomBetween(30, 50);
  const side: f32 = if (space.rand() > 0.5) u.PI / 2.0 else -u.PI / 2.0;
  const a = u.angleNorm(ss.obj.pv.r + side + space.randomBetween(-u.PI / 4.0, u.PI / 4.0));
  ss.obj.pv.dx += r * @cos(a);
  ss.obj.pv.dy += r * @sin(a);
  ss.obj.pv.r = 0.0;
  ss.obj.pv.dr = 0.0;

  return ss;
}

pub fn makeMissile(s: *Ship, start_time: i64) Ship {
  const spriteKind = SpriteKind.@"missile";
  const sprite = sprites[@enumToInt(spriteKind)];
  var m = Ship.init();
  m.kind = .missile;
  m.faction = s.faction;
  m.obj = Object {
    .id = u.nextId(),
    .start_time = start_time,
    .pv = u.Posvel.init(),
    .drag_xy = 0.9,
    .radius = @intToFloat(f32, std.math.max(sprite.w, sprite.h)) / 2.0 - 4,
  };
  m.sprite = spriteKind;
  m.mass = 1.0;
  m.maxhp = s.missile_hp;
  m.hp = s.missile_hp;
  m.visibility = 150;
  m.radar = s.radar;
  m.thrust = 300.0;
  m.turn_power = 2.0;
  m.duration = s.missile_duration;
  //m.ai = true;
  m.ai_freq = 500;

  return m;
}

pub const ShipImg = enum {
  red,
  blue,
};

pub fn Cruiser(team: ShipImg, start_time: i64) Ship {
  const spriteKind = if (team == .blue) SpriteKind.@"blue-cruiser" else SpriteKind.@"red-cruiser";
  const sprite = sprites[@enumToInt(spriteKind)];
  var s = Ship.init();
  s.name = u.str("Cruiser");
  s.faction = if (team == .blue) u.str("Blue") else u.str("Red");
  s.obj = Object {
    .id = u.nextId(),
    .start_time = start_time,
    .pv = u.Posvel.init(),
    .drag_xy = 0.2,
    .radius = @intToFloat(f32, std.math.max(sprite.w, sprite.h)) / 2.0 - 4,
  };
  s.sprite = spriteKind;
  s.mass = 100.0;
  s.maxhp = 150.0;
  s.hp = 150.0;
  s.visibility = 200;
  s.radar = 500;
  s.thrust = 20.0;
  s.turn_power = 0.6;
  s.hangar = true;
  s.pbolt_power = 10.0;
  s.missile_duration = 4000;
  s.missile_hp = 10.0;

  if (team == .blue) {
    s.engines = .{
      Engine{.x = -19.0, .y = 18.5, .sprite = SpriteKind.@"engine-rings", .sprite_scale = 1.0},
      Engine{.x = -19.0, .y = -18.5, .sprite = SpriteKind.@"engine-rings", .sprite_scale = 1.0},
      Engine{},
    };
  }
  else {
    s.engines = .{
      Engine{.x = -20.0, .y = 4.5, .sprite = SpriteKind.@"engine-red-fire", .sprite_scale = 0.7},
      Engine{.x = -20.0, .y = -4.5, .sprite = SpriteKind.@"engine-red-fire", .sprite_scale = 0.7},
      Engine{},
    };
  }

  return s;
}

pub fn Station(team: ShipImg, faction: [u.STR_LEN]u8, start_time: i64) Ship {
  const spriteKind = if (team == .blue) SpriteKind.@"blue-station" else SpriteKind.@"red-station";
  const sprite = sprites[@enumToInt(spriteKind)];
  var s = Ship.init();
  s.name = u.str("Station");
  s.faction = faction;
  s.obj = Object {
    .id = u.nextId(),
    .start_time = start_time,
    .pv = u.Posvel.init(),
    .drag_xy = 0.1,
    .radius = @intToFloat(f32, std.math.max(sprite.w, sprite.h)) / 2.0 - 4,
  };
  s.sprite = spriteKind;
  s.mass = 1000.0;
  s.maxhp = 500.0;
  s.hp = 500.0;
  s.visibility = 500;
  s.radar = 1000;
  s.thrust = 0.0;
  s.turn_power = 0.0;
  s.hangar = true;
  s.pbolt_power = 10.0;
  s.missile_duration = 4000;
  s.missile_hp = 10.0;

  return s;
}

pub fn Fighter(team: ShipImg, faction: [u.STR_LEN]u8, start_time: i64) Ship {
  const spriteKind = if (team == .blue) SpriteKind.@"blue-fighter" else SpriteKind.@"red-fighter";
  const sprite = sprites[@enumToInt(spriteKind)];
  var s = Ship.init();
  s.name = u.str("Fighter");
  s.faction = faction;
  s.obj = Object {
    .id = u.nextId(),
    .start_time = start_time,
    .pv = u.Posvel.init(),
    .drag_xy = 0.8,
    .radius = @intToFloat(f32, std.math.max(sprite.w, sprite.h)) / 2.0 - 4,
  };
  s.sprite = spriteKind;
  s.sprite_scale = 20.0 / @intToFloat(f32, sprite.w);
  s.mass = 20.0;
  s.maxhp = 100.0;
  s.hp = 100.0;
  s.visibility = 200;
  s.radar = 300;
  s.thrust = 190.0;
  s.turn_power = 1.8;
  s.pbolt_power = 8.0;
  
  if (team == .blue) {
    s.engines = .{
      Engine{.x = -10.0, .y = 0.0,
        .sprite = SpriteKind.@"engine-rings",
        .sprite_scale = 1.0
      },
      Engine{},
      Engine{},
    };
  }
  else {
    s.engines = .{
      Engine{.x = -11.0, .y = 0.0,
        .sprite = SpriteKind.@"engine-red-fire",
        .sprite_scale = 0.8
      },
      Engine{},
      Engine{},
    };
  }

  return s;
}

pub fn makeAsteroid(start_time: i64, size: f32, pv: u.Posvel) Ship {
  const spriteKind = SpriteKind.@"asteroid";
  const sprite = sprites[@enumToInt(spriteKind)];
  var s = Ship.init();
  s.obj = Object{
    .id = u.nextId(),
    .start_time = start_time,
    .pv = pv,
    .radius = size / 2.0 - 4,
  };
  s.sprite = spriteKind;
  s.sprite_scale = size / @intToFloat(f32, sprite.w);
  s.mass = size * size;
  s.maxhp = 1000.0;
  s.hp = 1000.0;
  s.visibility = 200;
  s.radar = 300;
  s.invincible = true;
  s.turn_power = 0;
  s.thrust = 0;

  return s;
}

