const std = @import("std");
const builtin = @import("builtin");
const c = @import("c.zig");
const gui = @import("gui.zig");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

pub fn main() void {
  if (c.SDL_Init(c.SDL_INIT_EVERYTHING) < 0) {
    std.debug.print("Couldn't initialize SDL: {s}\n", .{c.SDL_GetError()});
    return;
  }

  if (c.TTF_Init() < 0) {
    std.debug.print("Couldn't initialize SDL_ttf: {s}\n", .{c.SDL_GetError()});
    return;
  }

  var window = c.SDL_CreateWindow("Gui Test", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 360, 600, c.SDL_WINDOW_ALLOW_HIGHDPI | c.SDL_WINDOW_RESIZABLE)
  orelse {
    std.debug.print("Failed to open window: {s}\n", .{c.SDL_GetError()});
    return;
  };

  _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "linear");

  var renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC)
    orelse {
    std.debug.print("Failed to create renderer: {s}\n", .{c.SDL_GetError()});
    return;
  };

  _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND);

  var win = gui.Window.init(gpa, window, renderer);

  main_loop: while (true) {
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    win.begin(arena);

    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event) != 0) {
      win.addEvent(event);
      switch (event.type) {
        c.SDL_KEYDOWN, c.SDL_KEYUP => |updown| {
          if (updown == c.SDL_KEYDOWN and ((event.key.keysym.mod & c.KMOD_CTRL) > 0) and event.key.keysym.sym == c.SDLK_q) {
            break :main_loop;
          }
        },
        c.SDL_QUIT => {
          //std.debug.print("SDL_QUIT\n", .{});
          break :main_loop;
        },
        else => {
          //std.debug.print("other event\n", .{});
        }
      }
    }

    win.endEvents();

    {
      var box = gui.Box(@src(), 0, .vertical, .{.expand = .both, .background = false});
      defer box.deinit();

      var paned = gui.Paned(@src(), 0, .horizontal, 400, .{.expand = .both, .background = false});
      const collapsed = paned.collapsed();

      podcastSide(arena, paned);
      episodeSide(arena, paned);

      paned.deinit();

      if (collapsed) {
        player(arena);
      }
    }

    win.end(null);
  }

  c.SDL_DestroyRenderer(renderer);
  c.SDL_DestroyWindow(window);
  c.SDL_Quit();
}

var show_dialog: bool = false;

fn podcastSide(arena: std.mem.Allocator, paned: *gui.PanedWidget) void {
  var box = gui.Box(@src(), 0, .vertical, .{
    .expand = .both,
    .color_style = .window});
  defer box.deinit();

  {
    var overlay = gui.Overlay(@src(), 0, .{.expand = .horizontal});
    defer overlay.deinit();

    {
      var menu = gui.Menu(@src(), 0, .horizontal, .{
        .expand = .horizontal,
      //.color_style = .window,
      });
      defer menu.deinit();

      gui.Spacer(@src(), 0, .{.expand = .horizontal});

      const oo = gui.OptionsSet(.{
        .expand = .none, 
        .padding = gui.Rect.all(4),
        .corner_radius = gui.Rect.all(5)});
      defer gui.OptionsReset(oo);
      if (gui.MenuItemLabel(@src(), 0, "Hello", true, .{})) |r| {
        var fw = gui.Popup(@src(), 0, gui.Rect.fromPoint(gui.Point{.x = r.x, .y = r.y + r.h}), &menu.submenus_activated, menu, .{});
        defer fw.deinit();
        if (gui.MenuItemLabel(@src(), 0, "Add RSS", false, .{})) |rr| {
          _ = rr;
          show_dialog = true;
          gui.MenuGet().?.close();
        }
      }
    }

    gui.Label(@src(), 0, "fps {d}", .{@round(gui.FPS())}, .{
      .margin = gui.Rect.all(4),
      .expand = .none, 
      .gravity = .upleft, 
      .background = false});
  }

  if (show_dialog) {
    const oo2 = gui.OptionsSet(.{.corner_radius = gui.Rect.all(5), .padding = gui.Rect.all(4)});
    defer gui.OptionsReset(oo2);

    var dialog = gui.FloatingWindow(@src(), 0, true, gui.Rect{}, &show_dialog, .{.color_style = .window});
    defer dialog.deinit();

    _ = gui.OptionsSet(.{.margin = gui.Rect.all(4), .padding = gui.Rect.all(6)});

    gui.LabelNoFormat(@src(), 0, "Add RSS Feed", .{.gravity = .center, .background = false});

    const TextEntryText = struct {
      //var text = array(u8, 100, "abcdefghijklmnopqrstuvwxyz");
      var text1 = array(u8, 100, "");
      fn array(comptime T: type, comptime size: usize, items: ?[]const T) [size]T {
        var output = std.mem.zeroes([size]T);
        if (items) |slice| std.mem.copy(T, &output, slice);
        return output;
      }
    };

    gui.TextEntry(@src(), 0, 26.0, &TextEntryText.text1, .{.gravity = .center, .color_style = .content, .border = gui.Rect.all(1)});

    var box2 = gui.Box(@src(), 0, .horizontal, gui.OptionsGet(.{.gravity = .right}).plain());
    defer box2.deinit();
    if (gui.Button(@src(), 0, "Ok", .{})) {
      dialog.close();
    }
    if (gui.Button(@src(), 0, "Cancel", .{})) {
      dialog.close();
    }
  }

  var scroll = gui.ScrollArea(@src(), 0, .{.expand = .both, .color_style = .window, .background = false});

  const oo3 = gui.OptionsSet(.{
    .expand = .horizontal,
    .gravity = .left,
    .color_style = .content,
  });
  defer gui.OptionsReset(oo3);

  var i: usize = 1;
  while (i < 8) : (i += 1) {
    const title = std.fmt.allocPrint(arena, "Podcast {d}", .{i}) catch unreachable;
    var margin: gui.Rect = .{.x = 8, .y = 0, .w = 8, .h = 0};
    var border: gui.Rect = .{.x = 1, .y = 0, .w = 1, .h = 0};
    var corner = gui.Rect.all(0);

    if (i != 1) {
      gui.Separator(@src(), i, .{.margin = margin, .min_size = .{.w = 1, .h = 1}, .border = .{.x = 1, .y = 1, .w = 0, .h = 0}});
    }

    if (i == 1) {
      margin.y = 8;
      border.y = 1;
      corner.x = 9;
      corner.y = 9;
    }
    else if (i == 7) {
      margin.h = 8;
      border.h = 1;
      corner.w = 9;
      corner.h = 9;
    }

    if (gui.Button(@src(), i, title, .{
        .margin = margin,
        .border = border,
        .corner_radius = corner,
        .padding = gui.Rect.all(8)})) {
      paned.showOther();
    }
  }

  scroll.deinit();

  if (!paned.collapsed()) {
    player(arena);
  }
}

fn episodeSide(arena: std.mem.Allocator, paned: *gui.PanedWidget) void {
  _ = arena;
  var box = gui.Box(@src(), 0, .vertical, .{.expand = .both, .color_style = .window});
  defer box.deinit();
  if (paned.collapsed()) {
    var menu = gui.Menu(@src(), 0, .horizontal, .{.expand = .horizontal, .color_style = .window});
    defer menu.deinit();

    if (gui.MenuItemLabel(@src(), 0, "Back", false, .{.margin = gui.Rect.all(4), .corner_radius = gui.Rect.all(5)})) |rr| {
      _ = rr;
      paned.showOther();
    }
  }

  var scroll = gui.ScrollArea(@src(), 0, .{.expand = .both, .background = false, .color_style = .window});
  defer scroll.deinit();

  const oo = gui.OptionsSet(.{.margin = gui.Rect.all(4), .padding = gui.Rect.all(4)});
  defer gui.OptionsReset(oo);

  var i: usize = 0;
  while (i < 10) : (i += 1) {
    var tl = gui.TextLayout(@src(), i, .{.expand = .horizontal, .font_line_skip_factor = 1.1, .color_style = .content});
    {
      var cbox = gui.Box(@src(), 0, .vertical, gui.OptionsGet(.{.gravity = .upright}).plain());
      defer cbox.deinit();

      _ = gui.ButtonIcon(@src(), 0, 18, "play",
        gui.icons.papirus.actions.media_playback_start_symbolic, .{});
      _ = gui.ButtonIcon(@src(), 0, 18, "more",
        gui.icons.papirus.actions.view_more_symbolic, .{});
    }

    tl.addText("Episode Title\n", .{.font_style = .heading, .font_line_skip_factor = 1.3});
    const lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.";
    tl.addText(lorem, .{});
    tl.deinit();
  }
}

fn player(arena: std.mem.Allocator) void {
  _ = arena;
  const oo = gui.OptionsSet(.{
    .expand = .horizontal,
    .color_style = .content,
  });
  defer gui.OptionsReset(oo);

  var box2 = gui.Box(@src(), 0, .vertical, .{});
  defer box2.deinit();

  gui.Label(@src(), 0, "Title of the playing episode", .{}, .{
    .margin = gui.Rect{.x = 8, .y = 4, .w = 8, .h = 4},
    .font_style = .heading,
  });

  var box3 = gui.Box(@src(), 0, .horizontal, .{
    .margin = .{.x = 4, .y = 0, .w = 4, .h = 4},
    .padding = gui.Rect.all(0),
  });
  defer box3.deinit();

  _ = gui.OptionsSet(.{
    .gravity = .center,
    .color_style = .control,
    .padding = gui.Rect.all(4),
    .corner_radius = gui.Rect.all(5),
    .margin = gui.Rect.all(4)});

  _ = gui.ButtonIcon(@src(), 0, 20, "back",
    gui.icons.papirus.actions.media_seek_backward_symbolic, .{});

  gui.Label(@src(), 0, "0.00%", .{}, .{.color_style = .content});

  _ = gui.ButtonIcon(@src(), 0, 20, "forward",
    gui.icons.papirus.actions.media_seek_forward_symbolic, .{});

  _ = gui.ButtonIcon(@src(), 0, 20, "play",
    gui.icons.papirus.actions.media_playback_start_symbolic, .{});

}


