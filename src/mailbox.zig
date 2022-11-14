const std = @import("std");
const RingBuffer = @import("ring_buffer.zig");

const Self = @This();
stream: std.net.Stream,
out: RingBuffer = undefined,
in: RingBuffer = undefined,

pump_out_size: u32 = 0, 

pub fn pumpOut(self: *Self) !void {
  if (self.pump_out_size == 0) {
    self.pump_out_size = self.out.haveMessage();
  }

  while (self.pump_out_size > 0) {
    const s = std.math.min(self.out.read_idx + self.pump_out_size, self.out.buf.len);
    const want_written = s - self.out.read_idx;
    const written = try self.stream.write(self.out.buf[self.out.read_idx..s]);
    self.out.read_idx += written;
    self.out.read_idx %= self.out.buf.len;
    //std.debug.print("pumpOut {d} {d} {d} {d}\n", .{self.pump_out_size, s, want_written, written});
    self.pump_out_size -= @intCast(u32, written);

    if (written < want_written) {
      return;
    }

    if (self.pump_out_size == 0) {
      self.pump_out_size = self.out.haveMessage();
    }
  }
}

pub fn pumpIn(self: *Self) !void {
  //std.debug.print("start pumpIn {d} {d}\n", .{self.in.read_idx, self.in.write_idx});
  while (true) {
    var end = self.in.read_idx;
    if (end == 0) {
      end = self.in.buf.len - 1;
    }
    else {
      end = self.in.read_idx - 1;
    }

    if (end <= self.in.write_idx) {
      end = self.in.buf.len;
    }

    const want_readed = end - self.in.write_idx;
    //std.debug.print("  pumpIn {d} {d} {d}\n", .{self.in.read_idx, self.in.write_idx, end});
    const readed = self.stream.read(self.in.buf[self.in.write_idx..end]) catch |err| switch (err) {
      error.WouldBlock => 0,
      else => return err,
    };
    if (readed == 0) {
      return;
    }
    self.in.write_idx += readed;
    self.in.write_idx %= self.in.buf.len;
    //std.debug.print("  pumpIn read {d} {d} {d}\n", .{end, want_readed, readed});
    if (readed < want_readed) {
      return;
    }
  }
}
