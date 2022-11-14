const std = @import("std");
const u = @import("util.zig");

const Region = @This();

pub const Circle = struct {
  p: u.Point,
  r: f32,
  next: ?*Circle = null,
};

pub const PointIterator = struct {
  region: *Region,
  sep: f32,
  min: u.Point,
  max: u.Point,
  cur: u.Point,
  offset: bool = false,

  pub fn next(self: *PointIterator) ?u.Point {
    while (!self.region.inRegion(self.cur) and (self.cur.y <= self.max.y)) {
      //std.debug.print("pi {d} {d}\n", .{self.cur.x, self.cur.y});
      self.cur.x += self.sep;
      if (self.cur.x > self.max.x) {
        self.cur.y += self.sep / 2;
        self.offset = !self.offset;
        self.cur.x = self.min.x;
        if (self.offset) {
          self.cur.x += self.sep / 2;
        }
      }
    }

    if (self.cur.y > self.max.y) {
      return null;
    }
    else {
      const ret = self.cur;
      self.cur.x += self.sep;
      return ret;
    }
  }
};


circles: ?*Circle = null,

pub fn addCircle(self: *Region, c: *Circle) void {
  c.next = self.circles;
  self.circles = c;
}

pub fn inRegion(self: *Region, p: u.Point) bool {
  var circ = self.circles;
  while (circ) |c| {
    if (u.distance(p, c.p) <= c.r) {
      return true;
    }
    circ = c.next;
  }
  return false;
}

pub fn getIterator(self: *Region, sep: f32) PointIterator {
  var min = u.Point{.x = std.math.inf(f32), .y = std.math.inf(f32)};
  var max = u.Point{.x = -std.math.inf(f32), .y = -std.math.inf(f32)};
  var circ = self.circles;
  while (circ) |c| {
    min.x = std.math.min(min.x, c.p.x - c.r);
    min.y = std.math.min(min.y, c.p.y - c.r);
    max.x = std.math.max(max.x, c.p.x + c.r);
    max.y = std.math.max(max.y, c.p.y + c.r);
    circ = c.next;
  }
  return PointIterator{.region = self, .sep = sep, .min = min, .max = max, .cur = min};
}


