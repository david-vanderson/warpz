const std = @import("std");
const com = @import("../common.zig");

pub const Hook = struct {
  startFn: fn (self: *Hook, space: *com.Space) *Hook,
  hookFn: fn (self: *Hook, space: *com.Space, updates: *std.ArrayList(com.Message), collider: *com.Collider) *Hook,
  annCmdFn: fn (self: *Hook, ann_cmd: com.AnnotationCommand, space: *com.Space, updates: *std.ArrayList(com.Message)) *Hook,

  pub fn start(self: *Hook, space: *com.Space) *Hook {
    return self.startFn(self, space);
  }

  pub fn hook(self: *Hook, space: *com.Space, updates: *std.ArrayList(com.Message), collider: *com.Collider) *Hook {
    return self.hookFn(self, space, updates, collider);
  }

  pub fn annCmd(self: *Hook, space: *com.Space, updates: *std.ArrayList(com.Message)) *Hook {
    return self.annCmdFn(self, space, updates);
  }
};

pub var quit_button: com.Annotation = undefined;

// all scenario hooks
pub var initial: *Hook = undefined;
pub var testing: *Hook = undefined;
pub var pilot_training: *Hook = undefined;
pub var base_defense: *Hook = undefined;

