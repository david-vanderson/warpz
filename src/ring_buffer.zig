const std = @import("std");

const Self = @This();
buf: []u8,
read_idx: usize = 0,
write_idx: usize = 0,
message_idx: usize = 0,

pub const WriteError = error{NoSpaceLeft};
pub const Writer = std.io.Writer(*Self, WriteError, write);

pub fn writer(self: *Self) Writer {
  return .{ .context = self };
}

pub fn startMessage(self: *Self) WriteError!void {
  self.message_idx = self.write_idx;
  // put 4 byte bogus size of message so other threads
  // won't try to read before we are done writing
  const too_big: u32 = @intCast(u32, self.buf.len) + 1;
  try self.writer().writeIntBig(u32, too_big);
}

fn between(self: *Self, start: usize, end: usize) usize {
  if (end < start) {
    return self.buf.len - start + end;
  }
  else {
    return end - start;
  }
}

pub fn endMessage(self: *Self) WriteError!void {
  // overwrite the message_idx 2 bytes with how much we wrote
  const size = @intCast(u32, self.between(self.message_idx, self.write_idx));
  self.buf[self.message_idx] = @truncate(u8, size >> 24);
  self.buf[(self.message_idx + 1) % self.buf.len] = @truncate(u8, size >> 16);
  self.buf[(self.message_idx + 2) % self.buf.len] = @truncate(u8, size >> 8);
  self.buf[(self.message_idx + 3) % self.buf.len] = @truncate(u8, size);
  //std.debug.print("endMessage size {d}\n", .{size});
}

pub fn haveMessage(self: *Self) u32 {
  var i: usize = 0;
  var n: usize = self.read_idx;
  var size: u32 = 0;
  while (i < 4 and n < self.buf.len and n != self.write_idx) : (i += 1) {
    //std.debug.print("haveMessage loop {} {} {} {}\n", .{size, i, n, self.buf[n]});
    switch (i) {
      0 => size += @as(u32, self.buf[n]) << 24,
      1 => size += @as(u32, self.buf[n]) << 16,
      2 => size += @as(u32, self.buf[n]) << 8,
      3 => size += self.buf[n],
      else => unreachable,
    }
    n = (n + 1) % self.buf.len;
  }

  //std.debug.print("haveMessage size {d}\n", .{size});
  if ((size > 0) and (size <= self.between(self.read_idx, self.write_idx))) {
    return size;
  }
  else {
    return 0;
  }
}

pub fn write(self: *Self, bytes: []const u8) WriteError!usize {
  if (bytes.len == 0) return 0;

  var n: usize = 0;
  while (n < bytes.len) : (n += 1) {
    const new_write_idx = (self.write_idx + 1) % self.buf.len;
    if (new_write_idx == self.read_idx) {
      return error.NoSpaceLeft;
    }
    self.buf[self.write_idx] = bytes[n];
    self.write_idx = new_write_idx;
  }

  return n;
}

pub const ReadError = error{};
pub const Reader = std.io.Reader(*Self, ReadError, read);

pub fn reader(self: *Self) Reader {
  return .{ .context = self };
}

pub fn skip(self: *Self, num: u32) !u32 {
  try self.reader().skipBytes(num, Self.Reader.SkipBytesOptions{});
  return num;
}

pub fn read(self: *Self, dest: []u8) ReadError!usize {
  var n: usize = 0;
  while (n < dest.len and self.read_idx != self.write_idx) : (n += 1) {
    dest[n] = self.buf[self.read_idx];
    self.read_idx = (self.read_idx + 1) % self.buf.len;
  }

  return n;
}
