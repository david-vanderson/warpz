const std = @import("std");

const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
});

const SCREEN_WIDTH = 1280;
const SCREEN_HEIGHT = 720;
 
var renderer: *c.SDL_Renderer = undefined;
var window: *c.SDL_Window = undefined;

pub fn main() !void {
  if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
    std.debug.print("Couldn't initialize SDL: {s}\n", .{c.SDL_GetError()});
    return;
  }

  window = c.SDL_CreateWindow("Shooter 01", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, SCREEN_WIDTH, SCREEN_HEIGHT, 0)
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
  var rot: f32 = 50.0;

  loop: while (true) {
    _ = c.SDL_SetRenderDrawColor(renderer, 96, 128, 255, 255);
    _ = c.SDL_RenderClear(renderer);

    _ = c.SDL_RenderCopyEx(renderer, texture, &srcr, &desr, rot, 0, flip);

    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event) != 0) {
      switch (event.type) {
        c.SDL_KEYDOWN => {
          switch (event.key.keysym.sym) {
            c.SDLK_LEFT => rot += 1,
            c.SDLK_RIGHT => rot -= 1,
            c.SDLK_ESCAPE => break :loop,
            else => {},
          }
        },
        c.SDL_QUIT => {
          //std.debug.print("SDL_QUIT\n", .{});
          break :loop;
        },
        else => {
          //std.debug.print("other event\n", .{});
          break;
        }
      }
    }
    c.SDL_RenderPresent(renderer);
    c.SDL_Delay(16);
  }

  c.SDL_DestroyRenderer(renderer);
  c.SDL_DestroyWindow(window);
  c.SDL_Quit();
}

