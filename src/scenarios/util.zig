const std = @import("std");
const u = @import("../util.zig");
const com = @import("../common.zig");

pub fn orders(phase: u8, faction: [u.STR_LEN]u8, txt: [u.STR_LEN]u8) com.Annotation {
  var a = com.Annotation.init();
  a.obj.id = u.nextId();
  a.phase = phase;
  a.obj.start_time = 0; // no time limit by default
  a.kind = .orders;
  a.faction = faction;
  a.txt = txt;
  return a;
}

pub fn text(phase: u8, faction: [u.STR_LEN]u8, fade: bool, line: f32, txt: [u.STR_LEN]u8) com.Annotation {
  var a = com.Annotation.init();
  a.obj.id = u.nextId();
  a.phase = phase;
  a.faction = faction;
  a.kind = .text;
  a.status = if (fade) .active else .done;
  a.txt = txt;
  a.where = .screen;
  a.obj.pv.p.x = 0.3;
  a.obj.pv.p.y = 0.3;
  a.obj.pv.dy = line;
  a.obj.pv.r = 3000;
  a.obj.pv.dr = 2000;
  return a;
}

pub fn waypoint(phase: u8, faction: [u.STR_LEN]u8, x: f32, y: f32, r: f32, txt: [u.STR_LEN]u8) com.Annotation {
  var a = com.Annotation.init();
  a.obj.id = u.nextId();
  a.phase = phase;
  a.kind = .waypoint;
  a.status = .future;
  a.faction = faction;
  a.obj.pv.p.x = x;
  a.obj.pv.p.y = y;
  a.obj.pv.r = r;
  a.txt = txt;
  return a;
}

pub fn checkWaypoints(space: *com.Space, updates: *std.ArrayList(com.Message)) void {
  for (space.annotations.items) |*a, i| {
    if (a.kind == .waypoint and a.status == .active) {
      for (space.ships.items) |*s| {
        if (std.mem.eql(u8, &a.faction, &s.faction)) {
          const d = s.obj.radius + a.obj.pv.r;
          if (u.distance2(s.obj.pv.p, a.obj.pv.p) < d*d) {
            a.status = .done;
            updates.append(com.Message{.annotation = a.*}) catch unreachable;
            for (space.annotations.items[i+1..]) |*aa| {
              if (aa.kind == .waypoint and aa.status == .future and std.mem.eql(u8, &aa.faction, &a.faction)) {
                aa.status = .active;
                updates.append(com.Message{.annotation = aa.*}) catch unreachable;
                break;
              }
            }
          }
        }
      }
    }
  }
}

pub const Liner = struct {
  const Self = @This();
  rest: []const u8,
  line: []const u8 = undefined,
  linenum: f32 = -1,

  pub fn init(rest: []const u8) Self {
    return .{.rest = rest};
  }

  pub fn next(self: *Self) bool {
    self.linenum += 1.0;
    self.line = self.rest;
    if (self.line.len == 0) {
      return false;
    }
    if (self.line.len > u.STR_LEN) {
      self.line.len = u.STR_LEN;
      while (self.line.len > 0 and self.line[self.line.len - 1] != ' ') {
        self.line.len -= 1;
      }

      if (self.line.len == 0) {
        self.line.len = u.STR_LEN;
      }
    }

    self.rest = self.rest[self.line.len..];
    return true;
  }
};

