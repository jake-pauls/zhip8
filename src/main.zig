const std = @import("std");

/// Representation for the hardware and components of a CHIP-8 system.
const Hardware = struct {
    memory: [4096]u8 = .{0} ** 4096,
    display: [32][64]u8 = .{.{0} ** 64} ** 32,
    PC: u16 = 0x200,
    I: u16 = 0,
    stack: ?[]u16 = null,
    delay_timer: u8 = 0,
    sound_timer: u8 = 0,
    registers: [16]u8 = .{0} ** 16,

    fn printMemoryToFile(self: Hardware, allocator: std.mem.Allocator) !void {
        const file = try std.fs.cwd().createFile("memory.zhip8.txt", .{ .read = true });
        defer file.close();

        for (0..4096) |i| {
            // Display each code as only two hex digits (8 bits)
            const str = try std.fmt.allocPrint(allocator, "{d}: {X:0>2}\n", .{i, self.memory[i]});
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
    while (true) {

        // Attempt at writing a timer to control the frequency of instructions per second.
        in_a = try std.time.Instant.now();
        const work_time = in_a.since(in_b);
        if (work_time < time_per_instruction_ns) {
            const delta_ns = time_per_instruction_ns - work_time;
            std.time.sleep(delta_ns);
        }
        in_b = try std.time.Instant.now();

        const op = fetch(&hardware);
        std.debug.print("{X:0>4}\n", .{ op.value });
        execute(&hardware, &op);
    }
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
        0x0 => clear(),
        0x1 => jump(hardware, op),
        0x6 => std.debug.print("set register VX\n", .{}),
        0x7 => std.debug.print("add value to register\n", .{}),
        0xA => std.debug.print("set index register\n", .{}),
        0xD => std.debug.print("display/draw\n", .{}),
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
fn clear() void {
    std.debug.print("todo: Clear the screen, setup graphics!\n", .{});
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

/// Constructs the number
///
/// Example:
///     6XNN - Store the number NN in register VX
///     6212 - Store the number 0x12 in register V2
fn setVX(_: *Hardware, _: *const Opcode) void {

}
