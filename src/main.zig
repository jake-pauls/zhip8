const std = @import("std");

/// Representation for an opcode processed by the CHIP-8 system.
/// TODO: Might be more useful to keep bits separate.
const Opcode = struct { upper_bits: u8, lower_bits: u8, value: u16 };

pub fn main() !void {
    const rom_file_path = "data/ROM/IBM Logo.ch8";
    // const rom_file_path = "data/ROM/Tetris [Fran Dachille, 1991].ch8";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const read_buffer = try std.fs.cwd().readFileAlloc(allocator, rom_file_path, std.math.maxInt(u32));
    defer allocator.free(read_buffer);

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
        decode(Opcode{ .upper_bits = upper_bits, .lower_bits = lower_bits, .value = value });
    }
}

fn decode(opcode: Opcode) void {
    const str = switch (opcode.value) {
        0x00E0 => "clear",
        else => "don't know",
    };

    std.debug.print("{X:0>4} - {s}\n", .{ opcode.value, str });
}
