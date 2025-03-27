const std = @import("std");
const rl = @import("raylib");

const MEMORY_SIZE = 0x1000008;
const KEY_MEM_SIZE = 16;
const VIDEO_BUFF_SIZE = 256 * 256;
const SCREEN_WIDTH = 256;
const SCREEN_HEIGHT = 256;
const FPS = 60;

const COLOR_STEP = 0x33;
const AUDIO_SAMPLE_RATE = 15360;
const AUDIO_SIZE = 256;
const AUDIO_CHANNELS = 1;

var memory: [MEMORY_SIZE]u8 = undefined;
var keyMem: [KEY_MEM_SIZE]u8 = undefined;

const color_map = initColorMap();

fn initColorMap() [256]rl.Color {
    var c: [256]rl.Color = undefined;
    for (0..6) |r| for (0..6) |g| for (0..6) |b| {
        c[r * 36 + g * 6 + b] = rl.Color.init(r * COLOR_STEP, g * COLOR_STEP, b * COLOR_STEP, 255);
    };
    for (216..256) |i| {
        c[i] = rl.Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
    }
    return c;
}

fn load(buff: []const u8) void {
    @memset(&memory, 0);
    const len = @min(buff.len, std.math.maxInt(u24));
    @memcpy(memory[0..len], buff[0..len]);
}

fn update() void {
    const pc_start = std.mem.readInt(u24, memory[2..5], .big);
    var pc: usize = pc_start;

    for (0..65536) |_| {
        // if (pc + 9 > MEMORY_SIZE) break;

        const a_addr = std.mem.readInt(u24, @ptrCast(memory[pc .. pc + 3]), .big);
        const b_addr = std.mem.readInt(u24, @ptrCast(memory[pc + 3 .. pc + 6]), .big);
        const next_pc = std.mem.readInt(u24, @ptrCast(memory[pc + 6 .. pc + 9]), .big);

        if (a_addr < MEMORY_SIZE and b_addr < MEMORY_SIZE) {
            memory[b_addr] = memory[a_addr];
        }

        pc = next_pc;
    }
}

fn updateKeys() void {
    @memset(&keyMem, 0);

    if (rl.isKeyDown(rl.KeyboardKey.zero)) keyMem[0x01] |= 0x01;
    if (rl.isKeyDown(rl.KeyboardKey.one)) keyMem[0x01] |= 0x02;
    if (rl.isKeyDown(rl.KeyboardKey.two)) keyMem[0x01] |= 0x04;
    if (rl.isKeyDown(rl.KeyboardKey.three)) keyMem[0x01] |= 0x08;

    if (rl.isKeyDown(rl.KeyboardKey.four)) keyMem[0x02] |= 0x01;
    if (rl.isKeyDown(rl.KeyboardKey.five)) keyMem[0x02] |= 0x02;
    if (rl.isKeyDown(rl.KeyboardKey.six)) keyMem[0x02] |= 0x04;
    if (rl.isKeyDown(rl.KeyboardKey.seven)) keyMem[0x02] |= 0x08;

    if (rl.isKeyDown(rl.KeyboardKey.eight)) keyMem[0x03] |= 0x01;
    if (rl.isKeyDown(rl.KeyboardKey.nine)) keyMem[0x03] |= 0x02;
    if (rl.isKeyDown(rl.KeyboardKey.a)) keyMem[0x03] |= 0x04;
    if (rl.isKeyDown(rl.KeyboardKey.b)) keyMem[0x03] |= 0x08;

    if (rl.isKeyDown(rl.KeyboardKey.c)) keyMem[0x04] |= 0x01;
    if (rl.isKeyDown(rl.KeyboardKey.d)) keyMem[0x04] |= 0x02;
    if (rl.isKeyDown(rl.KeyboardKey.e)) keyMem[0x04] |= 0x04;
    if (rl.isKeyDown(rl.KeyboardKey.f)) keyMem[0x04] |= 0x08;

    memory[0] = 0;
    memory[1] = 0;

    // According to BytePusher spec, memory[0] is the high byte and memory[1] is the low byte
    memory[0] = keyMem[0x03] | (keyMem[0x04] << 4); // High byte: IJKL MNOP
    memory[1] = keyMem[0x01] | (keyMem[0x02] << 4); // Low byte: ABCD EFGH
}

fn updateAudio(stream: rl.AudioStream) void {
    if (!rl.isAudioStreamProcessed(stream)) return;

    const audio_addr = @as(u24, std.mem.readInt(u16, memory[6..8], .big)) << 8;

    if (audio_addr == 0 or audio_addr + AUDIO_SIZE > MEMORY_SIZE) return;

    var audioBuffer: [AUDIO_SIZE]i8 = undefined;
    for (0..AUDIO_SIZE) |i| {
        audioBuffer[i] = @bitCast(memory[audio_addr + i] ^ 0x80);
    }

    rl.updateAudioStream(stream, &audioBuffer, AUDIO_SIZE);
}

fn draw() void {
    rl.beginDrawing();
    defer rl.endDrawing();

    rl.clearBackground(rl.Color.black);

    const pixels_addr = @as(u24, memory[5]) << 16;

    if (pixels_addr + VIDEO_BUFF_SIZE > MEMORY_SIZE) {
        rl.drawText("Display buffer out of bounds", 10, 10, 20, rl.Color.red);
        return;
    }

    for (0..VIDEO_BUFF_SIZE) |i| {
        const color_index = memory[pixels_addr + i];
        const y = @as(i32, @intCast(i / SCREEN_WIDTH));
        const x = @as(i32, @intCast(i % SCREEN_WIDTH));
        rl.drawPixel(x, y, color_map[color_index]);
    }

    var debug_text: [64:0]u8 = undefined;
    _ = std.fmt.bufPrintZ(&debug_text, "PC: 0x{X:0>6}", .{std.mem.readInt(u24, memory[2..5], .big)}) catch "";
    rl.drawText(&debug_text, 10, 10, 10, rl.Color.white);
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
    defer std.heap.page_allocator.free(rom);

    std.log.info("Loading ROM: {s} ({} bytes)", .{ rom_path, rom.len });
    load(rom);
    // debugState();

    rl.initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "BytePusher Zig");
    defer rl.closeWindow();

    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    const audioStream = try rl.loadAudioStream(AUDIO_SAMPLE_RATE, 8, AUDIO_CHANNELS);
    defer rl.unloadAudioStream(audioStream);
    rl.playAudioStream(audioStream);

    rl.setTargetFPS(FPS);

    while (!rl.windowShouldClose()) {
        updateKeys();
        update();
        updateAudio(audioStream);
        draw();
    }
}
