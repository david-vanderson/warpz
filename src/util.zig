const std = @import("std");

pub const PI = std.math.pi;
pub const PI2 = std.math.tau;

pub const TICK = 33;
pub const PORT = 22381;
pub const RB_SIZE = 1000 * 1024;
pub const STR_LEN = 50;
pub const FONT_SIZE = 14;
pub const LINE_HEIGHT = 20;

pub const PLASMA_SPEED = 60.0;

pub fn timeForRepeat(age: i64, repeat: i64, start: i64) bool {
  const r = @rem(age, repeat);
  if (start < r and r <= (start + TICK)) {
    return true;
  }
  else {
    return false;
  }
}

pub fn timeFor(age: i64, start: i64) bool {
  if (start < age and age <= (start + TICK)) {
    return true;
  }
  else {
    return false;
  }
}

pub fn sliceZ(s: anytype) [:0]const u8 {
  return std.mem.sliceTo(s[0..s.len-1:0], 0);
}

pub fn str(s: []const u8) [STR_LEN]u8 {
  var t: [STR_LEN]u8 = [_]u8{0} ** STR_LEN;
  std.mem.copy(u8, &t, s);
  return t;
}

pub fn hash(s: []const u8) u64 {
  return std.hash.Wyhash.hash(0, s);
}

pub const Point = struct {
  x: f32 = 0,
  y: f32 = 0,
};

pub const Posvel = struct {
  const Self = @This();
  pub fn init() Self {
    return Self{
      .p = Point{.x = 0, .y = 0},
      .r = 0, .dx = 0, .dy = 0, .dr = 0};
  }

  p: Point = .{.x = 0, .y = 0},
  r: f32 = 0,
  dx: f32 = 0,
  dy: f32 = 0,
  dr: f32 = 0,
};

var next_id: u64 = 1;
pub fn nextId() u64 {
  defer next_id += 1;
  return next_id;
}

pub fn angleNorm(a: f32) f32 {
  var b: f32 = a;
  while (b >= PI) { b -= PI2; }
  while (b < 0) { b += PI2; }
  return b;
}

pub fn angle(a: Point, b: Point) f32 {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  return std.math.atan2(f32, dy, dx);
}

pub fn distance2(a: Point, b: Point) f32 {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  return (dx * dx) + (dy * dy);
}

pub fn distance(a: Point, b: Point) f32 {
  return @sqrt(distance2(a, b));
}

pub fn speed(a: Posvel) f32 {
  return @sqrt((a.dx * a.dx) + (a.dy * a.dy));
}

pub fn velAngle(a: Posvel) f32 {
  return std.math.atan2(f32, a.dy, a.dx);
}

// as val goes from start to end return 1.0 to 0.0
pub fn linearFade(comptime t: type, val: t, start: t, end: t) f32 {
  if (val <= start) {
    return 1.0;
  }
  else if (val > end) {
    return 0.0;
  }
  else {
    if (t == i64) {
      return @intToFloat(f32, end - val) / @intToFloat(f32, end - start);
    }
    else if (t == f32) {
      return (end - val) / (end - start);
    }
  }
}

// as t goes from 0 to 1, linear interpolate from a to b
pub fn lerp(a: f32, b: f32, t: f32) f32 {
  return a * (1.0 - t) + b * t;
}

pub fn cycletri(t: f32, cycle: f32) f32 {
  const r = std.math.modf(t / cycle);  // goes 0-1,0-1
  const ret = @fabs((@fabs(r.fpart) - 0.5) * 2.0);  // goes 1-0-1
  return ret;
}

pub fn perpv(phi: f32, s1_speed: f32, s1_velAngle: f32, s1_mass: f32, s2_speed: f32, s2_velAngle: f32, s2_mass: f32) f32 {
  return ((s1_speed * @cos(s1_velAngle - phi) * (s1_mass - s2_mass)) + (2.0 * s2_mass * s2_speed * @cos(s2_velAngle - phi))) / (s1_mass + s2_mass);
}
