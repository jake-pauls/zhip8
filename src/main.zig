const std = @import("std");
const sdl = @import("zsdl2");

/// Size of the memory. ~4K
const memory_size = 4096;

/// Display width in pixels.
const display_width = 64;
/// Display height in pixels.
const display_height = 32;

/// Representation for the hardware and components of a CHIP-8 system.
const Hardware = struct {
    memory: [memory_size]u8 = .{0} ** memory_size,
    display: [display_height][display_width]u1 = .{.{0} ** display_width} ** display_height,
    PC: u16 = 0x200,
    I: u16 = 0,
    stack: ?[]u16 = null,
    delay_timer: u8 = 0,
    sound_timer: u8 = 0,
    V: [16]u8 = .{0} ** 16,

    /// Dumps the contents of the memory array into a `memory.zhip8.txt` file for debugging.
    fn printMemoryToFile(self: Hardware, allocator: std.mem.Allocator) !void {
        const file = try std.fs.cwd().createFile("memory.zhip8.txt", .{ .read = true });
        defer file.close();

        for (0..self.memory.len) |i| {
            // Display each code as only two hex digits (8 bits)
            const str = try std.fmt.allocPrint(allocator, "{d}: {X:0>2}\n", .{i, self.memory[i]});
            defer allocator.free(str);
            try file.writeAll(str);
        }
    }

    /// Dumps the contents fo the display array into a `display.zhip8.txt` file for debugging.
    fn printDisplayToFile(self: Hardware, allocator: std.mem.Allocator) !void {
        const file = try std.fs.cwd().createFile("display.zhip8.txt", .{ .read = true });
        defer file.close();

        // TODO: This is pretty inefficient, find a better way to alloc/write strings to files dynamically in Zig.
        for (0..display_height) |i| {
            for (0..display_width) |j| {
                const pixel = self.display[i][j];
                const str = try std.fmt.allocPrint(allocator, "{d}", .{pixel});
                defer allocator.free(str);
                try file.writeAll(str);
            }
            const str = try std.fmt.allocPrint(allocator, "\n", .{});
            defer allocator.free(str);
            try file.writeAll(str);
        }
    }
};

/// Representation for an opcode processed by the CHIP-8 system.
///
/// Each opcode contains four bytes to represent each digit used in a CHIP-8 opcode,
/// and 2 bytes to represent the cumuluative opcode with all bits together. These bits
/// are ordered from most significant (starting with one) to least significant (four).
const Opcode = struct { one: u8, two: u8, three: u8, four: u8, value: u16 };

const system_font = [80]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80  // F
};

pub fn main() !void {
    try run();

    try sdl.init(.{ .audio = true, .video = true });
    defer sdl.quit();

    const window = try sdl.Window.create(
        "zig-gamedev-window",
        sdl.Window.pos_undefined,
        sdl.Window.pos_undefined,
        600,
        600,
        .{ .opengl = true, .allow_highdpi = true },
    );

    var timer: std.time.Timer = try std.time.Timer.start();
    while (timer.read() != (std.time.ns_per_s * 5)) {
        continue;
    }

    defer window.destroy();
}

pub fn run() !void {
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Initialize the hardware
    var hardware = Hardware {};

    // Read a ROM from disk for loading into the emulator
    // NOTE: Program should be loaded into memory at address 0x200
    const rom_file_path = "data/ROM/IBM Logo.ch8";
    const read_buffer: []u8 = try std.fs.cwd().readFileAlloc(allocator, rom_file_path, std.math.maxInt(u32));
    defer allocator.free(read_buffer);
    for (0..read_buffer.len) |i| {
        hardware.memory[0x200 + i] = read_buffer[i];
    }

    // Load the system font into memory
    for (0..system_font.len) |i| {
        hardware.memory[0x050 + i] = system_font[i];
    }

    // Calculate the number of seconds per instruction
    const time_per_instruction_s: f32 = @as(f32, 1) / 700;
    // ~1.4 ms ~= ~1428571.40000 ns
    const time_per_instruction_ns: u64 = @intFromFloat(time_per_instruction_s * @as(f32, @floatFromInt(std.time.ns_per_s)));
    var in_a = try std.time.Instant.now();
    var in_b = try std.time.Instant.now();

    // Start the processing loop
    var i: u8 = 0;
    while (true) : (i += 1) {
        // Attempt at writing a timer to control the frequency of instructions per second.
        in_a = try std.time.Instant.now();
        const work_time = in_a.since(in_b);
        if (work_time < time_per_instruction_ns) {
            const delta_ns = time_per_instruction_ns - work_time;
            std.time.sleep(delta_ns);
        }
        in_b = try std.time.Instant.now();

        const op = fetch(&hardware);
        execute(&hardware, &op);

        if (i == 50) {
            break;
        }
    }

    try hardware.printDisplayToFile(allocator);
}

fn fetch(hardware: *Hardware) Opcode {
    const upper_instruction_bits = hardware.memory[hardware.PC];
    const lower_instruction_bits = hardware.memory[hardware.PC+1];
    hardware.PC += 2;

    // Create a 16-bit integer from both 8-bit ints.
    // ----------------------------------------------------
    // 1001 0010 - A2
    // 0101 0111 - 57
    // ----------------------------------------------------
    // 0000 0000 0101 0111 - lower_bits
    // 1001 0010 0000 0000 - upper_bits << 8
    // 1001 0010 0101 0111 - lower_bits | (upper_bits << 8)

    const value: u16 = lower_instruction_bits | @as(u16, upper_instruction_bits) << 8;

    // Create a 4-bit integer from 8-bit ints.
    // ----------------------------------------------------
    // 1001 0010 - A2
    // ----------------------------------------------------
    // 1001 0010
    // 0000 1111 - 0x0F
    // 0000 0010 - lower

    const one = upper_instruction_bits >> 4;
    const two = upper_instruction_bits & 0x0F;

    // 1110 - 0x0E
    const three = lower_instruction_bits >> 4;
    const four = lower_instruction_bits & 0x0F;

    return Opcode{ .one = one, .two = two, .three = three, .four = four, .value = value };
}

fn execute(hardware: *Hardware, op: *const Opcode) void {
    switch (op.one) {
        0x0 => clear(hardware),
        0x1 => jump(hardware, op),
        0x6 => setVX(hardware, op),
        0x7 => addVX(hardware, op),
        0xA => setI(hardware, op),
        0xD => draw(hardware, op),
        else => unreachable,
    }
}

//
// Operations
//

/// Clears the screen.
///
/// Example:
///     00E0 - Clear the screen
fn clear(hardware: *Hardware) void {
    hardware.display = .{.{0} ** 64} ** 32;
}

/// Constructs the address of the jump using the last three bits of the opcode
/// and directly sets the program counter to the corresponding address.
///
/// Example:
///     1NNN - Jump to address NNN
///     1228 - Jump to address 0x228
fn jump(hardware: *Hardware, op: *const Opcode) void {
    const h: u12 = @as(u12, op.two) << 8;
    const t: u12 = @as(u12, op.three) << 4;
    const o: u12 = @as(u12, op.four);

    const address = h | t | o;
    hardware.PC = address;
}

/// Sets the value of the register indicated in the second bit of the opcode
/// to the value constructed by the last two bits of the opcode.
///
/// Example:
///     6XNN - Store the number NN in register VX
///     600C - Store the number 0x0C in register V0
fn setVX(hardware: *Hardware, op: *const Opcode) void {
    const register: u8 = op.two;
    const t: u8 = op.three << 4;
    const o: u8 = op.four;

    const value: u8 = t | o;
    hardware.V[register] = value;
}

/// Adds the value constructed by the last two bits of the opode to the
/// current value of the register indicated in the second bit of the opcode.
///
/// Example:
///     7XNN - Add the value NN to register VX
///     7008 - Add the value 0x08 to register VX
fn addVX(hardware: *Hardware, op: *const Opcode) void {
    const register: u8 = op.two;
    const t: u8 = op.three << 4;
    const o: u8 = op.four;

    const value: u8 = t | o;
    hardware.V[register] += value;
}

/// Sets the value of the index register (I) to the address constructed
/// from the last three bits of the opcode.
///
/// Example:
///     ANNN - Store memory address NNN in register I
///     A239 - Store memory address 0x239 in register I
fn setI(hardware: *Hardware, op: *const Opcode) void {
    const h: u12 = @as(u12, op.two) << 8;
    const t: u12 = @as(u12, op.three) << 4;
    const o: u12 = @as(u12, op.four);

    const address = h | t | o;
    hardware.I = address;
}

/// Draws a sprite at the position indicated by the values contained in the registers
/// of the second and third bits of the opcode with N bytes of data represented by the fourth
/// bit of the opcode starting at the address stored in I.
///
/// Example:
///     DXYN - Draw a sprite at position VX,VY with N bytes of data starting at the address stored in I
///     D01F - Draw a sprite at position V0,V1 with 0xF bytes of data starting at the address stored in I
fn draw(hardware: *Hardware, op: *const Opcode) void {
    const x = hardware.V[op.two] & 63;
    const y = hardware.V[op.three] & 31;
    const n = op.four;

    // Reset the flag register to 0 before drawing.
    // If any pixels are turned off by this draw operation the flag register should switch to 1.
    hardware.V[0xF] = 0;

    // Sprite data is defined in memory, with each register eight bits from the starting position
    //  e.g., one "opcode" is two lines @ 8 bytes per line
    //
    // Example (IBM Logo):
    //  sprite for the "I" starts at 554 in memory and ends at 568
    //
    // hardware.display[y][x] = starting point for sprite drawing

    std.debug.print("Drawing a sprite at ({d}, {d}) using {d} bytes of data starting from address {X}\n", .{ x, y, n, hardware.I });

    for (0..n) |i| {
        const sprite_row: u8 = hardware.memory[hardware.I+i];

        //std.debug.print("sprite_row: {b:0>8}\n", .{sprite_row});
        //std.debug.print("actual:     ", .{});

        // Each instruction is 8 bytes
        var j: u3 = 7;
        while (j >= 0) {
            //std.debug.print("\tpixel: {b:0>8}\n", .{pixel});
            //std.debug.print("\tvisiting (x,y) => ({d},{d})\n", .{ x+j, y+i });

            const sprite_bit: u1 = @truncate(sprite_row >> j);
            const xor = sprite_bit ^ hardware.display[y+i][x+j];

            // std.debug.print("\txor = {b:0>1} ^ {b:0>1}\n", .{ sprite_bit, hardware.display[y+i][x+j] });
            // std.debug.print("{b:0>1}", .{xor});

            hardware.display[y+i][x+j] = xor;

            if (j == 0) {
                break;
            }
            j -= 1;
        }
        //std.debug.print("\n", .{});
    }
}
