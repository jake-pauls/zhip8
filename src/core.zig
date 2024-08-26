const std = @import("std");

/// Size of the memory. ~4K
const memory_size = 4096;

/// Display width in pixels.
pub const display_width = 64;
/// Display height in pixels.
pub const display_height = 32;

/// Representation for the hardware and components of a CHIP-8 system.
pub const Hardware = struct {
    memory: [memory_size]u8 = .{0} ** memory_size,
    display: [display_height][display_width]u1 = .{.{0} ** display_width} ** display_height,
    PC: u16 = 0x200,
    I: u16 = 0,
    stack: ?[]u16 = null,
    delay_timer: u8 = 0,
    sound_timer: u8 = 0,
    V: [16]u8 = .{0} ** 16,

    /// Dumps the contents of the memory array into a `memory.zhip8.txt` file for debugging.
    pub fn printMemoryToFile(self: Hardware, allocator: std.mem.Allocator) !void {
        const file = try std.fs.cwd().createFile("memory.zhip8.txt", .{ .read = true });
        defer file.close();

        for (0..self.memory.len) |i| {
            // Display each code as only two hex digits (8 bits)
            const str = try std.fmt.allocPrint(allocator, "{d}: {X:0>2}\n", .{ i, self.memory[i] });
            defer allocator.free(str);
            try file.writeAll(str);
        }
    }

    /// Dumps the contents fo the display array into a `display.zhip8.txt` file for debugging.
    pub fn printDisplayToFile(self: Hardware, allocator: std.mem.Allocator) !void {
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
pub const Opcode = struct { one: u8, two: u8, three: u8, four: u8, value: u16 };
