const std = @import("std");

/// Representation for the hardware and components of a CHIP-8 system.
const Hardware = struct {
    memory: [4096]u8 = .{0} ** 4096,
    display: [32][64]u8 = .{.{0} ** 64} ** 32,
    PC: u8 = 0,
    I: u16 = 0,
    stack: ?[]u16 = null,
    delay_timer: u8 = 0,
    sound_timer: u8 = 0,
    registers: [16]u8 = .{0} ** 16,

    fn printMemoryToFile(self: Hardware, allocator: std.mem.Allocator) !void {
        const file = try std.fs.cwd().createFile("memory.zhip8.txt", .{ .read = true });
        defer file.close();

        for (0..4096) |i| {
            const str = try std.fmt.allocPrint(allocator, "{d}: {X:0>4}\n", .{i, self.memory[i]});
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

const rom_file_path = "data/ROM/IBM Logo.ch8";
// const rom_file_path = "data/ROM/Tetris [Fran Dachille, 1991].ch8";

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
    const read_buffer: []u8 = try std.fs.cwd().readFileAlloc(allocator, rom_file_path, std.math.maxInt(u32));
    defer allocator.free(read_buffer);
    for (0..read_buffer.len) |i| {
        hardware.memory[0x200 + i] = read_buffer[i];
    }

    // Load the system font into memory
    for (0..system_font.len) |i| {
        hardware.memory[0x050 + i] = system_font[i];
    }

    try hardware.printMemoryToFile(allocator);
}

/// Sample function for testing some bit shifting operations related to unwrapping opcodes.
fn opcodeProcessing(read_buffer: []u8) void {
    var i: u8 = 0;
    while (i < read_buffer.len) : (i += 2) {
        const upper_bits = read_buffer[i];
        const lower_bits = read_buffer[i + 1];

        // Create a 16-bit integer from both 8-bit ints.
        // ----------------------------------------------------
        // 1001 0010 - A2
        // 0101 0111 - 57
        // ----------------------------------------------------
        // 0000 0000 0101 0111 - lower_bits
        // 1001 0010 0000 0000 - upper_bits << 8
        // 1001 0010 0101 0111 - lower_bits | (upper_bits << 8)

        const value: u16 = lower_bits | @as(u16, upper_bits) << 8;

        // Create a 4-bit integer from 8-bit ints.
        // ----------------------------------------------------
        // 1001 0010 - A2
        // ----------------------------------------------------
        // 1001 0010
        // 0000 1111 - 0x0F
        // 0000 0010 - lower

        const one = upper_bits >> 4;
        const two = upper_bits & 0x0F;

        // 1110 - 0x0E
        const three = lower_bits >> 4;
        const four = lower_bits & 0x0F;

        std.debug.print("{X} {X} {X} {X}\n", .{ one, two, three, four });
        const opcode = Opcode{ .one = one, .two = two, .three = three, .four = four, .value = value };
        std.debug.print("{X:0>4}\n", .{ opcode.value });

        switch (opcode.one) {
            0 => {
            },
            1 => {
                std.debug.print("this is a jump\n", .{});
            },
            else => {}
        }
    }
}
