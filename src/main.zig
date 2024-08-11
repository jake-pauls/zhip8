const std = @import("std");

/// Representation for the hardware and components of a CHIP-8 system.
const Hardware = struct {
    memory: [4096]u8 = .{0} ** 4096,
    display: [64][128]u8 = .{.{0} ** 128} ** 64,
    PC: u8 = 0,
    I: u16 = 0,
    stack: ?[]u16 = null,
    delay_timer: u8 = 0,
    sound_timer: u8 = 0,
    registers: [16]u8 = .{0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xA, 0xB, 0xC, 0xD, 0xE, 0xF},

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

pub fn main() !void {
    const rom_file_path = "data/ROM/IBM Logo.ch8";
    // const rom_file_path = "data/ROM/Tetris [Fran Dachille, 1991].ch8";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const read_buffer: []u8 = try std.fs.cwd().readFileAlloc(allocator, rom_file_path, std.math.maxInt(u32));
    defer allocator.free(read_buffer);

    var hardware = Hardware {};

    // NOTE: Program should be loaded into memory at address 0x200
    for (0..read_buffer.len) |i| {
        hardware.memory[0x200 + i] = read_buffer[i];
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
