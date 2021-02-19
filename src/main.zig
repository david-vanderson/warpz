const std = @import("std");

const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
    @cInclude("SDL2/SDL_ttf.h");
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

  if (c.TTF_Init() < 0) {
    std.debug.print("Couldn't initialize SDL_ttf: {s}\n", .{c.SDL_GetError()});
    return;
  }

  const font = c.TTF_OpenFont("ttf-bitstream-vera-1.10/VeraMono.ttf", 12);

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

  loop: while (true) {
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

