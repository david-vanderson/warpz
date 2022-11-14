const std = @import("std");
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

  var window = c.SDL_CreateWindow("Gui Test", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 800, 600, c.SDL_WINDOW_ALLOW_HIGHDPI | c.SDL_WINDOW_RESIZABLE)
  orelse {
    std.debug.print("Failed to open window: {s}\n", .{c.SDL_GetError()});
    return;
  };

  _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "linear");

  var renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED)// | c.SDL_RENDERER_PRESENTVSYNC)
    orelse {
    std.debug.print("Failed to create renderer: {s}\n", .{c.SDL_GetError()});
    return;
  };

  _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND);

  var win = gui.Window.init(gpa, window, renderer);

  var buttons: [3][6]bool = undefined;
  for (buttons) |*b| {
    b.* = [_]bool{true} ** 6;
  }

  var maxz: usize = 20;
  _ = maxz;
  var floats: [6]bool = [_]bool{false} ** 6;

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
          if (updown == c.SDL_KEYDOWN and event.key.keysym.sym == c.SDLK_t) {
            for (floats) |f, fi| {
              if (!f) {
                floats[fi] = true;
                break;
              }
            }
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
      const oo = gui.OptionsSet(.{.expand = .both});
      var overlay = gui.Overlay(@src(), 0, .{});
      defer overlay.deinit();

      const scale = gui.Scale(@src(), 0, 1, .{});
      defer scale.deinit();

      const context = gui.Context(@src(), 0, .{});
      defer context.deinit();
      gui.OptionsReset(oo);

      if (context.activePoint()) |cp| {
        //std.debug.print("context.rect {}\n", .{context.rect});
        var fw2 = gui.Popup(@src(), 0, gui.Rect.fromPoint(cp), &context.active, null, .{});
        defer fw2.deinit();

        _ = gui.MenuItemLabel(@src(), 0, "Cut", false, .{});
        if (gui.MenuItemLabel(@src(), 0, "Close", false, .{}) != null) {
          gui.MenuGet().?.close();
        }
        _ = gui.MenuItemLabel(@src(), 0, "Paste", false, .{});
      }

      {
        var layout = gui.Box(@src(), 0, .vertical, .{});
        defer layout.deinit();

        {
          var menu = gui.Menu(@src(), 0, .horizontal, .{});
          defer menu.deinit();

          {
            if (gui.MenuItemLabel(@src(), 0, "File", true, .{})) |r| {
              var fw = gui.Popup(@src(), 0, gui.Rect.fromPoint(gui.Point{.x = r.x, .y = r.y + r.h}), &menu.submenus_activated, menu, .{});
              defer fw.deinit();

              if (gui.MenuItemLabel(@src(), 0, "Open...", true, .{})) |rr| {
                var menu_rect2 = rr;
                menu_rect2.x += menu_rect2.w;
                var fw2 = gui.Popup(@src(), 0, menu_rect2, null, null, .{});
                defer fw2.deinit();

                _ = gui.MenuItemLabel(@src(), 0, "Cut", false, .{});
                if (gui.MenuItemLabel(@src(), 0, "Close", false, .{}) != null) {
                  gui.MenuGet().?.close();
                }
                _ = gui.MenuItemLabel(@src(), 0, "Paste", false, .{});
              }

              if (gui.MenuItemLabel(@src(), 0, "Close", false, .{}) != null) {
                gui.MenuGet().?.close();
              }
              _ = gui.MenuItemLabel(@src(), 0, "Print", false, .{});
            }
          }

          {
            if (gui.MenuItemLabel(@src(), 0, "Edit", true, .{})) |r| {
              var fw = gui.Popup(@src(), 0, gui.Rect.fromPoint(gui.Point{.x = r.x, .y = r.y + r.h}), &menu.submenus_activated, menu, .{});
              defer fw.deinit();

              _ = gui.MenuItemLabel(@src(), 0, "Cut", false, .{});
              _ = gui.MenuItemLabel(@src(), 0, "Copy", false, .{});
              _ = gui.MenuItemLabel(@src(), 0, "Paste", false, .{});
            }
          }
        }

        //{
        //  //const e2 = gui.Expand(.horizontal);
        //  //defer _ = gui.Expand(e2);

        //  var margin = gui.Margin(gui.Rect{.x = 20, .y = 20, .w = 20, .h = 20});
        //  defer _ = gui.Margin(margin);

        //  var box = gui.Box(@src(), 0, .horizontal);
        //  defer box.deinit();
        // 
        //  for (buttons) |*buttoncol, k| {
        //    if (k != 0) {
        //      gui.Spacer(@src(), k, 6);
        //    }
        //    if (buttoncol[0]) {
        //      var margin2 = gui.Margin(gui.Rect{.x = 4, .y = 4, .w = 4, .h = 4});
        //      defer _ = gui.Margin(margin2);

        //      var box2 = gui.Box(@src(), k, .vertical);
        //      defer box2.deinit();

        //      for (buttoncol) |b, i| {
        //        if (b) {
        //          if (i != 0) {
        //            gui.Spacer(@src(), i, 6);
        //            //gui.Label(@src(), i, "Label", .{});
        //          }
        //          var buf: [100:0]u8 = undefined;
        //          if (k == 0) {
        //            _ = std.fmt.bufPrintZ(&buf, "HELLO {d}", .{i}) catch unreachable;
        //          }
        //          else if (k == 1) {
        //            _ = std.fmt.bufPrintZ(&buf, "middle {d}", .{i}) catch unreachable;
        //          }
        //          else {
        //            _ = std.fmt.bufPrintZ(&buf, "bye {d}", .{i}) catch unreachable;
        //          }
        //          if (gui.Button(@src(), i, &buf)) {
        //            if (i == 0) {
        //              buttoncol[0] = false;
        //            }
        //            else if (i == 5) {
        //              buttons[k+1][0] = true;
        //            }
        //            else if (i % 2 == 0) {
        //              std.debug.print("Adding {d}\n", .{i + 1});
        //              buttoncol[i+1] = true;
        //            }
        //            else {
        //              std.debug.print("Removing {d}\n", .{i});
        //              buttoncol[i] = false;
        //            }
        //          }
        //        }
        //      }
        //    }
        //  }
        //}

        {
          var scroll = gui.ScrollArea(@src(), 0, .{.min_size = .{.w = 50, .h = 200},
            .margin = gui.Rect.all(8),
            .border = gui.Rect.all(1),
            .padding = gui.Rect.all(8),
          });
          defer scroll.deinit();

          var buf: [100]u8 = undefined;
          var z: usize = 0;
          while (z < maxz) : (z += 1) {
            const buf_slice = std.fmt.bufPrint(&buf, "Button {d}", .{z}) catch unreachable;
            if (gui.Button(@src(), z, buf_slice, .{})) {
              if (z % 2 == 0) {
                maxz += 1;
              }
              else {
                maxz -= 1;
              }
            }
          }
        }

        {
          var button = gui.ButtonWidget{};
          _ = button.init(@src(), 0, "Wiggle", .{.tab_index = 10});

          if (gui.AnimationGet(button.bc.wd.id, .xoffset)) |a| {
            button.bc.wd.rect.x += a.lerp();
          }

          if (button.install()) {
            const a = gui.Animation{.start_val = 0, .end_val = 200, .start_time = 0, .end_time = 10_000_000};
            gui.Animate(button.bc.wd.id, .xoffset, a);
          }
        }

        {
          if (gui.Button(@src(), 0, "Stroke Test", .{})) {
            StrokeTest.show_dialog = !StrokeTest.show_dialog;
          }

          if (StrokeTest.show_dialog) {
            show_stroke_test_window();
          }
        }

        {
          const millis = @divFloor(gui.frameTimeNS(), 1_000_000);
          const left = @intCast(i32, @rem(millis, 1000));

          var label = gui.LabelWidget{};
          label.init(@src(), 0, "{d} {d}", .{@divTrunc(millis, 1000), @intCast(u32, left)}, .{.margin = gui.Rect.all(4), .min_size = gui.OptionsGet(.{}).font().textSize("0" ** 15), .gravity = .left});
          label.install();

          if (gui.TimerDone(label.wd.id) or !gui.TimerExists(label.wd.id)) {
            const wait = 1000 * (1000 - left);
            gui.TimerSet(label.wd.id, wait);
            //std.debug.print("add timer {d}\n", .{wait});
          }
        }

        {
          gui.Spinner(@src(), 0, 50);
        }

        {
          const CheckboxBool = struct {
            var b: bool = false;
          };

          var checklabel: []const u8 = "Check Me No";
          if (CheckboxBool.b) {
            checklabel = "Check Me Yes";
          }

          gui.Checkbox(@src(), 0, &CheckboxBool.b, checklabel, .{.tab_index = 6, .min_size = .{.w = 100, .h = 0}});
        }

        {
          const TextEntryText = struct {
            //var text = array(u8, 100, "abcdefghijklmnopqrstuvwxyz");
            var text1 = array(u8, 100, "abc");
            var text2 = array(u8, 100, "abc");
            fn array(comptime T: type, comptime size: usize, items: ?[]const T) [size]T {
              var output = std.mem.zeroes([size]T);
              if (items) |slice| std.mem.copy(T, &output, slice);
              return output;
            }
          };

          gui.TextEntry(@src(), 0, 26.0, &TextEntryText.text1, .{});
          gui.TextEntry(@src(), 0, 26.0, &TextEntryText.text2, .{});
        }
      }
      

      const fps = gui.FPS();
      //std.debug.print("fps {d}\n", .{@round(fps)});
      //gui.render_text = true;
      gui.Label(@src(), 0, "fps {d:4.2}", .{fps}, .{.gravity = .upright});
      //gui.render_text = false;
    }

    {
      const FloatingWindowTest = struct {
        var show: bool = false;
      };

      if (gui.Button(@src(), 0, "Floating Window", .{})) {
        FloatingWindowTest.show = !FloatingWindowTest.show;
      }

      if (FloatingWindowTest.show) {
        const fwrect = gui.Rect{.x = 300.25, .y = 200.25, .w = 300, .h = 200};
        var fwin = gui.FloatingWindow(@src(), 0, false, fwrect, &FloatingWindowTest.show, .{});
        defer fwin.deinit();
        gui.LabelNoFormat(@src(), 0, "Floating Window", .{.margin = .{}, .gravity = .center, .background = false});

        {
          var menu = gui.Menu(@src(), 0, .horizontal, .{});
          defer menu.deinit();

          {
            if (gui.MenuItemLabel(@src(), 0, "File", true, .{})) |r| {
              var fw = gui.Popup(@src(), 0, gui.Rect.fromPoint(gui.Point{.x = r.x, .y = r.y + r.h}), &menu.submenus_activated, menu, .{});
              defer fw.deinit();

              if (gui.MenuItemLabel(@src(), 0, "Open...", true, .{})) |rr| {
                var menu_rect2 = rr;
                menu_rect2.x += menu_rect2.w;
                var fw2 = gui.Popup(@src(), 0, menu_rect2, null, null, .{});
                defer fw2.deinit();

                _ = gui.MenuItemLabel(@src(), 0, "Cut", false, .{});
                if (gui.MenuItemLabel(@src(), 0, "Close", false, .{}) != null) {
                  gui.MenuGet().?.close();
                }
                _ = gui.MenuItemLabel(@src(), 0, "Paste", false, .{});
              }

              if (gui.MenuItemLabel(@src(), 0, "Close", false, .{}) != null) {
                gui.MenuGet().?.close();
              }
              _ = gui.MenuItemLabel(@src(), 0, "Print", false, .{});
            }
          }

          {
            if (gui.MenuItemLabel(@src(), 0, "Edit", true, .{})) |r| {
              var fw = gui.Popup(@src(), 0, gui.Rect.fromPoint(gui.Point{.x = r.x, .y = r.y + r.h}), &menu.submenus_activated, menu, .{});
              defer fw.deinit();

              _ = gui.MenuItemLabel(@src(), 0, "Cut", false, .{});
              _ = gui.MenuItemLabel(@src(), 0, "Copy", false, .{});
              _ = gui.MenuItemLabel(@src(), 0, "Paste", false, .{});
            }
          }
        }
      

        gui.Label(@src(), 0, "Pretty Cool", .{}, .{.font_body = .{.name = "VeraMono", .ttf_bytes = gui.fonts.bitstream_vera.VeraMono, .size = 20}});

        if (gui.Button(@src(), 0, "button", .{})) {
          std.debug.print("floating button\n", .{});
          floats[0] = true;
        }

        const CheckboxBoolFloat = struct {
          var b: bool = false;
        };

        var checklabel: []const u8 = "Check Me No";
        if (CheckboxBoolFloat.b) {
          checklabel = "Check Me Yes";
        }

        gui.Checkbox(@src(), 0, &CheckboxBoolFloat.b, checklabel, .{});

        for (floats) |*f, fi| {
          if (f.*) {
            const modal = if (fi % 2 == 0) true else false;
            var name: []const u8 = "";
            if (modal) {
              name = "Modal";
            }
            var buf = std.mem.zeroes([100]u8);
            var buf_slice = std.fmt.bufPrintZ(&buf, "{d} {s} Dialog", .{fi, name}) catch unreachable;
            const fwrect2 = gui.Rect{.x = 100.25 + 20 * @intToFloat(f32, fi), .y = 100.25, .w = 300, .h = 200};
            var fw2 = gui.FloatingWindow(@src(), fi, modal, fwrect2, f, .{.color_style = .window});
            defer fw2.deinit();
            gui.LabelNoFormat(@src(), 0, buf_slice, .{.margin = .{}, .gravity = .center, .background = false});

            gui.Label(@src(), 0, "Asking a Question", .{}, .{});

            const oo = gui.OptionsSet(.{.margin = gui.Rect.all(4), .expand = .horizontal});
            var box = gui.Box(@src(), 0, .horizontal, .{});

            if (gui.Button(@src(), 0, "Yes", .{})) {
              std.debug.print("Yes {d}\n", .{fi});
              floats[fi+1] = true;
            }

            if (gui.Button(@src(), 0, "No", .{})) {
              std.debug.print("No {d}\n", .{fi});
              fw2.close();
            }

            gui.OptionsReset(oo);
            box.deinit();

            {
              var scroll = gui.ScrollArea(@src(), 0, .{.expand = .both});
              defer scroll.deinit();

              inline for (@typeInfo(gui.icons.papirus.actions).Struct.decls) |d, i| {
                var iconbox = gui.Box(@src(), 0, .horizontal, .{.expand = .horizontal});
                defer iconbox.deinit();
                _ = gui.ButtonIcon(@src(), i, 20, d.name, @field(gui.icons.papirus.actions, d.name), .{});
                gui.Label(@src(), i, d.name, .{}, .{});

                //if (i == 10) {
                  //break;
                //}
              }
            }
            
          }
        }


        var scroll = gui.ScrollArea(@src(), 0, .{.expand = .both});
        defer scroll.deinit();
        var tl = gui.TextLayout(@src(), 0, .{.expand = .both});
        {
          _ = gui.Button(@src(), 0, "Corner", .{.gravity = .upleft});
          _ = gui.Button(@src(), 0, "Corner", .{.gravity = .upright});
        }
        const lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.";
        //const lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore";
        tl.addText(lorem, .{});
        //var it = std.mem.split(u8, lorem, " ");
        //while (it.next()) |word| {
        //  tl.addText(word);
        //  tl.addText(" ");
        //}
        tl.deinit();
      }
    }

    win.end(10);
  }

  c.SDL_DestroyRenderer(renderer);
  c.SDL_DestroyWindow(window);
  c.SDL_Quit();
}

fn show_stroke_test_window() void {
  var win = gui.FloatingWindow(@src(), 0, false, gui.Rect{}, &StrokeTest.show_dialog, .{});
  defer win.deinit();
  gui.LabelNoFormat(@src(), 0, "Stroke Test", .{.margin = .{}, .gravity = .center, .background = false});

  var scale = gui.Scale(@src(), 0, 1, .{.expand = .both});
  defer scale.deinit();

  var st = StrokeTest{};
  st.install(@src(), 0, .{.min_size = .{.w = 400, .h = 400}, .expand = .both});
  defer st.deinit();

}

pub const StrokeTest = struct {
  const Self = @This();
  var show_dialog: bool = false;
  var pointsArray: [10]gui.Point = [1]gui.Point{.{}} ** 10;
  var points: []gui.Point = pointsArray[0..0];
  var dragi: ?usize = null;
  var thickness: f32 = 1.0;

  id: u32 = undefined,
  parent: gui.Widget = undefined,
  rect: gui.Rect = .{},
  minSize: gui.Size = .{},

  pub fn install(self: *Self, src: std.builtin.SourceLocation, id_extra: usize, opts: gui.Options) void {
    const options = gui.OptionsGet(opts);
    self.parent = gui.ParentSet(self.widget());
    self.id = self.parent.extendID(src, id_extra);
    self.rect = self.parent.rectFor(self.id, options);
    self.minSize = options.min_size orelse .{};
    gui.debug("{x} StrokeTest {}", .{self.id, self.rect});

    _ = gui.CaptureMouseMaintain(self.id);
    self.processEvents();

    const rs = self.parent.screenRectScale(self.rect);
    if (options.background orelse false) {
      gui.PathAddRect(rs.r, options.corner_radiusGet());
      gui.PathFillConvex(options.color_bg());
    }

    const fill_color = gui.Color{.r = 200, .g = 200, .b = 200, .a = 255};
    for (points) |p| {
      var rect = gui.Rect.fromPoint(p.plus(.{.x = -10, .y = -10})).toSize(.{.w = 20, .h = 20});
      const rsrect = self.screenRectScale(rect);
      gui.PathAddRect(rsrect.r, gui.Rect.all(1));
      gui.PathFillConvex(fill_color);
    }

    for (points) |p| {
      const rsp = self.screenRectScale(self.rect).childPoint(p);
      gui.PathAddPoint(rsp);
    }

    const stroke_color = gui.Color{.r = 0, .g = 0, .b = 255, .a = 150};
    gui.PathStroke(false, rs.s * thickness, stroke_color);
  }

  fn widget(self: *Self) gui.Widget {
    return gui.Widget.init(self, ID, rectFor, minSizeForChild, screenRectScale, bubbleEvent);
  }

  fn ID(self: *const Self) u32 {
    return self.id;
  }

  pub fn rectFor(self: *Self, id: u32, opts: gui.Options) gui.Rect {
    return gui.PlaceIn(id, self.rect, opts);
  }

  pub fn minSizeForChild(self: *Self, s: gui.Size) void {
    self.minSize = gui.Size.max(self.minSize, s);
  }

  pub fn screenRectScale(self: *Self, r: gui.Rect) gui.RectScale {
    return self.parent.screenRectScale(self.rect).child(r);
  }

  pub fn bubbleEvent(self: *Self, e: *gui.Event) void {
    self.parent.bubbleEvent(e);
  }

  pub fn processEvents(self: *Self) void {
    const rs = self.parent.screenRectScale(self.rect);
    var iter = gui.EventIterator.init(self.id, rs.r);
    while (iter.next()) |e| {
      switch (e.evt) {
        .mouse => |me| {
          const mp = me.p.inRectScale(rs);
          switch (me.state) {
            .leftdown => {
              e.handled = true;
              dragi = null;

              for (points) |p, i| {
                const dp = gui.Point.diff(p, mp);
                if (@fabs(dp.x) < 5 and @fabs(dp.y) < 5) {
                  dragi = i;
                  break;
                }
              }

              if (dragi == null and points.len < pointsArray.len) {
                dragi = points.len;
                points.len += 1;
                points[dragi.?] = mp;
              }

              if (dragi != null) {
                gui.CaptureMouse(self.id);
                gui.DragPreStart(me.p, .crosshair);
              }
            },
            .leftup => {
              e.handled = true;
              gui.CaptureMouse(null);
              gui.DragEnd();
            },
            .motion => {
              e.handled = true;
              if (gui.Dragging(me.p)) |dps| {
                const dp = dps.scale(1 / rs.s);
                points[dragi.?].x += dp.x;
                points[dragi.?].y += dp.y;
              }
            },
            .wheel_y => {
              e.handled = true;
              var base: f32 = 1.05;
              const zs = @exp(@log(base) * me.wheel);
              if (zs != 1.0) {
                thickness *= zs;
              }
            },
            else => {},
          }
        },
        else => {},
      }
    }
  }

  pub fn deinit(self: *Self) void {
    gui.MinSizeSet(self.id, self.minSize);
    self.parent.minSizeForChild(self.minSize);
    _ = gui.ParentSet(self.parent);
  }
};

