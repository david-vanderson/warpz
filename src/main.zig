const std = @import("std");

const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
    @cInclude("SDL2/SDL_ttf.h");
});

const SCREEN_WIDTH = 1280;
const SCREEN_HEIGHT = 520;
const TICK = 33;
 
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
  var rot: f32 = 0.0;
  var alpha: f32 = 1.0;
  var red: u8 = 0;
  const red_incr = 6;

  const col = c.SDL_Color{.r = 255, .g = 255, .b = 255, .a = 255};
  const textSurface = c.TTF_RenderUTF8_Blended(font, "Hello World!", col);
  const textTexture = c.SDL_CreateTextureFromSurface(renderer, textSurface);
  const tsrcr = c.SDL_Rect{.x = 0, .y = 0, .w = textSurface.*.w, .h = textSurface.*.h};
  var tdesr = c.SDL_Rect{.x = 20, .y = 20, .w = tsrcr.w, .h = tsrcr.h};

  var frame_times = [_]i64{0} ** 10;

  var start_loop_millis: i64 = 0;

  gameloop: while (true) {

    if (start_loop_millis == 0) {
      start_loop_millis = std.time.milliTimestamp();
    }
    
    _ = c.SDL_SetRenderDrawColor(renderer, 96, 128, 255, 255);
    _ = c.SDL_RenderClear(renderer);

    _ = c.SDL_SetTextureAlphaMod(texture, @floatToInt(u8, alpha * 255));
    _ = c.SDL_SetTextureColorMod(texture, red, 0, 0);
    _ = c.SDL_RenderCopyEx(renderer, texture, &srcr, &desr, rot, 0, flip);

    _ = c.SDL_SetTextureAlphaMod(textTexture, @floatToInt(u8, alpha * 255));
    _ = c.SDL_SetTextureColorMod(textTexture, red, 0, 0);
    _ = c.SDL_RenderCopyEx(renderer, textTexture, &tsrcr, &tdesr, rot, 0, flip);

    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event) != 0) {
      switch (event.type) {
        c.SDL_KEYDOWN => {
          switch (event.key.keysym.sym) {
            c.SDLK_LEFT => {
              rot += 1;
            },
            c.SDLK_RIGHT => {
              rot -= 1;
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

