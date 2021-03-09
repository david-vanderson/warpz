const std = @import("std");

const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
    @cInclude("SDL2/SDL_ttf.h");
});

const SCREEN_WIDTH = 1280;
const SCREEN_HEIGHT = 520;
const TICK = 33;

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = &gpa_instance.allocator;


const Ship = struct {
};

const Player = struct {
  on_ship: u64,
};

const Entity = union(enum) {
  ship: Ship,
  player: Player,
};

const Posvel = struct {
  x: f64,
  y: f64,
  r: f64,
  dx: f64,
  dy: f64,
  dr: f64,
};

var next_id: u64 = 1;
fn nextId() u64 {
  defer next_id += 1;
  return next_id;
}

const Object = struct {
  // unique id for each game object
  id: u64,
  // millis since scenario start for age-related stuff (animations, fading, dying)
  start_time: i64,
  // usually true but set to false when an Object needs to be removed
  alive: bool,
  // position and velocity info 
  posvel: Posvel,
  entity: Entity,
};

const Scenario = struct {
  const Self = @This();
  // unique id to disambiguate when we switch scenarios
  id: u64,
  // millis since scenario start
  time: i64,
  width: f64,
  height: f64,
  objects: std.ArrayList(Object),

  pub fn findId(self: *Self, id: u64) !*Object {
    for (self.objects.items) |*o| {
      if (o.id == id) {
        return o;
      } 
    }

    return error.notFound;
  }
};

// 0 before we are assigned an id by the server
var meid: u64 = 0;
 
var renderer: *c.SDL_Renderer = undefined;
var window: *c.SDL_Window = undefined;
var font: ?*c.TTF_Font = undefined;

fn renderText(text: [:0]u8, left: i32, top: i32) void {
  const color = c.SDL_Color{.r = 255, .g = 255, .b = 255, .a = 255};
  const textSurface = c.TTF_RenderUTF8_Blended(font, text, color);
  const textTexture = c.SDL_CreateTextureFromSurface(renderer, textSurface);
  const tsrcr = c.SDL_Rect{.x = 0, .y = 0, .w = textSurface.*.w, .h = textSurface.*.h};
  const tdesr = c.SDL_Rect{.x = left, .y = top, .w = tsrcr.w, .h = tsrcr.h};
  //_ = c.SDL_SetTextureAlphaMod(textTexture, @floatToInt(u8, alpha * 255));
  //_ = c.SDL_SetTextureColorMod(textTexture, red, 0, 0);
  const flip = @intToEnum(c.SDL_RendererFlip, c.SDL_FLIP_NONE);
  _ = c.SDL_RenderCopyEx(renderer, textTexture, &tsrcr, &tdesr, 0, 0, flip);
}

const FLIP_NONE = @intToEnum(c.SDL_RendererFlip, c.SDL_FLIP_NONE);

fn drawShip(ship: *Object, texture: *c.SDL_Texture, alpha: f32, red: u8) void {
  const srcr = c.SDL_Rect{.x = 0, .y = 0, .w = 166, .h = 166};
  const desr = c.SDL_Rect{
    .x = @floatToInt(c_int, ship.posvel.x),
    .y = @floatToInt(c_int, ship.posvel.y),
    .w = srcr.w, .h = srcr.h};
  _ = c.SDL_SetTextureAlphaMod(texture, @floatToInt(u8, alpha * 255));
  _ = c.SDL_SetTextureColorMod(texture, red, 0, 0);
  _ = c.SDL_RenderCopyEx(renderer, texture, &srcr, &desr, ship.posvel.r, 0, FLIP_NONE);
}

pub fn main() !void {
  if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
    std.debug.print("Couldn't initialize SDL: {s}\n", .{c.SDL_GetError()});
    return;
  }

  if (c.TTF_Init() < 0) {
    std.debug.print("Couldn't initialize SDL_ttf: {s}\n", .{c.SDL_GetError()});
    return;
  }

  font = c.TTF_OpenFont("ttf-bitstream-vera-1.10/VeraMono.ttf", 12);

  window = c.SDL_CreateWindow("Shooter 01", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, SCREEN_WIDTH, SCREEN_HEIGHT, c.SDL_WINDOW_RESIZABLE)
  orelse {
    std.debug.print("Failed to open {d} x {d} window: {s}\n", .{SCREEN_WIDTH, SCREEN_HEIGHT, c.SDL_GetError()});
    return;
  };
    
  _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "linear");

  renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED)
    orelse {
    std.debug.print("Failed to create renderer: {s}\n", .{c.SDL_GetError()});
    return;
  };

  const texture: *c.SDL_Texture = c.IMG_LoadTexture(renderer, "images/asteroid.png")
    orelse {
    std.debug.print("Failed to create texture: {s}\n", .{c.SDL_GetError()});
    return;
  };

  const srcr = c.SDL_Rect{.x = 0, .y = 0, .w = 166, .h = 166};
  var desr = c.SDL_Rect{.x = 100, .y = 100, .w = srcr.w, .h = srcr.h};
  const flip = @intToEnum(c.SDL_RendererFlip, c.SDL_FLIP_NONE);
  var alpha: f32 = 1.0;
  var red: u8 = 0;
  const red_incr = 6;

  var scenario = Scenario {
    .id = nextId(),
    .time = 0,
    .width = 200.0,
    .height = 100.0,
    .objects = std.ArrayList(Object).init(gpa),
  };

  var a = Object {
    .id = nextId(),
    .start_time = scenario.time,
    .alive = true,
    .posvel = Posvel{
      .x = 1.0,
      .y = 1.0,
      .r = 1.0,
      .dx = 5.0,
      .dy = 5.0,
      .dr = 0.1,
      },
    .entity = Entity{
      .ship = Ship{
      },
    },
  };
  try scenario.objects.append(a);

  var p = Object {
    .id = nextId(),
    .start_time = scenario.time,
    .alive = true,
    .posvel = Posvel{
      .x = 0.0,
      .y = 0.0,
      .r = 0.0,
      .dx = 0.0,
      .dy = 0.0,
      .dr = 0.0,
      },
    .entity = Entity{
      .player = Player{
        .on_ship = 0,
      },
    },
  };
  try scenario.objects.append(p);

  var meId: u64 = 0;
  var meObj: *Object = undefined;

  for (scenario.objects.items) |*o| {
    if (o.entity == .player) {
      meObj = o;
      meId = meObj.id;
      break;
    }
  }

  for (scenario.objects.items) |*o| {
    if (o.entity == .ship) {
      meObj.entity.player.on_ship = o.id;
      break;
    }
  }

  std.debug.print("meId = {d} on_ship = {d}\n", .{meId, meObj.entity.player.on_ship});

  var frame_times = [_]i64{0} ** 10;

  var start_loop_millis: i64 = 0;

  gameloop: while (true) {

    if (start_loop_millis == 0) {
      start_loop_millis = std.time.milliTimestamp();
    }

    meObj = try scenario.findId(meId);
    const meShip = try scenario.findId(meObj.entity.player.on_ship);
    
    _ = c.SDL_SetRenderDrawColor(renderer, 96, 128, 255, 255);
    _ = c.SDL_RenderClear(renderer);

    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event) != 0) {
      switch (event.type) {
        c.SDL_KEYDOWN => {
          switch (event.key.keysym.sym) {
            c.SDLK_LEFT => {
              meShip.posvel.r += 1;
            },
            c.SDLK_RIGHT => {
              meShip.posvel.r -= 1;
            },
            c.SDLK_UP => {
              alpha += 0.1;
              if (alpha > 1.0) alpha = 1.0;
            },
            c.SDLK_DOWN => {
              alpha -= 0.1;
              if (alpha < 0.0) alpha = 0.0;
            },
            c.SDLK_r => {
              red = if (red > (255 - red_incr)) 255 else red + red_incr;
              //std.debug.print("red {d}", .{red});
            },
            c.SDLK_t => {
              red = if (red < red_incr) 0 else red - red_incr;
              //std.debug.print("red {d}", .{red});
            },
            c.SDLK_ESCAPE => break :gameloop,
            else => {},
          }
        },
        c.SDL_QUIT => {
          //std.debug.print("SDL_QUIT\n", .{});
          break :gameloop;
        },
        else => {
          //std.debug.print("other event\n", .{});
          break;
        }
      }
    }

    for (scenario.objects.items) |*o| {
      switch (o.entity) {
        .player => {},
        .ship => {
          drawShip(o, texture, alpha, red);
        },
      }
    }

    if (frame_times[0] > 0) {
      const diff = frame_times[frame_times.len - 1] - frame_times[0];
      const avg = @intToFloat(f32, diff) / @intToFloat(f32, frame_times.len - 1);
      const fps = 1000.0 / avg;
      const fps_int = @floatToInt(i32, fps);
      //std.debug.print("n {d} diff {d} avg {d} fps {d}\n", .{frame_times.len, diff, avg, fps});
      var buf = std.mem.zeroes([100:0]u8);
      var fbs = std.io.fixedBufferStream(&buf);
      try fbs.writer().print("fps {d}", .{fps_int});
      renderText(buf[0..:0], SCREEN_WIDTH - 100, 0);
    }

    c.SDL_RenderPresent(renderer);

    const millis = std.time.milliTimestamp();
    const loop_millis = millis - start_loop_millis;
    const extra_millis = TICK - loop_millis;
    const sleep_millis = std.math.max(1, extra_millis);
    const total = loop_millis + sleep_millis;
    start_loop_millis += total;
    //std.debug.print("start {d} + loop_millis {d} and total {d}\n", .{start_loop_millis, loop_millis, total});

    for (frame_times) |_, i| {
      if (i == (frame_times.len - 1)) {
        frame_times[i] = millis;
      } else {
        frame_times[i] = frame_times[i+1];
      }

      //std.debug.print("frame_times[{d}] = {d}\n", .{i, frame_times[i]});
    }

    c.SDL_Delay(@intCast(u32, sleep_millis));
  }

  c.SDL_DestroyRenderer(renderer);
  c.SDL_DestroyWindow(window);
  c.SDL_Quit();
}

