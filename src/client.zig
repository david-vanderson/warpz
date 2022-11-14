const builtin = @import("builtin");
const std = @import("std");
const c = @import("c.zig");
const Mailbox = @import("mailbox.zig");
const u = @import("util.zig");
const com = @import("common.zig");

var screen_width: f32 = 1280;
var screen_height: f32 = 520;
var scale: f32 = 1.0;
var fullscreen: i32 = 0;
var fullscreen_width: f32 = 0;
var fullscreen_height: f32 = 0;
var tab_view: bool = false;

var debug_view: bool = false;
var debug_players: u8 = 0;

var next_id: u64 = 1;
fn client_nextId() u64 {
  defer next_id += 1;
  return next_id;
}

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();


fn stoplightColor(val: f32, max: f32) c.SDL_Color {
  if (val < 0.33 * max) {
    return c.SDL_Color{.r = 255, .g = 0, .b = 0, .a = 255};
  }
  else if (val < 0.66 * max) {
    return c.SDL_Color{.r = 255, .g = 255, .b = 0, .a = 255};
  }
  else {
    return c.SDL_Color{.r = 0, .g = 255, .b = 0, .a = 255};
  }
}

pub fn linearColor(x: c.SDL_Color, y: c.SDL_Color, frac: f32) c.SDL_Color {
  const r = @intToFloat(f32, x.r) * frac + @intToFloat(f32, y.r) * (1 - frac);
  const g = @intToFloat(f32, x.g) * frac + @intToFloat(f32, y.g) * (1 - frac);
  const b = @intToFloat(f32, x.b) * frac + @intToFloat(f32, y.b) * (1 - frac);
  const a = @intToFloat(f32, x.a) * frac + @intToFloat(f32, y.a) * (1 - frac);
  return c.SDL_Color{
    .r = @floatToInt(u8, std.math.clamp(r, 0, 255)),
    .g = @floatToInt(u8, std.math.clamp(g, 0, 255)),
    .b = @floatToInt(u8, std.math.clamp(b, 0, 255)),
    .a = @floatToInt(u8, std.math.clamp(a, 0, 255)),
  };
}

fn setSDLRenderColor(color: c.SDL_Color) void {
  _ = c.SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
}

fn drawShip(ship: *com.Ship, space: *com.Space, alpha: f32, camera: Camera) c.SDL_FRect {
  const screenPt = space2Screen(camera, ship.obj.pv.p);
  const sprite = com.sprites[@enumToInt(ship.sprite)];
  const w = @intToFloat(f32, sprite.w) * camera.zoom * ship.sprite_scale;
  const h = @intToFloat(f32, sprite.h) * camera.zoom * ship.sprite_scale;
  const desr = c.SDL_FRect{
    .x = screenPt.x - (w / 2.0),
    .y = screenPt.y - (h / 2.0),
    .w = w,
    .h = h,
  };

  var red: u8 = 255;

  if (ship.hp < ship.maxhp and ship.kind != .missile) {
    const frac = std.math.max(0.0, ship.hp / ship.maxhp);
    if (frac < 0.5) {
      const age = @intToFloat(f32, space.info.time - ship.obj.start_time);
      const t = u.cycletri(age, 2500.0);
      const x = u.lerp(frac * 1.8, 1.0, t);
      red = @floatToInt(u8, std.math.clamp(255.0 * x, 0.0, 255.0));
    }
  }

  _ = c.SDL_SetTextureAlphaMod(sprite.frames[0], @floatToInt(u8, alpha * 255));
  _ = c.SDL_SetTextureColorMod(sprite.frames[0], 255, red, red);
  _ = c.SDL_RenderCopyExF(renderer, sprite.frames[0], 0, &desr, ship.obj.pv.r * -180.0 / u.PI, 0, c.SDL_FLIP_NONE);

  var count_engine: u8 = space.countHeld(ship, com.Player.Held.go);
  count_engine += debug_players;

  if (count_engine > 0) {
    count_engine -= 1;
    for (ship.engines) |engine| {
      if (engine.sprite != .none) {
        const spr = com.sprites[@enumToInt(engine.sprite)];
        const r = u.angleNorm(ship.obj.pv.r + engine.r);
        const ew = @intToFloat(f32, spr.w) * camera.zoom * ship.sprite_scale * engine.sprite_scale;
        const eh = @intToFloat(f32, spr.h) * camera.zoom * ship.sprite_scale * engine.sprite_scale;
        const edesr = c.SDL_FRect{
          .x = screenPt.x + (engine.x * camera.zoom * ship.sprite_scale * @cos(ship.obj.pv.r)) - (engine.y * camera.zoom * ship.sprite_scale * @sin(ship.obj.pv.r)) - ((ew / 2.0) * @cos(r)) - (ew / 2.0),
          .y = screenPt.y - (engine.x * camera.zoom * ship.sprite_scale * @sin(ship.obj.pv.r)) - (engine.y * camera.zoom * ship.sprite_scale * @cos(ship.obj.pv.r)) + ((ew / 2.0) * @sin(r)) - (eh / 2.0),
          .w = ew,
          .h = eh,
        };

        const p = std.math.min(count_engine, spr.num_players-1);
        const age = space.info.time - ship.obj.start_time;
        const frame: usize = @intCast(usize, @mod(@divFloor(age, 100), spr.num_frames));
        const f = p * spr.num_frames + frame;

        _ = c.SDL_SetTextureAlphaMod(spr.frames[f], @floatToInt(u8, alpha * 255));
        _ = c.SDL_SetTextureColorMod(spr.frames[f], 255, red, red);
        _ = c.SDL_RenderCopyExF(renderer, spr.frames[f], 0, &edesr, r * -180.0 / u.PI, 0, c.SDL_FLIP_NONE);
      }
    }
  }

  return desr;
}


fn drawPlasma(plasma: *com.Plasma, fowa: f32, space: *com.Space, camera: Camera) void {
  const screenPt = space2Screen(camera, plasma.obj.pv.p);
  const sprite = com.sprites[@enumToInt(com.SpriteKind.plasma)];
  // add 2 to plasma size for transparent pixel border
  const zoom = (camera.zoom * 2.0 * (plasma.obj.radius + 1.0)) / @intToFloat(f32, sprite.w);
  const w = @intToFloat(f32, sprite.w) * zoom;
  const h = @intToFloat(f32, sprite.h) * zoom;
  const desr = c.SDL_FRect{
    .x = screenPt.x - (w / 2.0),
    .y = screenPt.y - (h / 2.0),
    .w = w,
    .h = h,
  };

  const age = space.info.time - plasma.obj.start_time;
  const t = @mod(age, 1000);
  const r = u.PI2 * @intToFloat(f32, t) / 1000.0;

  _ = c.SDL_SetTextureAlphaMod(sprite.frames[0], @floatToInt(u8, fowa * 255));
  _ = c.SDL_RenderCopyExF(renderer, sprite.frames[0], 0, &desr, r * -180.0 / u.PI, 0, c.SDL_FLIP_NONE);
}

fn drawNebula(nebula: *com.Nebula, space: *com.Space, camera: Camera) void {
  const screenPt = space2Screen(camera, nebula.obj.pv.p);
  const sprite = com.sprites[@enumToInt(com.SpriteKind.nebula)];

  const size = camera.zoom * nebula.obj.radius * 2.0;
  const w = size;
  const h = size;
  const desr = c.SDL_FRect{
    .x = screenPt.x - (w / 2.0),
    .y = screenPt.y - (h / 2.0),
    .w = w,
    .h = h,
  };

  const age = @intToFloat(f32, space.info.time - nebula.obj.start_time);
  const r = @floatToInt(u8, 100 + 50 * u.cycletri(age, 17000));
  const g = @floatToInt(u8, 100 + 50 * u.cycletri(age, 19000));
  const b = @floatToInt(u8, 100 + 50 * u.cycletri(age, 23000));

  const color = c.SDL_Color{.r = r, .g = g, .b = b, .a = 80};

  _ = c.SDL_SetTextureAlphaMod(sprite.frames[0], color.a);
  _ = c.SDL_SetTextureColorMod(sprite.frames[0], color.r, color.g, color.b);
  _ = c.SDL_RenderCopyExF(renderer, sprite.frames[0], 0, &desr, nebula.obj.pv.r * -180.0 / u.PI, 0, c.SDL_FLIP_NONE);
}

fn drawBackEffect(effect: *com.Effect, fowa: f32, space: *com.Space, camera: Camera) void {
  const age = space.info.time - effect.obj.start_time;
  const agep = u.linearFade(i64, age, 0, effect.duration);
  // effect size starts at 0.75 radius and goes to 1.5 radius 
  const size = ((1.0 - agep) * 0.75 + 0.75) * effect.obj.radius;
  const a = @floatToInt(u8, agep * 255 * fowa);
  const white = c.SDL_Color{.r = 255, .g = 255, .b = 255, .a = a};
  const red = c.SDL_Color{.r = 255, .g = 0, .b = 0, .a = a};
  const color = linearColor(white, red, agep);
  drawCircle(camera, effect.obj.pv.p, size, com.SpriteKind.circle, color);
}

fn drawEffect(effect: *com.Effect, fowa: f32, space: *com.Space, camera: Camera) void {
  const age = space.info.time - effect.obj.start_time;
  const agep = u.linearFade(i64, age, 0, effect.duration);
  // effect size starts at 0.75 radius and goes to 1.5 radius 
  const size = ((1.0 - agep) * 0.75 + 0.75) * effect.obj.radius;
  drawCircle(camera, effect.obj.pv.p, size, com.SpriteKind.circle, c.SDL_Color{.r = 255, .g = 255, .b = 0, .a = @floatToInt(u8, agep * 255 * fowa)});
}

fn drawExplosion(e: *com.Explosion, fowa: f32, camera: Camera) void {
  const z = std.math.clamp(e.obj.radius / e.maxradius, 0.0, 1.0);
  const a = @floatToInt(u8, e.fade() * 255 * fowa);
  const white = c.SDL_Color{.r = 255, .g = 255, .b = 255, .a = a};
  const orange = c.SDL_Color{.r = 255, .g = 140, .b = 0, .a = a};
  const color = linearColor(orange, white, z*z);
  drawCircle(camera, e.obj.pv.p, e.obj.radius, com.SpriteKind.circle, color);
}

fn drawCircle(camera: Camera, p: u.Point, r: f32, spr_kind: com.SpriteKind, color: c.SDL_Color) void {
  const screenPt = space2Screen(camera, p);
  const sprite = com.sprites[@enumToInt(spr_kind)];

  const size = camera.zoom * r * 2.0;
  const w = size;
  const h = size;
  const desr = c.SDL_FRect{
    .x = screenPt.x - (w / 2.0),
    .y = screenPt.y - (h / 2.0),
    .w = w,
    .h = h,
  };

  _ = c.SDL_SetTextureAlphaMod(sprite.frames[0], color.a);
  _ = c.SDL_SetTextureColorMod(sprite.frames[0], color.r, color.g, color.b);
  _ = c.SDL_RenderCopyExF(renderer, sprite.frames[0], 0, &desr, 0, 0, c.SDL_FLIP_NONE);
}

fn space2Screen(camera: Camera, p: u.Point) u.Point {
  return u.Point {
    .x = (screen_width / 2) + camera.zoom * (p.x - camera.center.x),
    .y = (screen_height / 2) + camera.zoom * (camera.center.y - p.y),
  };
}

fn screen2Space(camera: Camera, p: u.Point) u.Point {
  return u.Point {
    .x = (p.x - (screen_width / 2)) / camera.zoom + camera.center.x,
    .y = -(p.y - (screen_height / 2)) / camera.zoom + camera.center.y,
  };
}

fn space2ScreenCanon(camera: Camera, p: u.Point) u.Point {
  return u.Point {
    .x = camera.zoom * (p.x - camera.center.x),
    .y = camera.zoom * (p.y - camera.center.y),
  };
}

fn screenCanon2Space(camera: Camera, p: u.Point) u.Point {
  return u.Point {
    .x = p.x / camera.zoom + camera.center.x,
    .y = p.y / camera.zoom + camera.center.y,
  };
}


const Camera = struct {
  const Self = @This();
  // 0 before we are assigned an id by the server
  player_id: u64,
  mode: enum{
    player_follow,
    free_drag,
    sector_view,
  },
  center: u.Point,  // center_true but with dmgfx added
  center_true: u.Point,
  zoom: f32,  // zoom we render with
  zoom_sector_saved: f32,  // save zoom when showing sector
  sector_view_point: u.Point,  // when showing sector we are leaving this point
  in_hangar: bool,  // showing the hangar of a ship?

  pub fn setZoom(self: *Self, space_info: com.SpaceInfo, zoom: f32) void {
    const minZoom = space_info.minZoom(screen_width, screen_height);
    self.zoom = std.math.clamp(zoom, minZoom, 10.0);
  }
};


var renderer: *c.SDL_Renderer = undefined;
var window: *c.SDL_Window = undefined;
var font: ?*c.TTF_Font = undefined;

fn renderText(text: [:0]const u8, left: f32, top: f32, max_width: f32, centered: bool, color: c.SDL_Color) void {
  const ttfcolor = c.SDL_Color{.r = 255, .g = 255, .b = 255, .a = 255};
  const textSurface = c.TTF_RenderUTF8_Blended(font, text, ttfcolor);
  defer c.SDL_FreeSurface(textSurface);
  const textTexture = c.SDL_CreateTextureFromSurface(renderer, textSurface);
  defer c.SDL_DestroyTexture(textTexture);
  const tsrcr = c.SDL_Rect{.x = 0, .y = 0,
    .w = textSurface.*.w,
    .h = textSurface.*.h,
  };
  var tdesr = c.SDL_FRect{
    .x = left * scale,
    .y = top * scale,
    .w = @intToFloat(f32, tsrcr.w),
    .h = @intToFloat(f32, tsrcr.h),
  };

  if (tdesr.w > (max_width * scale)) {
    const f = (max_width * scale) / tdesr.w;
    tdesr.w *= f;
    tdesr.h *= f;
  }

  if (centered) {
    tdesr.x -= tdesr.w / 2;
    tdesr.y -= tdesr.h / 2;
  }

  _ = c.SDL_SetTextureAlphaMod(textTexture, color.a);
  _ = c.SDL_SetTextureColorMod(textTexture, color.r, color.g, color.b);
  _ = c.SDL_RenderCopyF(renderer, textTexture, &tsrcr, &tdesr);
}

fn drawSectorLines(camera: Camera, sinfo: com.SpaceInfo) void {
  _ = c.SDL_SetRenderDrawColor(renderer, 0, 0, 155, 255);

  // width of each sector
  const sw: f32 = 2000.0;
  // x coord in space coords that's the edge of the screen
  const xspan = screen_width / camera.zoom;
  const minx = std.math.max(-sinfo.half_width, camera.center.x - xspan / 2.0);
  const maxx = std.math.min(sinfo.half_width, camera.center.x + xspan / 2.0);

  const yspan = screen_height / camera.zoom;
  const miny = std.math.max(-sinfo.half_height, camera.center.y - yspan / 2.0);
  const maxy = std.math.min(sinfo.half_height, camera.center.y + yspan / 2.0);

  const minscreen = space2Screen(camera, u.Point{.x = minx, .y = miny});
  const maxscreen = space2Screen(camera, u.Point{.x = maxx, .y = maxy});

  var x = @ceil(minx / sw) * sw;
  while (x <= maxx) : (x += sw) {
    const xscreen = space2Screen(camera, u.Point{.x = x, .y = 0});
    _ = c.SDL_RenderDrawLineF(renderer,
      xscreen.x,
      std.math.max(0, minscreen.y),
      xscreen.x,
      std.math.min(screen_height, maxscreen.y),
    );
  }

  var y = @ceil(miny / sw) * sw;
  while (y <= maxy) : (y += sw) {
    const yscreen = space2Screen(camera, u.Point{.x = 0, .y = y});
    _ = c.SDL_RenderDrawLineF(renderer,
      std.math.max(0, minscreen.x),
      yscreen.y,
      std.math.min(screen_width, maxscreen.x),
      yscreen.y,
    );
  }
}

const Button = struct {
  // used to uniquely identify this button
  id: u64,
  label: [:0]const u8,
  shortcut: i32 = 0,
  x: f32,
  y: f32,
  w: f32,
  h: f32,
};



fn drawButton(b: Button, disabled: bool) !void {
  const pressed = buttons_pressed.contains(b.id) or disabled;
  var outline_color: c.SDL_Color = undefined;
  var text_color: c.SDL_Color = undefined;
  var fill_color: c.SDL_Color = undefined;
  if (pressed) {
    outline_color = c.SDL_Color{.r = 150, .g = 150, .b = 150, .a = 255};
    text_color = outline_color;
    fill_color = c.SDL_Color{.r = 0, .g = 0, .b = 0, .a = 255};
  }
  else {
    outline_color = c.SDL_Color{.r = 220, .g = 220, .b = 220, .a = 255};
    text_color = outline_color;
    fill_color = c.SDL_Color{.r = 120, .g = 120, .b = 120, .a = 255};
  }

  _ = c.SDL_SetRenderDrawColor(renderer, fill_color.r, fill_color.g, fill_color.b, fill_color.a);
  var rect = c.SDL_FRect{
    .x = b.x * scale,
    .y = b.y * scale,
    .w = b.w * scale,
    .h = b.h * scale,
  };
  _ = c.SDL_RenderFillRectF(renderer, &rect);

  _ = c.SDL_SetRenderDrawColor(renderer, outline_color.r, outline_color.g, outline_color.b, outline_color.a);
  const thick = 2;

  rect = c.SDL_FRect{
    .x = b.x * scale,
    .y = b.y * scale,
    .w = b.w * scale,
    .h = thick * scale,
  };
  _ = c.SDL_RenderFillRectF(renderer, &rect);
  rect.y = (b.y + b.h - thick) * scale;
  _ = c.SDL_RenderFillRectF(renderer, &rect);

  rect = c.SDL_FRect{
    .x = b.x * scale,
    .y = b.y * scale,
    .w = thick * scale,
    .h = b.h * scale,
  };
  _ = c.SDL_RenderFillRectF(renderer, &rect);
  rect.x = (b.x + b.w - thick) * scale;
  _ = c.SDL_RenderFillRectF(renderer, &rect);

  const max_width = 0.8 * b.w;
  renderText(b.label, b.x + (b.w / 2), b.y + (b.h / 2), max_width, true, text_color);

  try buttons_shown.put(b.id, true);

  if (!mouse_on_button and
      mouse_pos.x >= (b.x - thick) * scale and
      mouse_pos.x <= (b.x + b.w + thick) * scale and
      mouse_pos.y >= (b.y - thick) * scale and
      mouse_pos.y <= (b.y + b.h + thick) * scale) {
    mouse_on_button = true;
  }
}

const DoButtonResult = enum {
  click,
  repeat,
  unclick,
};

fn swapRemove(events: *[]Event, k: u32) void {
  var i = k;
  while (i+1 < events.len) : (i += 1) {
    events.*[i] = events.*[i+1];
  }
  events.len -= 1;
}

fn doButton(b: Button, events: *[]Event, i: *u32) ?DoButtonResult {
  while (i.* < events.len) : (i.* += 1) {
    const e = events.*[i.*];
    const pressed = buttons_pressed.contains(b.id);
    if (b.shortcut >= 0 and e == Event.key_event and e.key_event.keysym == b.shortcut) {
      if (!pressed and e.key_event.state == .down) {
        buttons_pressed.put(b.id, true) catch unreachable;
        swapRemove(events, i.*);
        return DoButtonResult.click;
      }
      else if (pressed and e.key_event.state == .repeat) {
        swapRemove(events, i.*);
        return DoButtonResult.repeat;
      }
      else if (pressed and e.key_event.state == .up) {
        _ = buttons_pressed.remove(b.id);
        swapRemove(events, i.*);
        return DoButtonResult.unclick;
      }
    }
    else if (e == Event.mouse_event) {
      const mx = e.mouse_event.x / scale;
      const my = e.mouse_event.y / scale;
      if (mx >= b.x and mx <= (b.x + b.w)
          and my >= b.y and my <= (b.y + b.h)) {
        if (!pressed and e.mouse_event.state == .leftdown) {
          buttons_pressed.put(b.id, true) catch unreachable;
          swapRemove(events, i.*);
          return DoButtonResult.click;
        }
        else if (pressed and e.mouse_event.state == .leftup) {
          _ = buttons_pressed.remove(b.id);
          swapRemove(events, i.*);
          return DoButtonResult.unclick;
        }
      }
    }
  }

  return null;
}

const KeyEvent = struct {
  const Kind = enum {
    down,
    repeat,
    up,
  };
  keysym: i32,
  state: Kind,
};

const MouseEvent = struct {
  const Kind = enum {
    leftdown,
    leftup,
    rightdown,
    rightup,
    motion,
  };
  x: f32,
  y: f32,
  state: Kind,
};

const Event = union(enum) {
  key_event: KeyEvent,
  mouse_event: MouseEvent,
};

var keys_held: std.AutoHashMap(i32, bool) = undefined;

// Keep track of which buttons (based on name) are pressed.
// If a button is pressed but not shown, remove it because
// something changed.
const ButtonSet = std.AutoHashMap(u64, bool);
var buttons_pressed: ButtonSet = undefined;
var buttons_shown: ButtonSet = undefined;

pub fn setup() !void {
  if (c.SDL_Init(c.SDL_INIT_EVERYTHING) < 0) {
    std.debug.print("Couldn't initialize SDL: {s}\n", .{c.SDL_GetError()});
    return;
  }

  if (c.TTF_Init() < 0) {
    std.debug.print("Couldn't initialize SDL_ttf: {s}\n", .{c.SDL_GetError()});
    return;
  }

  window = c.SDL_CreateWindow("Warpz", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, @floatToInt(i32, screen_width), @floatToInt(i32, screen_height),
    c.SDL_WINDOW_ALLOW_HIGHDPI |
    c.SDL_WINDOW_RESIZABLE)
  orelse {
    std.debug.print("Failed to open {d} x {d} window: {s}\n", .{screen_width, screen_height, c.SDL_GetError()});
    return;
  };

  //var ddpi: f32 = undefined;
  //var hdpi: f32 = undefined;
  //var vdpi: f32 = undefined;
  //_ = c.SDL_GetDisplayDPI(0, &ddpi, &hdpi, &vdpi);
  //std.debug.print("ddpi {d} hdpi {d} vdpi {d}\n", .{ddpi, hdpi, vdpi});

  _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "linear");

  renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC)
    orelse {
    std.debug.print("Failed to create renderer: {s}\n", .{c.SDL_GetError()});
    return;
  };

  var pixel_w: i32 = undefined;
  var pixel_h: i32 = undefined;
  _ = c.SDL_GetRendererOutputSize(renderer, &pixel_w, &pixel_h);
  screen_width = @intToFloat(f32, pixel_w);
  screen_height = @intToFloat(f32, pixel_h);

  var window_w: i32 = undefined;
  var window_h: i32 = undefined;
  _ = c.SDL_GetWindowSize(window, &window_w, &window_h);
  scale = screen_width / @intToFloat(f32, window_w); 
  std.debug.print("window size {d} x {d} renderer size {d} x {d} scale {d}\n", .{window_w, window_h, pixel_w, pixel_h, scale});

  font = c.TTF_OpenFont("ttf-bitstream-vera-1.10/VeraMono.ttf", @floatToInt(c_int, u.FONT_SIZE * scale));

  //_ = c.SDL_RenderSetLogicalSize(renderer, @floatToInt(i32, screen_width), @floatToInt(i32, screen_height));

  _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND);

  try com.loadShips(renderer, gpa);
}

fn setSockFlags(sock: std.os.socket_t, flags: u32) !void {
    if ((flags & std.os.SOCK.NONBLOCK) != 0) {
        if (builtin.os.tag == .windows) {
            var mode: c_ulong = 1;
            if (std.os.windows.ws2_32.ioctlsocket(sock, std.os.windows.ws2_32.FIONBIO, &mode) == std.os.windows.ws2_32.SOCKET_ERROR) {
                switch (std.os.windows.ws2_32.WSAGetLastError()) {
                    .WSANOTINITIALISED => unreachable,
                    .WSAENETDOWN => return error.NetworkSubsystemFailed,
                    .WSAENOTSOCK => return error.FileDescriptorNotASocket,
                    // TODO: handle more errors
                    else => |err| return std.os.windows.unexpectedWSAError(err),
                }
            }
        } else {
            var fl_flags = std.os.fcntl(sock, std.os.F.GETFL, 0) catch |err| switch (err) {
                error.FileBusy => unreachable,
                error.Locked => unreachable,
                error.PermissionDenied => unreachable,
                else => |e| return e,
            };
            fl_flags |= std.os.SOCK.NONBLOCK;
            _ = std.os.fcntl(sock, std.os.F.SETFL, fl_flags) catch |err| switch (err) {
                error.FileBusy => unreachable,
                error.Locked => unreachable,
                error.PermissionDenied => unreachable,
                else => |e| return e,
            };
        }
    }
}

fn sendCommand(message: com.Message) !void {
  if (mmbox) |*mbox| {
    //std.debug.print("client sending {}\n", .{message});
    try mbox.out.startMessage();
    try com.serializeMessage(message, mbox.out.writer());
    try mbox.out.endMessage();
    pumpOut(mbox);
  }
}

fn pumpOut(mbox: *Mailbox) void {
  mbox.pumpOut() catch {
    std.debug.print("server pumpOut error\n", .{});
    gpa.free(mbox.in.buf);
    gpa.free(mbox.out.buf);
    mmbox = null;
  };
}

fn pumpIn(mbox: *Mailbox) void {
  mbox.pumpIn() catch {
    std.debug.print("server pumpIn error\n", .{});
    gpa.free(mbox.in.buf);
    gpa.free(mbox.out.buf);
    mmbox = null;
  };
}

const FowArea = struct {
  p: u.Point,
  visibility: f32,
  radar: f32,
};

fn fowAlpha(fowlist: std.ArrayList(FowArea), o: com.Object) f32 {
  var a: f32 = 0.0;
  for (fowlist.items) |*f| {
    const d = u.distance2(f.p, o.pv.p);
    var vd = f.visibility + o.radius;
    vd *= vd;
    const va = u.linearFade(f32, d, 0.9 * vd, vd);
    a = std.math.max(a, va);

    var rd = f.radar + o.radius;
    rd *= rd;
    var ra = u.linearFade(f32, d, 0.9 * rd, rd);
    ra *= o.in_nebula;  // radar can't see things in nebulas
    a = std.math.max(a, ra);

    if (a == 1.0) {
      break;
    }
  }

  return a;
}

var mmbox: ?Mailbox = null;
var eventsArray: [100]Event = undefined;
var frame_times = [_]i64{0} ** 30;
var update_times = [_]i64{0} ** 30;
var ahead_times = [_]i64{0} ** 30;
var mouse_shown = true;
var mouse_on_button = false;
var mouse_pos = u.Point{.x = 0, .y = 0};

pub fn run() !void {
  keys_held = std.AutoHashMap(i32, bool).init(gpa);
  buttons_pressed = ButtonSet.init(gpa);

  var saved_space: ?com.Space = null;
  var space = com.Space.init(gpa);
  space.info.id = 0;
  space.info.time = 0;
  space.info.half_width = 400.0;
  space.info.half_height = 200.0;

  var start_loop_millis: i64 = 0;
  var heartbeat_millis: i64 = 0;
  var last_update_time: i64 = 0;
  // time we would like to show
  var target_time: i64 = 0;

  var camera: Camera = .{
    .player_id = 0,
    .mode = .player_follow,
    .center = .{.x = 0, .y = 0},
    .center_true = .{.x = 0, .y = 0},
    .zoom = scale,
    .zoom_sector_saved = scale,
    .sector_view_point = .{.x = 0, .y = 0},
    .in_hangar = false,
  };

  var mouseIsDrag: bool = false;


  game_loop: while (true) {

    if (start_loop_millis == 0) {
      start_loop_millis = std.time.milliTimestamp();
      heartbeat_millis = start_loop_millis;
    }

    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    buttons_shown = ButtonSet.init(arena);
    mouse_on_button = false;

    if (mmbox == null and start_loop_millis > heartbeat_millis + 1000) {
      heartbeat_millis = start_loop_millis;
      std.debug.print("client connecting...", .{});
      const stream = std.net.tcpConnectToHost(arena, "127.0.0.1", u.PORT) catch |err| switch (err) {
        else => null,
      };

      if (stream) |s| {
        std.debug.print("connected to {}\n", .{s});
        try setSockFlags(s.handle, std.os.SOCK.NONBLOCK);
        mmbox = Mailbox{
          .stream = s,
          .out = com.RingBuffer{.buf = try gpa.alloc(u8, u.RB_SIZE)},
          .in = com.RingBuffer{.buf = try gpa.alloc(u8, u.RB_SIZE)},
        };

        var nc = com.NewClient.init();
        nc.name = u.str("Client Player");

        try mmbox.?.out.startMessage();
        try com.serializeMessage(com.Message{.new_client = nc}, mmbox.?.out.writer());
        try mmbox.?.out.endMessage();
        pumpOut(&mmbox.?);
      }
      else {
        std.debug.print("connect failed\n", .{});
      }
    }

    // process messages from server
    if (mmbox) |*mbox| {
      pumpIn(mbox);
    }

    if (mmbox) |*mbox| {
      var size = mbox.in.haveMessage();
      while (size > 0) {
        _ = try mbox.in.reader().readIntBig(u32);
        var num_bytes: u32 = 4;
        while (num_bytes < size) {
          var message = try com.deserializeMessage(mbox.in.reader(), &num_bytes);
          //std.debug.print("client read {d} {d}: {}\n", .{size, num_bytes, message});
          switch (message) {
            .new_client => |nc| {
              camera.player_id = nc.id;
              std.debug.print("client got player id {d}\n", .{camera.player_id});
            },
            .space_info => |si| {
              // newspace 
              space.deinit();
              if (saved_space) |*ss| {
                ss.deinit();
                saved_space = null;
              }

              space = com.Space.init(gpa);
              space.info = si;
              last_update_time = si.time;
              target_time = si.time;

              // reset camera
              camera.center_true = .{.x = 0, .y = 0};
              camera.mode = .player_follow;
              camera.zoom = space.info.minZoom(screen_width, screen_height);
              camera.zoom_sector_saved = scale;
              camera.in_hangar = false;
            },
            .update => |up| blk: {
              if (space.info.id != up.id) {
                std.debug.print("client dropping update {d}-{d} (space id {d})\n", .{up.id, up.time, space.info.id});
                num_bytes += try mbox.in.skip(size - num_bytes);
              }
              else if (up.time != (last_update_time + u.TICK)) {
                std.debug.print("client dropping update {d}-{d} (expected time {d})\n", .{up.id, up.time, last_update_time + u.TICK});
                num_bytes += try mbox.in.skip(size - num_bytes);
              }
              else {
                // normal update
                last_update_time = up.time;

                for (update_times) |_, i| {
                  if (i == (update_times.len - 1)) {
                    update_times[i] = std.time.milliTimestamp();
                  } else {
                    update_times[i] = update_times[i+1];
                  }

                  //std.debug.print("update_times[{d}] = {d}\n", .{i, update_times[i]});
                }

                if (up.time > target_time) {
                  // update came sooner than expected
                  std.debug.print("client jumping forward to {d} target {d}\n", .{up.time, target_time});
                  target_time = up.time;

                  // if the client hangs for a bit then we'll get here, but then
                  // at the end of the loop the loop_millis will be large (due to
                  // client hanging, so they'll be added to target_time and that
                  // will push it way too far out, so reset our loop_millis here
                  start_loop_millis = std.time.milliTimestamp();
                }

                // restore from saved space if we previously predicted more than 1 tick
                if (saved_space) |*ss| {
                  if (ss.info.time != up.time) {
                    std.debug.print("client dropping update {d} (saved space at time {d})\n", .{up.time, ss.info.time});
                    num_bytes += try mbox.in.skip(size - num_bytes);
                    break :blk;
                  }

                  std.debug.print("client restoring from save {d} target {d}\n", .{ss.info.time, target_time});

                  space.deinit();
                  space = com.Space.init(gpa);
                  try space.copyFrom(ss);
                  ss.deinit();
                  saved_space = null;
                }

                // we could have ticked forward last loop, so this doesn't always happen
                if (space.info.time < up.time) {
                  //std.debug.print("t", .{});
                  //std.debug.print("client ticking forward for input from {d} to {d} target {d}\n", .{space.info.time, up.time, target_time});
                  var collider = com.Collider.init(arena, &space);
                  _ = try space.tick(null, &collider);
                }
              }
            },
            .move => |mm| {
              if (mm.id == camera.player_id) {
                // we are moving to a new ship
                camera.in_hangar = false;

                // camera should switch back to player_follow
                // if we are moving from nothing or from a spacesuit
                if (space.findPlayer(camera.player_id)) |me| {
                  if (me.on_ship_id == 0 or space.findShip(me.on_ship_id) == null) {
                    camera.mode = .player_follow;
                  }
                  else if (space.findShip(me.on_ship_id)) |s| {
                    if (s.kind == .spacesuit) {
                      camera.mode = .player_follow;
                    }
                  }
                }
              }
              space.applyChange(message, null, null);
            },
            else => {
              space.applyChange(message, null, null);
            },
          }
        }
        size = mbox.in.haveMessage();
      }
    }

    if (start_loop_millis > heartbeat_millis + 1000) {
      heartbeat_millis = start_loop_millis;
      try sendCommand(com.Message{.heartbeat = com.HeartBeat{}});
    }

    var events: []Event = eventsArray[0..];
    events.len = 0;
    var debug_dmgfx: bool = false;
    
    var event: c.SDL_Event = undefined;
    var numEvents: u32 = 0;
    while (events.len < eventsArray.len and c.SDL_PollEvent(&event) != 0) {
      numEvents += 1;
      switch (event.type) {
        c.SDL_WINDOWEVENT => {
          switch (event.window.event) {
            c.SDL_WINDOWEVENT_RESIZED => {
              std.debug.print("window resized {d},{d}\n", .{event.window.data1, event.window.data2});
              //screen_width = @intToFloat(f32, event.window.data1);
              //screen_height = @intToFloat(f32, event.window.data2);
              //_ = c.SDL_RenderSetLogicalSize(renderer, event.window.data1, event.window.data2);
              var pixel_w: i32 = undefined;
              var pixel_h: i32 = undefined;
              _ = c.SDL_GetRendererOutputSize(renderer, &pixel_w, &pixel_h);
              screen_width = @intToFloat(f32, pixel_w);
              screen_height = @intToFloat(f32, pixel_h);

              var window_w: i32 = event.window.data1;
              var window_h: i32 = event.window.data2;
              scale = screen_width / @intToFloat(f32, window_w); 
              std.debug.print("window size {d} x {d} renderer size {d} x {d} scale {d}\n", .{window_w, window_h, pixel_w, pixel_h, scale});

              if (fullscreen == 0) {
                // nothing
              }
              else if (fullscreen == 2) {
                fullscreen = 1;
                fullscreen_width = screen_width;
                fullscreen_height = screen_height;
                //std.debug.print("fullscreen on\n", .{});
              }
              else if (screen_width != fullscreen_width or screen_height != fullscreen_height) {
                fullscreen = 0;  // resized out of fullscreen
                //std.debug.print("fullscreen off by resize\n", .{});
              }
            },
            else => {},
          }
        },
        c.SDL_KEYDOWN, c.SDL_KEYUP => |updown| {
          if (updown == c.SDL_KEYDOWN and ((event.key.keysym.mod & c.KMOD_CTRL) > 0) and event.key.keysym.sym == c.SDLK_q) {
            break :game_loop;
          }
          else if (updown == c.SDL_KEYDOWN and ((event.key.keysym.mod & c.KMOD_CTRL) > 0) and event.key.keysym.sym == c.SDLK_f) {
            if (fullscreen == 0) {
              _ = c.SDL_SetWindowFullscreen(window, c.SDL_WINDOW_FULLSCREEN_DESKTOP);
              fullscreen = 2; // waiting to  get resize event
              //std.debug.print("fullscreen waiting for resize\n", .{});
            }
            else {
              _ = c.SDL_SetWindowFullscreen(window, 0);
              fullscreen = 0;
              //std.debug.print("fullscreen off\n", .{});
            }
          }
          else if (updown == c.SDL_KEYDOWN and ((event.key.keysym.mod & c.KMOD_CTRL) > 0) and event.key.keysym.sym == c.SDLK_p) {
            debug_players += 1;
            debug_players = @mod(debug_players, 3);
            std.debug.print("debug_players = {d}\n", .{debug_players});
          }
          else if (updown == c.SDL_KEYDOWN and ((event.key.keysym.mod & c.KMOD_CTRL) > 0) and event.key.keysym.sym == c.SDLK_v) {
            debug_view = !debug_view;
          }
          else if (updown == c.SDL_KEYDOWN and ((event.key.keysym.mod & c.KMOD_CTRL) > 0) and event.key.keysym.sym == c.SDLK_d) {
            debug_dmgfx = true;
          }
          else if (updown == c.SDL_KEYDOWN and event.key.keysym.sym == c.SDLK_TAB) {
            tab_view = !tab_view;
          }
          else {
            events.len += 1;
            events[events.len-1] = Event{
              .key_event = KeyEvent{
                .state = blk: {
                  const pressed = keys_held.contains(event.key.keysym.sym);
                  if (updown == c.SDL_KEYDOWN) {
                    if (pressed) {
                      break :blk .repeat;
                    }
                    else {
                      try keys_held.put(event.key.keysym.sym, true);
                      break :blk .down;
                    }
                  }
                  else {
                    _ = keys_held.remove(event.key.keysym.sym);
                    break :blk .up;
                  }
                },
                .keysym = event.key.keysym.sym
              }
            };
          }
        },
        c.SDL_MOUSEBUTTONDOWN, c.SDL_MOUSEBUTTONUP => |updown| {
          if (event.button.button == c.SDL_BUTTON_LEFT) {
            mouseIsDrag = false;  // any click will stop a drag
            events.len += 1;
            events[events.len-1] = Event{
              .mouse_event = MouseEvent{
                .x = @intToFloat(f32, event.button.x) * scale,
                .y = @intToFloat(f32, event.button.y) * scale,
                .state = if (updown == c.SDL_MOUSEBUTTONDOWN) .leftdown else .leftup,
              }
            };
          }
          else if (event.button.button == c.SDL_BUTTON_RIGHT) {
            if (updown == c.SDL_MOUSEBUTTONDOWN) {
              mouseIsDrag = true;
            }
            else {
              mouseIsDrag = false;
            }
          }
        },
        c.SDL_MOUSEMOTION => {
          if (mouseIsDrag) {
            camera.mode = .free_drag;
            camera.center_true.x -= @intToFloat(f32, event.motion.xrel) * scale / camera.zoom;
            camera.center_true.y += @intToFloat(f32, event.motion.yrel) * scale / camera.zoom;
          }

          mouse_pos.x = @intToFloat(f32, event.motion.x) * scale;
          mouse_pos.y = @intToFloat(f32, event.motion.y) * scale;
        },
        c.SDL_MOUSEWHEEL => {
          camera.zoom_sector_saved = 0.0;
          const zooms = @intToFloat(f32, event.wheel.y);
          var base: f32 = 1.05;
          const zs = @exp(@log(base) * zooms);
          if (camera.mode == .player_follow) {
            camera.setZoom(space.info, camera.zoom * zs);
          }
          else {
            camera.mode = .free_drag;

            // zoom around mouse pointer
            var x: c_int = undefined;
            var y: c_int = undefined;
            _ = c.SDL_GetMouseState(&x, &y);
            var mouseP = u.Point{.x = @intToFloat(f32, x) * scale, .y = @intToFloat(f32, y) * scale};
            // space coords under mouse before zoom
            var op = screen2Space(camera, mouseP);
            camera.setZoom(space.info, camera.zoom * zs);
            // space coords under mouse after zoom
            var np = screen2Space(camera, mouseP);
            // translate so that np will be under the mouse
            camera.center_true.x += (op.x - np.x);
            camera.center_true.y += (op.y - np.y);
          }
        },
        c.SDL_QUIT => {
          //std.debug.print("SDL_QUIT\n", .{});
          break :game_loop;
        },
        else => {
          //std.debug.print("other event\n", .{});
        }
      }
    }

    if (false and numEvents > 0) {
      std.debug.print("numEvents {d}\n", .{numEvents});
      for (events) |*e| {
        std.debug.print("  {}\n", .{e});
      }
    }

    if (target_time - u.TICK > space.info.time) {
      // we are too far ahead, maybe our lag increased
      // slowly reduce target_time
      target_time -= 1;
      std.debug.print("client target_time {d}\n", .{target_time});
    }

    while (target_time > space.info.time) {
      if (saved_space == null and last_update_time < space.info.time) {
        // we are about to tick a second time past last_update_time, so save
        std.debug.print("client saving {d} target {d}\n", .{space.info.time, target_time});
        saved_space = com.Space.init(gpa);
        try saved_space.?.copyFrom(&space);
      }

      // tick forward for prediction
      var collider = com.Collider.init(arena, &space);
      _ = try space.tick(null, &collider);
      //std.debug.print("p", .{});
      //std.debug.print("client predicted to {d} target {d}\n", .{space.info.time, target_time});
    }

    space.cull();
    //std.debug.print("players {d}, ships {d}, plasmas: {d}, explosions {d}, backEffects {d}, effects {d}\n", .{space.players.items.len, space.ships.items.len, space.plasmas.items.len, space.explosions.items.len, space.backEffects.items.len, space.effects.items.len});

    for (ahead_times) |_, i| {
      if (i == (ahead_times.len - 1)) {
        ahead_times[i] = space.info.time - last_update_time;
      } else {
        ahead_times[i] = ahead_times[i+1];
      }
    }

    // background starts gray
    _ = c.SDL_SetRenderDrawColor(renderer, 75, 75, 75, 255);
    _ = c.SDL_RenderClear(renderer);

    var meOp: ?*com.Player = null;
    var meShipOp: ?*com.Ship = null;
    var meRCShipOp: ?*com.Ship = null;
    var dmgfx = u.Point{.x = 0.0, .y = 0.0};
    if (space.findPlayer(camera.player_id)) |me| {
      meOp = me;
      if (space.findShip(me.on_ship_id)) |s| {
        meShipOp = s;
        meRCShipOp = s;
        // topShip is the one we use for screenshaking
        var topShip = space.findTopShip(s);
        // viewShip is the one the viewpoint follows
        var viewShip = topShip;

        if (space.findShip(me.rcid)) |rcs| {
          meRCShipOp = rcs;
          viewShip = rcs;
        }

        if (debug_dmgfx) {
          topShip.dmgfx += 10.0;
        }

        if (camera.mode == .player_follow) {
          const dist = u.distance(camera.center_true, viewShip.obj.pv.p);
          if (dist > 10.0) {
            const d = std.math.max(10.0, 0.2 * dist);
            const a = u.angle(camera.center_true, viewShip.obj.pv.p);
            camera.center_true.x += d * @cos(a);
            camera.center_true.y += d * @sin(a);
          }
          else {
            camera.center_true = viewShip.obj.pv.p;
          }

          camera.center = camera.center_true;

          if (camera.zoom_sector_saved != 0.0) {
            // zoom but move camera so that target stays at the same pixel location
            const screenPt = space2Screen(camera, viewShip.obj.pv.p);

            if (camera.zoom_sector_saved > camera.zoom) {
              camera.setZoom(space.info, std.math.min(camera.zoom_sector_saved, camera.zoom * 1.25));
            }
            else {
              camera.setZoom(space.info, std.math.max(camera.zoom_sector_saved, camera.zoom / 1.25));
            }

            // space coords under target pixel location after zoom
            var np = screen2Space(camera, screenPt);
            camera.center_true.x += (viewShip.obj.pv.p.x - np.x);
            camera.center_true.y += (viewShip.obj.pv.p.y - np.y);
            camera.center = camera.center_true;
          }
        }

        // screen shake is always based on the top ship you are on
        dmgfx.x = space.randomBetween(-topShip.dmgfx, topShip.dmgfx);
        dmgfx.y = space.randomBetween(-topShip.dmgfx, topShip.dmgfx);
      }
      else if (camera.mode == .player_follow) {
        // player is not on any ship
        camera.mode = .sector_view;
        camera.zoom_sector_saved = scale;
        camera.sector_view_point = .{.x = 0, .y = 0};
      }
    }

    if (camera.mode == .sector_view) {
      // zoom to see whole space 
      // keep saved point at the same pixel
      const screenP = space2Screen(camera, camera.sector_view_point);
      camera.setZoom(space.info, camera.zoom / 1.25);
      // space coords under target pixel location after zoom
      var np = screen2Space(camera, screenP);
      camera.center_true.x += (camera.sector_view_point.x - np.x);
      camera.center_true.y += (camera.sector_view_point.y - np.y);
      camera.center = camera.center_true;

      const sector_camera = Camera{
        .player_id = 0,
        .mode = .sector_view,
        .center = .{.x = 0, .y = 0},
        .center_true = .{.x = 0, .y = 0},
        .zoom = space.info.minZoom(screen_width, screen_height),
        .zoom_sector_saved = scale,
        .sector_view_point = .{.x = 0, .y = 0},
        .in_hangar = false,
      };

      // move saved point towards where it will end up
      const origin = u.Point{.x = 0, .y = 0};
      const camera_dist = u.distance(origin, camera.center_true);
      if (camera_dist > 10.0) {
        const final_screenPt = space2ScreenCanon(sector_camera, camera.sector_view_point);
        const screenPt = space2ScreenCanon(camera, camera.sector_view_point);
        const dist = u.distance(final_screenPt, screenPt);
        const d = std.math.min(dist, std.math.max(3.0, 0.2 * dist)) / camera.zoom;
        const a = u.angle(final_screenPt, screenPt);
        camera.center_true.x += d * @cos(a);
        camera.center_true.y += d * @sin(a);
      }
      else {
        camera.center_true = origin;
      }

      camera.center = camera.center_true;
    }

    // set camera and screen shaking
    camera.center = camera.center_true;
    camera.center.x += dmgfx.x / camera.zoom;
    camera.center.y += dmgfx.y / camera.zoom;

    var fowlist = std.ArrayList(FowArea).init(arena);

    if (meOp) |me| {
      space.setInNebula();

      // black out fow for radar
      for (space.ships.items) |*s| {
        if (s.fowFor(&me.faction)) {
          const radar = s.visibility + (s.obj.in_nebula * (s.radar - s.visibility));
          drawCircle(camera, s.obj.pv.p, radar, com.SpriteKind.@"circle-fade", c.SDL_Color{.r = 0, .g = 0, .b = 0, .a = 255});
          const f = FowArea{.p = s.obj.pv.p, .visibility = s.visibility, .radar = radar};
          fowlist.append(f) catch unreachable;
        }
      }

      // nebulas put fow over radar
      for (space.nebulas.items) |*n| {
        drawCircle(camera, n.obj.pv.p, n.obj.radius, com.SpriteKind.@"circle-fade", c.SDL_Color{.r = 75, .g = 75, .b = 75, .a = 255});
      }

      // black out fow for visibility
      for (fowlist.items) |*f| {
        drawCircle(camera, f.p, f.visibility, com.SpriteKind.@"circle-fade", c.SDL_Color{.r = 0, .g = 0, .b = 0, .a = 255});
      }
    }

    // draw nebula images
    for (space.nebulas.items) |*n| {
      drawNebula(n, &space, camera);
    }

    // draw asteroid field circles
    //for (space.ships.items) |*s| {
    //  if (s.sprite == com.SpriteKind.@"asteroid") {
    //    const screenPt = space2Screen(camera, s.obj.pv.p);
    //    const sprite = com.sprites[@enumToInt(com.SpriteKind.circle)];

    //    const size = std.math.min(200, 10.0 / camera.zoom);
    //    const w = size;
    //    const h = size;
    //    const desr = c.SDL_FRect{
    //      .x = screenPt.x - (w / 2.0),
    //      .y = screenPt.y - (h / 2.0),
    //      .w = w,
    //      .h = h,
    //    };

    //    const color = c.SDL_Color{.r = 200, .g = 0, .b = 0, .a = 5};

    //    _ = c.SDL_SetTextureAlphaMod(sprite.frames[0], color.a);
    //    _ = c.SDL_SetTextureColorMod(sprite.frames[0], color.r, color.g, color.b);
    //    _ = c.SDL_RenderCopyExF(renderer, sprite.frames[0], 0, &desr, 0, 0, c.SDL_FLIP_NONE);
    //  }
    //}

    // draw sector lines
    drawSectorLines(camera, space.info);

    // filter all annotations
    if (meOp) |me| {
      for (space.annotations.items) |*a| {
        if (std.mem.eql(u8, &a.faction, &u.str(""))
            or std.mem.eql(u8, &a.faction, &me.faction)) {
          if (a.kind == .text and a.status == .active and (space.info.time - a.obj.start_time) > @floatToInt(i64, a.obj.pv.r + a.obj.pv.dr)) {
            a.obj.alive = false;
          }
        }
        else {
          a.obj.alive = false;
        }
      }
    }

    for (space.annotations.items) |*a| {
      if (a.kind == .waypoint) {
        const p = space2Screen(camera, a.obj.pv.p);
        switch (a.status) {
          .done => {
            const color = c.SDL_Color{.r = 0, .g = 150, .b = 0, .a = 255};
            renderText(a.txt[0..a.txt.len-1:0], p.x / scale, p.y / scale, 100, true, color);
          },
          .active => {
            drawCircle(camera, a.obj.pv.p, a.obj.pv.r, com.SpriteKind.@"circle-outline", c.SDL_Color{.r = 0, .g = 0, .b = 220, .a = 255});
            const color = c.SDL_Color{.r = 255, .g = 255, .b = 0, .a = 255};
            renderText(a.txt[0..a.txt.len-1:0], p.x / scale, p.y / scale, 100, true, color);
          },
          .future => {
            const color = c.SDL_Color{.r = 0, .g = 0, .b = 220, .a = 255};
            renderText(a.txt[0..a.txt.len-1:0], p.x / scale, p.y / scale, 100, true, color);
          },
        }
      }
    }

    for (space.backEffects.items) |*e| {
      const fowa = fowAlpha(fowlist, e.obj);
      if (fowa == 0.0) {
        continue;
      }
      drawBackEffect(e, fowa, &space, camera);
    }

    for (space.ships.items) |*s| {
      if (!s.flying()) {
        continue;
      }

      const fowa = fowAlpha(fowlist, s.obj);
      if (fowa == 0.0) {
        continue;
      }
      const desr = drawShip(s, &space, fowa, camera);
      //const desr = drawShip(s, &space, 1.0, camera);

      var r = desr;
      const pad: f32 = r.w * 0.6;
      r.x -= pad;
      r.w += pad * 2;
      r.y -= pad;
      r.h += pad * 2;
      // make sure we end up with a square (missile bitmaps are not square)
      const minw = std.math.max(16 * scale, std.math.max(r.w, r.h));
      if (r.w < minw) {
        const diff = minw - r.w;
        r.x -= @divTrunc(diff, 2);
        r.w = minw;
      }
      if (r.h < minw) {
        const diff = minw - r.h;
        r.y -= @divTrunc(diff, 2);
        r.h = minw;
      }

      if (s.hp < s.maxhp and s.kind != .missile) {
        // health bar above ship
        const frac = std.math.max(0.0, s.hp / s.maxhp);
        const color = stoplightColor(s.hp, s.maxhp);
        const a = @floatToInt(u8, fowa * @intToFloat(f32, color.a));
        _ = c.SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, a);
        var barw = std.math.max(2.0 * scale, r.w * 0.8 * frac);
        _ = c.SDL_RenderFillRectF(renderer, &c.SDL_FRect{
          .x = r.x + (r.w / 2) - (barw / 2.0),
          .y = r.y - 4 * scale,
          .w = barw,
          .h = 2.0 * scale,
        });
      }
      
      if (s == meRCShipOp and s.kind == .missile) {
        // draw time left bar below ship
        const age = @intToFloat(f32, space.info.time - s.obj.start_time);
        const dur = @intToFloat(f32, s.duration);
        const frac = 1.0 - std.math.clamp(age / dur, 0.0, 1.0);
        const a = @floatToInt(u8, fowa * 255);
        const color = c.SDL_Color{.r = 255, .g = 0, .b = 0, .a = a};
        _ = c.SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
        var barw = std.math.max(2.0 * scale, r.w * 0.8 * frac);
        _ = c.SDL_RenderFillRectF(renderer, &c.SDL_FRect{
          .x = r.x + (r.w / 2) - (barw / 2.0),
          .y = r.y + r.h + 2 * scale,
          .w = barw,
          .h = 3.0 * scale,
        });
      }

      // draw corners around ship
      if (meOp) |me| blk: {
        if (s.kind == .spacesuit) {
          // no corners on spacesuits
          break :blk;
        }

        if (std.mem.eql(u8, &s.faction, &u.str(""))) {
          // no faction no corners
          break :blk;
        }

        const a = @floatToInt(u8, fowa * 255);
        var color = c.SDL_Color{.r = 180, .g = 0, .b = 0, .a = a};  // assume hostile
        if (s == meRCShipOp or (meRCShipOp == null and s.obj.id == me.on_ship_id)) {
          color = c.SDL_Color{.r = 0, .g = 180, .b = 0, .a = a};  // my ship
        }
        else if (std.mem.eql(u8, &s.faction, &me.faction)) {
          color = c.SDL_Color{.r = 0, .g = 0, .b = 200, .a = a};  // friendly
        }

        const sprite = com.sprites[@enumToInt(com.SpriteKind.corner)];
        _ = c.SDL_SetTextureAlphaMod(sprite.frames[0], color.a);
        _ = c.SDL_SetTextureColorMod(sprite.frames[0], color.r, color.g, color.b);

        var cr = r;
        cr.w = @intToFloat(f32, sprite.w) * scale;
        cr.h = @intToFloat(f32, sprite.h) * scale;
        _ = c.SDL_RenderCopyExF(renderer, sprite.frames[0], 0, &cr, 0, 0, c.SDL_FLIP_NONE);
        cr.x = r.x + r.w - cr.w;

        _ = c.SDL_RenderCopyExF(renderer, sprite.frames[0], 0, &cr, 0, 0, c.SDL_FLIP_HORIZONTAL);

        cr.y = r.y + r.h - cr.h;
        _ = c.SDL_RenderCopyExF(renderer, sprite.frames[0], 0, &cr, 0, 0, c.SDL_FLIP_HORIZONTAL | c.SDL_FLIP_VERTICAL);

        cr.x = r.x;
        _ = c.SDL_RenderCopyExF(renderer, sprite.frames[0], 0, &cr, 0, 0, c.SDL_FLIP_VERTICAL);
      }
    }

    for (space.plasmas.items) |*p| {
      const fowa = fowAlpha(fowlist, p.obj);
      if (fowa == 0.0) {
        continue;
      }
      drawPlasma(p, fowa, &space, camera);
    }

    for (space.explosions.items) |*e| {
      const fowa = fowAlpha(fowlist, e.obj);
      if (fowa == 0.0) {
        continue;
      }
      drawExplosion(e, fowa, camera);
    }

    for (space.effects.items) |*e| {
      const fowa = fowAlpha(fowlist, e.obj);
      if (fowa == 0.0) {
        continue;
      }
      drawEffect(e, fowa, &space, camera);
    }

    for (space.annotations.items) |*a| {
      if (a.kind == .button and (a.status == .active or tab_view)) {
        var p = u.Point{.x = 0, .y = 0};
        var wh = u.Point{.x = 0, .y = 0};
        switch (a.where) {
          .space => {
            p = space2Screen(camera, a.obj.pv.p);
            p.x /= scale;
            p.y /= scale;
            wh.x = camera.zoom * a.obj.pv.dx / scale;
            wh.y = camera.zoom * a.obj.pv.dy / scale;
          },
          .screen => {
            p.x = a.obj.pv.p.x;
            if (p.x < 0) p.x = (screen_width + (p.x * scale)) / scale;
            p.y = a.obj.pv.p.y;
            if (p.y < 0) p.y = (screen_height + (p.y * scale)) / scale;
            wh.x = a.obj.pv.dx;
            wh.y = a.obj.pv.dy;
          },
          .message_queue => unreachable,
        }
        const b = Button {.id = a.obj.id, .label = a.txt[0..a.txt.len-1:0],
          .x = p.x, .y = p.y, .w = wh.x, .h = wh.y,
        };
        try drawButton(b, false);
        var i: u32 = 0;
        while (doButton(b, &events, &i)) |result| {
          if (result == DoButtonResult.click) {
            try sendCommand(com.Message{.ann_cmd = com.AnnotationCommand{.id = a.obj.id}});
          }
        }
      }
      else if (a.kind == .orders or a.kind == .text) {
        var secs_left: u32 = 0;
        if (a.obj.start_time >= space.info.time) {
          secs_left = @intCast(u32, @divTrunc(a.obj.start_time - space.info.time, 1000));
        }
        var min_left: u32 = @divTrunc(secs_left, 60);
        secs_left -= min_left * 60;

        var buf: [:0]u8 = try arena.allocSentinel(u8, 100, 0);
        std.mem.set(u8, buf, 0);
        var iter = std.mem.split(u8, &a.txt, "\t");
        var append: usize = 0;
        if (iter.next()) |s| {
          std.mem.copy(u8, buf[append..], s);
          append += s.len;
        }
        if (iter.next()) |s| {
          const slice = try std.fmt.bufPrintZ(buf[append..], "{d:0>2}:{d:0>2}", .{min_left, secs_left});
          append += slice.len;
          std.mem.copy(u8, buf[append..], s);
        }

        if (a.kind == .orders) {
          renderText(buf, 116, 8, 1000, false, c.SDL_Color{.r = 255, .g = 255, .b = 255, .a = 255});
        }
        else {
          const x = screen_width / scale * a.obj.pv.p.x;
          const y = screen_height / scale * a.obj.pv.p.y;
          var alpha: u8 = 255;
          const age = space.info.time - a.obj.start_time;
          const solid: i64 = @floatToInt(i64, a.obj.pv.r);
          const fade: i64 = @floatToInt(i64, a.obj.pv.dr);
          if (a.status == .active and age > solid) {
            // fading
            alpha = 255 - @intCast(u8, @divTrunc(255 * std.math.min(fade, (age - solid)), fade));
          }
          renderText(buf, x, y + a.obj.pv.dy * u.LINE_HEIGHT, 1000, false, c.SDL_Color{.r = 255, .g = 255, .b = 255, .a = alpha});
        }
      }
    }

    {
      const b = Button {.id = u.hash("Zoom In"), .label = "Zoom In [r]", .shortcut = c.SDLK_r, .x = 0, .y = 0, .w = 0, .h = 0};
      var i: u32 = 0;
      try buttons_shown.put(b.id, true);
      while (doButton(b, &events, &i)) |result| {
        if (result == DoButtonResult.click or result == DoButtonResult.repeat) {
          camera.setZoom(space.info, camera.zoom * 1.2);
          camera.zoom_sector_saved = 0.0;
        }
      }
    }

    {
      const b = Button {.id = u.hash("Zoom Out"), .label = "Zoom Out [t]", .shortcut = c.SDLK_t, .x = 0, .y = 0, .w = 0, .h = 0};
      var i: u32 = 0;
      try buttons_shown.put(b.id, true);
      while (doButton(b, &events, &i)) |result| {
        if (result == DoButtonResult.click or result == DoButtonResult.repeat) {
          camera.setZoom(space.info, camera.zoom / 1.2);
          camera.zoom_sector_saved = 0.0;
        }
      }
    }

    {
      //const b = Button {.id = u.hash("Sector View"), .label = "Sector View [`]", .shortcut = c.SDLK_BACKQUOTE, .x = 8, .y = 100, .w = 150, .h = 40};
      const b = Button {.id = u.hash("Sector View"), .label = "Sector View [`]", .shortcut = c.SDLK_BACKQUOTE, .x = 0, .y = 0, .w = 0, .h = 0};
      //try drawButton(b, false);
      var i: u32 = 0;
      while (doButton(b, &events, &i)) |result| {
        if (result == DoButtonResult.click) {
          if (camera.mode != .sector_view) {
            camera.mode = .sector_view;
            camera.zoom_sector_saved = camera.zoom;
            camera.sector_view_point = camera.center_true;
          }
          else {
            camera.mode = .player_follow;
          }
        }
      }
    }

    if (meShipOp != null and camera.mode != .player_follow) {
      const b = Button {.id = u.hash("Auto Center"), .label = "Auto Center [esc]", .shortcut = c.SDLK_ESCAPE, .x = screen_width / 2 / scale - 90, .y = 32, .w = 180, .h = 40};
      try drawButton(b, false);
      var i: u32 = 0;
      while (doButton(b, &events, &i)) |result| {
        if (result == DoButtonResult.click) {
          camera.mode = .player_follow;
        }
      }
    }

    if (meShipOp) |mes| {
      // start with meShip ignoring remote control so we always show the health of the ship you are actually sitting on
      var meShip = mes;
      var color = stoplightColor(meShip.hp, meShip.maxhp);
      var w = meShip.hp * scale;
      _ = c.SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
      _ = c.SDL_RenderFillRectF(renderer, &c.SDL_FRect{
          .x = screen_width - w - 8 * scale,
          .y = 8 * scale,
          .w = w,
          .h = 20 * scale,
      });

      color = c.SDL_Color{.r = 255, .g = 255, .b = 255, .a = 255};
      w = meShip.maxhp * scale;
      _ = c.SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
      _ = c.SDL_RenderDrawRectF(renderer, &c.SDL_FRect{
          .x = screen_width - w - 8 * scale,
          .y = 8 * scale,
          .w = w,
          .h = 20 * scale,
      });

      meShip = meRCShipOp.?;
      // now meShip is either the remote controlled ship (if there is one) or the ship you are on
      const flying = meShip.flying();

      if (meShip.turn_power > 0) {
        {
          const b = Button {.id = u.hash("Left"), .label = "Left [a]", .shortcut = c.SDLK_a, .x = 8, .y = screen_height / scale - 48, .w = 100, .h = 40};
          try drawButton(b, !flying);
          if (flying) {
            var i: u32 = 0;
            while (doButton(b, &events, &i)) |result| {
              if (result == DoButtonResult.click) {
                try sendCommand(com.Message{.hold = com.Hold{.held = @enumToInt(com.Player.Held.left), .updown = .down}});
              }
              else if (result == DoButtonResult.unclick) {
                try sendCommand(com.Message{.hold = com.Hold{.held = @enumToInt(com.Player.Held.left), .updown = .up}});
              }
            }
          }
        }
        {
          const b = Button {.id = u.hash("Right"), .label = "Right [d]", .shortcut = c.SDLK_d, .x = 116, .y = screen_height / scale - 48, .w = 100, .h = 40};
          try drawButton(b, !flying);
          if (flying) {
            var i: u32 = 0;
            while (doButton(b, &events, &i)) |result| {
              if (result == DoButtonResult.click) {
                try sendCommand(com.Message{.hold = com.Hold{.held = @enumToInt(com.Player.Held.right), .updown = .down}});
              }
              else if (result == DoButtonResult.unclick) {
                try sendCommand(com.Message{.hold = com.Hold{.held = @enumToInt(com.Player.Held.right), .updown = .up}});
              }
            }
          }
        }
      }

      if (meShip.missile_hp > 0) {
        {
          const b = Button {.id = u.hash("MissileE"), .label = "Missile [e]", .shortcut = c.SDLK_e, .x = screen_width / scale - 108, .y = screen_height / scale - 124, .w = 100, .h = 40};
          try drawButton(b, !flying);
          if (flying) {
            var i: u32 = 0;
            while (doButton(b, &events, &i)) |result| {
              if (result == DoButtonResult.click) {
                try sendCommand(com.Message{.missile = com.Missile{.ship_id = meShip.obj.id, .a = u.angleNorm(meShip.obj.pv.r - u.PI / 2.0)}});
              }
            }
          }
        }
        {
          const b = Button {.id = u.hash("MissileQ"), .label = "Missile [q]", .shortcut = c.SDLK_q, .x = screen_width / scale - 216, .y = screen_height / scale - 124, .w = 100, .h = 40};
          try drawButton(b, !flying);
          if (flying) {
            var i: u32 = 0;
            while (doButton(b, &events, &i)) |result| {
              if (result == DoButtonResult.click) {
                try sendCommand(com.Message{.missile = com.Missile{.ship_id = meShip.obj.id, .a = u.angleNorm(meShip.obj.pv.r + u.PI / 2.0)}});
              }
            }
          }
        }
      }

      if (flying) {
        if (meShip.thrust > 0 and meShip.kind != .missile) {
          const b = Button {.id = u.hash("Go"), .label = "Go [w]", .shortcut = c.SDLK_w, .x = 62, .y = screen_height / scale - 96, .w = 100, .h = 40};
          try drawButton(b, false);
          var i: u32 = 0;
          while (doButton(b, &events, &i)) |result| {
            if (result == DoButtonResult.click) {
              try sendCommand(com.Message{.hold = com.Hold{.held = @enumToInt(com.Player.Held.go), .updown = .down}});
            }
            else if (result == DoButtonResult.unclick) {
              try sendCommand(com.Message{.hold = com.Hold{.held = @enumToInt(com.Player.Held.go), .updown = .up}});
            }
          }
        }

        if (meShip.kind == .missile) {
          const b = Button {.id = u.hash("Stop"), .label = "Stop [s]", .shortcut = c.SDLK_s, .x = (screen_width / 2 / scale) - 50, .y = screen_height / scale - 121, .w = 100, .h = 40};
          try drawButton(b, false);
          var i: u32 = 0;
          while (doButton(b, &events, &i)) |result| {
            if (result == DoButtonResult.click) {
              try sendCommand(com.Message{.remote_control = com.RemoteControl{.pid = 0, .rcid = 0}});
            }
          }

          //var viz = meShip.runAIPilot(&space, arena, null);
          //var vz = viz;
          //var maxf: f32 = -std.math.inf(f32);
          //var minf: f32 = std.math.inf(f32);
          //while (vz) |v| {
          //  maxf = std.math.max(maxf, v.f);
          //  minf = std.math.min(minf, v.f);
          //  vz = v.next;
          //}

          //if (maxf == minf) {
          //  minf -= 1.0;
          //}

          //while (viz) |v| {
          //  const f = (v.f - minf) / (maxf - minf);  // 0 to 1
          //  const r = @floatToInt(u8, f * 255);
          //  drawCircle(camera, v.p, 2.0, com.SpriteKind.circle, c.SDL_Color{.r = 100, .g = r, .b = 0, .a = 150});
          //  viz = v.next;
          //}
        }

        if (meShip.kind == .spacesuit) {
          const b = Button {.id = u.hash("Respawn"), .label = "Respawn", .x = screen_width / scale / 2 - 50, .y = screen_height / scale - 144, .w = 100, .h = 40};
          try drawButton(b, false);
          var i: u32 = 0;
          while (doButton(b, &events, &i)) |result| {
            if (result == DoButtonResult.click) {
              try sendCommand(com.Message{.ann_cmd = com.AnnotationCommand{.id = 0}});
            }
          }
        }
        else {
          const b = Button {.id = u.hash("Jump"), .label = "Jump", .x = 8, .y = 8, .w = 100, .h = 40};
          try drawButton(b, false);
          var i: u32 = 0;
          while (doButton(b, &events, &i)) |result| {
            if (result == DoButtonResult.click) {
              try sendCommand(com.Message{.move = com.Move{.ship_id = meShip.obj.id, .to = std.math.maxInt(u64) - 1}});
            }
          }
        }
      }
      else {
        const ts = space.findTopShip(meShip);
        const s = space.findShip(meShip.on_ship_id).?;
        const can_launch = (s.on_ship_id == 0);
        {
          const b = Button {.id = u.hash("Launch"), .label = "Launch [w]", .shortcut = c.SDLK_w, .x = 62, .y = screen_height / scale - 96, .w = 100, .h = 40};
          try drawButton(b, !can_launch);
          if (can_launch) {
            var i: u32 = 0;
            while (doButton(b, &events, &i)) |result| {
              if (result == DoButtonResult.click) {
                try sendCommand(com.Message{.launch = com.Launch{.pid = 0}});
              }
            }
          }
        }

        if (!camera.in_hangar) {
          var buf: [:0]u8 = try arena.allocSentinel(u8, 100, 0);
          const buf_slice: [:0]u8 = try std.fmt.bufPrintZ(buf, "Exit to {s}", .{u.sliceZ(&s.name)});
          var tw: c_int = undefined;
          var th: c_int = undefined;
          _ = c.TTF_SizeUTF8(font, buf_slice, &tw, &th);
          var twf: f32 = @intToFloat(f32, tw);
          twf /= scale;
          twf += 20;
          {
            const b = Button {.id = u.hash("Exit"), .label = buf_slice, .x = (screen_width / scale / 2) - twf / 2, .y = screen_height / scale - 80, .w = @intToFloat(f32, tw), .h = 40};
            try drawButton(b, false);
            var i: u32 = 0;
            while (doButton(b, &events, &i)) |result| {
              if (result == DoButtonResult.click) {
                try sendCommand(com.Message{.move = com.Move{.ship_id = meShip.obj.id, .to = meShip.on_ship_id}});
              }
            }
          }
        }

        // draw black circle on topship and then our ship on that to show containment
        drawCircle(camera, ts.obj.pv.p, ts.obj.radius * 1.2, com.SpriteKind.circle, c.SDL_Color{.r = 0, .g = 0, .b = 0, .a = 170});

        // can overwrite ship's posvel because it's not flying
        meShip.obj.pv = ts.obj.pv;
        meShip.obj.pv.r = u.PI / 2.0;  // orient ship image up

        const alpha: f32 = 1.0;
        _ = drawShip(meShip, &space, alpha, camera);
      }


      if (meShip.hangar) {
        if (camera.in_hangar) {
          // draw hangar contents with button for boarding each ship
          const size = 100 * scale;
          const buf = 4 * scale;
          const cols = 5;
          const rows = 4;
          const fill_color = c.SDL_Color{.r = 0, .g = 0, .b = 0, .a = 255};
          const outline_color = c.SDL_Color{.r = 220, .g = 220, .b = 220, .a = 255};
          const hw = size * cols;
          const hh = size * rows;
          const hangarRect = c.SDL_FRect{.x = (screen_width / 2) - (hw / 2),
            .y = (screen_height / 2) - (hh / 2), .w = hw + buf, .h = hh + buf};
          setSDLRenderColor(fill_color);
          _ = c.SDL_RenderFillRectF(renderer, &hangarRect);
          setSDLRenderColor(outline_color);
          _ = c.SDL_RenderDrawRectF(renderer, &hangarRect);

          const screenCamera = Camera{
            .player_id = 0,
            .mode = .sector_view,
            .center = .{.x = screen_width / scale / 2.0, .y = -screen_height / scale / 2.0},
            .center_true = .{.x = 0.0, .y = 0.0},
            .zoom = scale,
            .zoom_sector_saved = scale,
            .sector_view_point = .{.x = 0, .y = 0},
            .in_hangar = false,
          };

          var i: i32 = 0;
          for (space.ships.items) |*s| {
            if (s.on_ship_id == meShip.obj.id) {
              const rect = c.SDL_FRect{
                .x = hangarRect.x + size * @intToFloat(f32, @mod(i, cols)) + buf,
                .y = hangarRect.y + size * @intToFloat(f32, @divTrunc(i, cols)) + buf,
                .w = size - buf,
                .h = size - buf,
              };
              _ = c.SDL_RenderDrawRectF(renderer, &rect);

              // can overwrite s's posvel because it's not flying
              s.obj.pv.p.x = rect.x + rect.w / 2.0;
              s.obj.pv.p.x /= scale;
              s.obj.pv.p.y = -rect.y - rect.h / 2.0;
              s.obj.pv.p.y /= scale;
              s.obj.pv.r = u.PI / 2.0;  // orient ship image up
              _ = drawShip(s, &space, 1.0, screenCamera);

              var strbuf: []u8 = try arena.alloc(u8, 100);
              std.mem.set(u8, strbuf, 0);
              const buf_slice: [:0]u8 = try std.fmt.bufPrintZ(strbuf, "ship {d}", .{s.obj.id});
              const b = Button {.id = u.hash(buf_slice), .label = buf_slice, .x = rect.x / scale, .y = rect.y / scale, .w = rect.w / scale, .h = rect.h / scale};
              var k: u32 = 0;
              while (doButton(b, &events, &k)) |result| {
                if (result == DoButtonResult.click) {
                  try sendCommand(com.Message{.move = com.Move{.ship_id = meShip.obj.id, .to = s.obj.id}});
                }
              }

              i += 1;
            }
          }

          {
            const b = Button {.id = u.hash("Exit Hangar"), .label = "Exit Hangar [h]", .shortcut = c.SDLK_h, .x = screen_width / scale - 256, .y = screen_height - 48, .w = 140, .h = 40};
            try drawButton(b, false);
            var k: u32 = 0;
            while (doButton(b, &events, &k)) |result| {
              if (result == DoButtonResult.click) {
                camera.in_hangar = false;
              }
            }
          }
        }
        else {
          const b = Button {.id = u.hash("Enter Hangar"), .label = "Hangar [h]", .shortcut = c.SDLK_h, .x = screen_width / scale - 256, .y = screen_height / scale - 48, .w = 140, .h = 40};
          try drawButton(b, false);
          var i: u32 = 0;
          while (doButton(b, &events, &i)) |result| {
            if (result == DoButtonResult.click) {
              camera.in_hangar = true;
            }
          }
        }
      }

      if (meShip.pbolt_power > 0) {
        const b = Button {.id = u.hash("Plasma"), .label = "Plasma", .shortcut = c.SDLK_SPACE, .x =  screen_width / scale - 108, .y = screen_height / scale - 48, .w = 100, .h = 40};
        try drawButton(b, true);
        const frac = com.Plasma.frac(space.info.time, meOp.?.plasma_last_time);
        const fw = frac * 80.0;
        const rect = c.SDL_FRect{
          .x = screen_width + (-108 + 10 + (80 - fw) / 2) * scale,
          .y = screen_height + (-48 + 5) * scale,
          .w = fw * scale,
          .h = 2 * scale,
        };
        setSDLRenderColor(c.SDL_Color{.r = 255, .g = 0, .b = 0, .a = 255});
        _ = c.SDL_RenderFillRectF(renderer, &rect);

        if (flying) {
          var i: u32 = 0;
          while (doButton(b, &events, &i)) |result| {
            if (result == DoButtonResult.click) {
              meOp.?.plasma_last_time = space.info.time;
              try sendCommand(com.Message{.pbolt = com.PBolt{.ship_id = meShip.obj.id, .ship_a = meShip.obj.pv.r, .a = meShip.obj.pv.r}});
            }
          }
          i = 0;
          while (i < events.len) : (i += 1) {
            const e = &events[i];
            if (e.* == Event.mouse_event and e.mouse_event.state == .leftdown) {
              meOp.?.plasma_last_time = space.info.time;
              const mp = u.Point{.x = e.mouse_event.x, .y = -e.mouse_event.y};
              var sp = space2Screen(camera, meShip.obj.pv.p);
              sp.y *= -1;
              const t = u.angle(sp, mp);
              try sendCommand(com.Message{.pbolt = com.PBolt{.ship_id = meShip.obj.id, .ship_a = t, .a = t}});
              swapRemove(&events, i);
            }
          }
        }
      }
    }

    if (debug_view) {
      // each pixel is 1ms
      const xoff = 20;
      const now = std.time.milliTimestamp();
      {
        _ = c.SDL_SetRenderDrawColor(renderer, 155, 155, 155, 255);
        var rect = c.SDL_Rect{
          .x = xoff - 1,
          .y = 100,
          .w = 1,
          .h = 100,
        };
        _ = c.SDL_RenderFillRect(renderer, &rect);
      }
      {
        var i: i32 = 0;
        for (frame_times) |ft| {
          var rect = c.SDL_Rect{
            .x = xoff + @truncate(c_int, now - ft),
            .y = 150,
            .w = 1,
            .h = 10,
          };
          _ = c.SDL_RenderFillRect(renderer, &rect);
          i += 1;
        }
      }

      _ = c.SDL_SetRenderDrawColor(renderer, 255, 0, 255, 255);
      {
        var i: i32 = 0;
        var last_ut: i64 = 0;
        for (update_times) |ut, k| {
          //std.debug.print("update_times[{d}] = {d}\n", .{k, update_times[k]});
          var rect = c.SDL_Rect{
            .x = xoff + @truncate(c_int, now - ut + (if (last_ut == ut) @intCast(i64, k) else 0)),
            .y = 155,
            .w = 1,
            .h = 10,
          };
          _ = c.SDL_RenderFillRect(renderer, &rect);
          i += 1;
          last_ut = ut;
        }
      }
    }

    if (mmbox != null and ahead_times[0] > 0) {
      var max_ahead: i64 = 0;
      for (ahead_times) |at| {
        max_ahead = std.math.max(max_ahead, at);
      }
      if (max_ahead > 100) {
        var buf: [100]u8 = undefined;
        var buf_slice: [:0]u8 = try std.fmt.bufPrintZ(&buf, "ahead {d}", .{max_ahead});
        renderText(buf_slice, screen_width / scale - 158, 32, 1000, false, c.SDL_Color{.r = 255, .g = 255, .b = 255, .a = 255});
      }
    }

    if (frame_times[0] > 0) {
      const diff = frame_times[frame_times.len - 1] - frame_times[0];
      const avg = @intToFloat(f32, diff) / @intToFloat(f32, frame_times.len - 1);
      const fps = 1000.0 / avg;
      const fps_int = @floatToInt(i32, fps);
      //std.debug.print("n {d} diff {d} avg {d} fps {d}\n", .{frame_times.len, diff, avg, fps});
      var buf: [100]u8 = undefined;
      var buf_slice: [:0]u8 = try std.fmt.bufPrintZ(&buf, "fps {d}", .{fps_int});
      renderText(buf_slice, screen_width / scale - 56, 32, 1000, false, c.SDL_Color{.r = 255, .g = 255, .b = 255, .a = 255});
    }

    for (frame_times) |_, i| {
      if (i == (frame_times.len - 1)) {
        frame_times[i] = std.time.milliTimestamp();
      } else {
        frame_times[i] = frame_times[i+1];
      }
      //std.debug.print("frame_times[{d}] = {d}\n", .{i, frame_times[i]});
    }

    if (mouse_shown and !mouse_on_button) {
      mouse_shown = false;
      _ = c.SDL_ShowCursor(c.SDL_DISABLE);
    }
    else if (!mouse_shown and mouse_on_button) {
      mouse_shown = true;
      _ = c.SDL_ShowCursor(c.SDL_ENABLE);
    }

    if (!mouse_shown) {
      // draw crosshairs
      _ = c.SDL_SetRenderDrawColor(renderer, 255, 255, 0, 255);
      const off = 5 * scale;
      const len = 5 * scale;
      _ = c.SDL_RenderDrawLineF(renderer, mouse_pos.x + off, mouse_pos.y, mouse_pos.x + off + len, mouse_pos.y);
      _ = c.SDL_RenderDrawLineF(renderer, mouse_pos.x - off, mouse_pos.y, mouse_pos.x - off - len, mouse_pos.y);
      _ = c.SDL_RenderDrawLineF(renderer, mouse_pos.x, mouse_pos.y + off, mouse_pos.x, mouse_pos.y + off + len);
      _ = c.SDL_RenderDrawLineF(renderer, mouse_pos.x, mouse_pos.y - off, mouse_pos.x, mouse_pos.y - off - len);
    }

    //drawCircle(camera, u.Point{.x = 1500, .y = 0}, 1500, com.SpriteKind.@"circle-outline", c.SDL_Color{.r = 200, .g = 0, .b = 0, .a = 200});
    //drawCircle(camera, u.Point{.x = -1000, .y = -500}, 400, com.SpriteKind.@"circle-outline", c.SDL_Color{.r = 200, .g = 0, .b = 0, .a = 200});

    if (mmbox == null) {
      // show intro screen
    }

    c.SDL_RenderPresent(renderer);

    button_loop: while (true) {
      var it = buttons_pressed.iterator();
      while (it.next()) |entry| {
        if (!buttons_shown.contains(entry.key_ptr.*)) {
          _ = buttons_pressed.remove(entry.key_ptr.*);
          continue :button_loop;
        }
      }

      break;
    }

    if (mmbox) |*mbox| {
      pumpOut(mbox);
    }

    const millis = std.time.milliTimestamp();
    const loop_millis = millis - start_loop_millis;
    const extra_millis = u.TICK - loop_millis;
    const sleep_millis = std.math.max(0, extra_millis);
    const total = loop_millis + sleep_millis;
    start_loop_millis += total;
    target_time += total;
    //std.debug.print("start {d} + loop_millis {d} and total {d}\n", .{start_loop_millis, loop_millis, total});
    //std.debug.print(".", .{});

    c.SDL_Delay(@intCast(u32, sleep_millis));
  }

  c.SDL_DestroyRenderer(renderer);
  c.SDL_DestroyWindow(window);
  c.SDL_Quit();
}

