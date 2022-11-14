const std = @import("std");
const Mailbox = @import("mailbox.zig");
const u = @import("util.zig");
const com = @import("common.zig");
const scenarios = @import("scenarios/scenarios.zig");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

var sig_int: bool = false;

pub fn handleSigInt(_: i32, _: *const std.os.siginfo_t, _: ?*const anyopaque) callconv(.C) void {
  sig_int = true;
}


const Client = struct {
  const Self = @This();
  const State = enum {
    // client connected, waiting for their name
    new,
    // client needs whole space before any updates
    // changing spaces puts all clients into this state
    waiting_for_space,
    // normal state sending all updates
    ok,
    // something happened like socket error, we will remove this client
    leaving,
  };

  state: State,
  player: com.Player,

  conn: std.net.StreamServer.Connection,
  mailbox: Mailbox,
};


var clients = std.ArrayList(Client).init(gpa);

var server: std.net.StreamServer = undefined;

fn listen(self: *std.net.StreamServer, address: std.net.Address) !void {
  const nonblock = std.os.SOCK.NONBLOCK;
  const sock_flags = std.os.SOCK.STREAM | std.os.SOCK.CLOEXEC | nonblock;
  const proto = if (address.any.family == std.os.AF.UNIX) @as(u32, 0) else std.os.IPPROTO.TCP;

  const sockfd = try std.os.socket(address.any.family, sock_flags, proto);
  self.sockfd = sockfd;
  errdefer {
      std.os.closeSocket(sockfd);
      self.sockfd = null;
  }

  if (self.reuse_address) {
      try std.os.setsockopt(
          sockfd,
          std.os.SOL.SOCKET,
          std.os.SO.REUSEADDR,
          &std.mem.toBytes(@as(c_int, 1)),
      );
  }

  var socklen = address.getOsSockLen();
  try std.os.bind(sockfd, &address.any, socklen);
  try std.os.listen(sockfd, self.kernel_backlog);
  try std.os.getsockname(sockfd, &self.listen_address.any, &socklen);
}

fn accept(self: *std.net.StreamServer) !std.net.StreamServer.Connection {
    var accepted_addr: std.net.Address = undefined;
    var adr_len: std.os.socklen_t = @sizeOf(std.net.Address);
    const accept_result = std.os.accept(self.sockfd.?, &accepted_addr.any, &adr_len, std.os.SOCK.CLOEXEC);

    if (accept_result) |fd| {
        return std.net.StreamServer.Connection{
            .stream = std.net.Stream{ .handle = fd },
            .address = accepted_addr,
        };
    } else |err| switch (err) {
        //error.WouldBlock => unreachable,
        else => |e| return e,
    }
}


pub fn run() !void {
  server = std.net.StreamServer.init(.{.reuse_address = true});
  defer server.deinit();

  try listen(&server, std.net.Address.parseIp("127.0.0.1", u.PORT) catch unreachable);
  std.debug.print("listening at {}\n", .{server.listen_address});

  var space = com.Space.init(gpa);
  var scenario = scenarios.initialize(gpa, &space);

  var previous_physics_time = std.time.milliTimestamp();
  while (true) {

    const loop_start_time = std.time.milliTimestamp();

    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    var updates = std.ArrayList(com.Message).init(arena);

    // process new clients
    const mconn = accept(&server) catch |err| switch (err) {
      error.WouldBlock => null, 
      else => unreachable,
    };
    if (mconn) |conn| {
      std.debug.print("server accepted new client {}\n", .{conn});
      var newc = Client{
        .conn = conn,
        .state = Client.State.new,
        .player = com.Player.init(),
        .mailbox = Mailbox {
          .stream = conn.stream,
          .out = com.RingBuffer{.buf = try gpa.alloc(u8, u.RB_SIZE)},
          .in = com.RingBuffer{.buf = try gpa.alloc(u8, u.RB_SIZE)},
        },
      };
      newc.player.id = u.nextId();
      try clients.append(newc);
      try newc.mailbox.out.startMessage();
      const m = com.Message{.new_client = com.NewClient{.id = newc.player.id, .name = newc.player.name}};
      try com.serializeMessage(m, newc.mailbox.out.writer());
      try newc.mailbox.out.endMessage();
      try newc.mailbox.pumpOut();
    }

    // process player commands
    for (clients.items) |*client| {
      if (client.state == .leaving) {
        continue;
      }

      client.mailbox.pumpIn() catch {
        std.debug.print("client {d} pumpIn error\n", .{client.player.id});
        client.state = .leaving;
        continue;
      };

      var size = client.mailbox.in.haveMessage();
      while (size > 0) {
        _ = try client.mailbox.in.reader().readIntBig(u32);
        var num_bytes: u32 = 4;
        while (num_bytes < size) {
          var message = try com.deserializeMessage(client.mailbox.in.reader(), &num_bytes);
          //std.debug.print("server: read {d} {d}: {}\n", .{size, num_bytes, message});
          switch (message) {
            .new_client => |nc| {
              client.player.name = nc.name;
              std.debug.print("server: new player {d} \"{s}\"\n", .{client.player.id, client.player.name});
              client.state = .waiting_for_space;
              var m = com.Message{.player = client.player};
              space.applyChange(m, &updates, null);
            },
            .heartbeat => {
              // just drop it
            },
            .hold => {
              message.hold.id = client.player.id;
              space.applyChange(message, &updates, null);
            },
            .move => {
              // getting a move from a client can only move that person
              message.move.id = client.player.id;
              if (space.findPlayer(message.move.id)) |p| {
                if (p.on_ship_id != message.move.ship_id) {
                  std.debug.print("server dropping {} (ship_id {d} doesn't match player.on_ship_id {d})\n", .{message, message.move.ship_id, p.on_ship_id});
                }
                else {
                  space.applyChange(message, &updates, null);
                }
              }
            },
            .remote_control => {
              message.remote_control.pid = client.player.id;
              space.applyChange(message, &updates, null);
            },
            .pbolt => {
              message.pbolt.pid = client.player.id;
              space.applyChange(message, &updates, null);
            },
            .missile => {
              message.missile.pid = client.player.id;
              space.applyChange(message, &updates, null);
            },
            .launch => {
              message.launch.pid = client.player.id;
              space.applyChange(message, &updates, null);
            },
            .ann_cmd => {
              message.ann_cmd.pid = client.player.id;
              const old_space_id = space.info.id;
              scenario = scenario.annCmdFn(scenario, message.ann_cmd, &space, &updates);
              if (old_space_id != space.info.id) {
                // space got changed, send to all clients
                for (clients.items) |*cli| {
                  if (cli.state == .ok) {
                    cli.state = .waiting_for_space;
                  }
                }
              }
            },
            .space_info,
            .update,
            .player,
            .plasma,
            .explosion,
            .annotation,
            .damage,
            .motion,
            .ship,
            .nebula,
            .remove,
            => {
              std.debug.print("server dropping unexpected message {}\n", .{message});
            },
          }
        }
        size = client.mailbox.in.haveMessage();
      }
    }

    {
      // cull clients who have left
      var i: usize = 0;
      while (i < clients.items.len) {
        if (clients.items[i].state == .leaving) {
          const p = &clients.items[i].player;
          std.debug.print("server: player left {d} \"{s}\"\n", .{p.id, p.name});
          const m = com.Message{.remove = com.Remove{.id = p.id}};
          space.applyChange(m, &updates, null);
          
          gpa.free(clients.items[i].mailbox.in.buf);
          gpa.free(clients.items[i].mailbox.out.buf);
          _ = clients.swapRemove(i);
        }
        else {
          i += 1;
        }
      }
    }

    // simulation tick
    if ((loop_start_time - previous_physics_time) < u.TICK) {
      //std.debug.print("server woke up too early, no tick\n", .{});
    }
    else {
      previous_physics_time += u.TICK;
      var collider = com.Collider.init(arena, &space);
      try space.tick(&updates, &collider);

      // TODO: upkeep
      // TODO: stop warp for ships that hit the edge
      // TODO: end rc for probes
      // TODO: blow up old cannonballs
      for (space.ships.items) |*s| {
        const age = space.info.time - s.obj.start_time;
        if (s.kind == .missile and age > s.duration) {
          // blow up old missiles
          // TODO: make an explosion
          const m = com.Message{.damage = com.Damage{.id = s.obj.id, .damage = s.maxhp, .dmgfx = false}};
          space.applyChange(m, &updates, &collider);
        }
      }

      // end remote control if a player's rc object went away
      for (space.players.items) |*p| {
        if (p.rcid > 0) {
          if (space.findShip(p.rcid)) |s| {
            if (s.obj.alive) {
              // rc object good
              continue;
            }
          }

          // either couldn't find it or it was dead, end rc
          space.playerCleanup(p, &updates, &collider);
        }
      }

      // ai
      var delay: i64 = 0;
      for (space.ships.items) |*s| {
        if (s.ai and (space.info.time - s.ai_time) > s.ai_freq) {
          s.ai_time = space.info.time + delay;
          delay += 1;  // push ais away from all running at the same time
          if (s.kind != .missile) {
            //s.runAIStrat(&space, &updates, &collider);
          }

          _ = s.runAIPilot(&space, arena, &updates, &collider);
        }
      }


      // scenario hook
      const old_space_id = space.info.id;
      scenario = scenario.hookFn(scenario, &space, &updates, &collider);
      if (old_space_id != space.info.id) {
        // space got changed, send to all clients
        for (clients.items) |*client| {
          if (client.state == .ok) {
            client.state = .waiting_for_space;
          }
        }
      }
    }

    space.cull();
    //std.debug.print("players {d}, ships {d}, plasmas: {d}, explosions {d}, backEffects {d}, effects {d}\n", .{space.players.items.len, space.ships.items.len, space.plasmas.items.len, space.explosions.items.len, space.backEffects.items.len, space.effects.items.len});

    // serialize update
    var out = com.RingBuffer{.buf = try arena.alloc(u8, u.RB_SIZE)};
    try out.startMessage();
    //space.info.id += 1;
    try com.serializeMessage(com.Message{.update = space.info}, out.writer());
    for (updates.items) |*up| {
      try com.serializeMessage(up.*, out.writer());
    }
    //try com.serializeMessage(Message{.ship = space.ships.items[0]}, out.writer());
    //space.info.id -= 1;
    try out.endMessage();
    const size = out.haveMessage();
    if (size * 2 > u.RB_SIZE) {
      std.debug.print("size of update {d} close to max {d}\n", .{size, u.RB_SIZE});
    }

    // copy serialized update to client mailboxes
    for (clients.items) |*client| {
      if (client.state == .ok) {
        _ = try client.mailbox.out.write(out.buf[0..out.write_idx]);
        client.mailbox.pumpOut() catch {
          std.debug.print("client {d} update pumpOut error\n", .{client.player.id});
          client.state = .leaving;
          continue;
        };
      }
    }

    // send space to any new clients or all if the space changed
    for (clients.items) |*client| {
      if (client.state == .waiting_for_space) {
        try client.mailbox.out.startMessage();
        try space.serialize(client.mailbox.out.writer());
        try client.mailbox.out.endMessage();
        const space_size = client.mailbox.out.haveMessage();
        if (space_size * 2 > u.RB_SIZE) {
          std.debug.print("size of serialized space {d} close to max {d}\n", .{space_size, u.RB_SIZE});
        }
        client.mailbox.pumpOut() catch {
          std.debug.print("client {d} newspace pumpOut error\n", .{client.player.id});
          client.state = .leaving;
          continue;
        };

        client.state = .ok;
      }
    }

    if (sig_int) {
      std.debug.print("server shutting down (got sigint)\n", .{});
      break;
    }

    // sleep
    const sleep_ms = previous_physics_time + u.TICK - std.time.milliTimestamp();
    if (sleep_ms > 0) {
      //std.debug.print("server sleeping {d}\n", .{sleep_ms});
      std.time.sleep(@intCast(u64, sleep_ms * std.time.ns_per_ms));
    }
    else {
      std.debug.print("server skipping {d}\n", .{sleep_ms});
    }
  }
}
