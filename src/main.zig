const std = @import("std");
const rl = @import("raylib");
// const rom = @embedFile("./Palette Test.BytePusher");

const MEMORY_SIZE = 0x1000008;
const KEY_MEM_SIZE = 16;
const VIDEO_BUFF_SIZE = 256 * 256;
const SCREEN_WIDTH = 256;
const SCREEN_HEIGHT = 256;
const FPS = 60;

const COLOR_STEP = 0x33;
const COLOR_BLACK = rl.Color{ .r = 0, .g = 0, .b = 0, .a = 255 };

var memory: [MEMORY_SIZE]u8 = undefined;
var keyMem: [KEY_MEM_SIZE]u8 = undefined;
var videoBuff: [VIDEO_BUFF_SIZE]u8 = undefined;

const color_map = initColorMap();

fn initColorMap() [256]rl.Color {
    var c: [256]rl.Color = undefined;
    for (0..6) |r| for (0..6) |g| for (0..6) |b| {
        c[r * 36 + g * 6 + b] = rl.Color.init(r * COLOR_STEP, g * COLOR_STEP, b * COLOR_STEP, 255);
    };
    @memset(c[216..], COLOR_BLACK);
    return c;
}

fn load(buff: []const u8) void {
    @memset(&memory, 0);
    const len = @min(buff.len, std.math.maxInt(u24));
    @memcpy(memory[0..len], buff[0..len]);
}

fn update() void {
    var pc = std.mem.readInt(u24, memory[2 .. 2 + 3], .big);
    for (0..65536) |_| {
        const a = std.mem.readInt(u24, @ptrCast(memory[pc..]), .big);
        const b = std.mem.readInt(u24, @ptrCast(memory[pc + 3 ..]), .big);
        const c = std.mem.readInt(u24, @ptrCast(memory[pc + 6 ..]), .big);

        memory[b] = memory[a];
        pc = c;
    }
}

fn draw() void {
    rl.beginDrawing();
    defer rl.endDrawing();
    const pixels_addr = @as(u24, memory[5]) << 16;
    const pixels: *[VIDEO_BUFF_SIZE]u8 = @ptrCast(memory[pixels_addr..]);

    for (pixels, 0..VIDEO_BUFF_SIZE) |color_index, i| {
        const y = i / SCREEN_WIDTH;
        const x = i % SCREEN_WIDTH;
        rl.drawPixel(@intCast(x), @intCast(y), color_map[color_index]);
    }
}

fn parseArgs() ![]const u8 {
    const alloc = std.heap.page_allocator;
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    const exe = args.next().?;
    const rom_path = args.next() orelse {
        std.log.err("Error: ROM file path not provided", .{});
        std.log.err("Usage: {s} <rom_file>", .{exe});
        return error.InvalidArguments;
    };

    return rom_path;
}

fn readRom(rom_path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(rom_path, .{ .mode = .read_only });
    defer file.close();

    const file_size = try file.getEndPos();

    const allocator = std.heap.page_allocator;
    const rom = try allocator.alloc(u8, file_size);

    const bytes_read = try file.readAll(rom);
    if (bytes_read != file_size) {
        return error.IncompleteRead;
    }
    return rom;
}

pub fn main() anyerror!void {
    const rom_path = parseArgs() catch {
        std.process.exit(1);
    };

    const rom = readRom(rom_path) catch {
        std.process.exit(1);
    };

    std.log.info("Loading ROM: {s}", .{rom_path});

    load(rom);
    rl.initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Bytepusher Zig");
    defer rl.closeWindow();

    rl.setTargetFPS(FPS);

    while (!rl.windowShouldClose()) {
        update();
        draw();
    }
}
