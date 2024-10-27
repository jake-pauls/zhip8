const std = @import("std");
const sdl = @import("zsdl2");

/// Size of the memory. ~4K
const memory_size_in_bytes = 4096;

/// Stack size in bytes.
const stack_size_in_bytes = 64;
const bytes_per_slot_on_stack = 2;
const stack_size = stack_size_in_bytes / bytes_per_slot_on_stack;

/// Display width in pixels.
pub const display_width_in_pixels = 64;
/// Display height in pixels.
pub const display_height_in_pixels = 32;

/// RGBA constant for the color black.
pub const sdl_color_black = sdl.Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
/// RGBA constant for the color white.
pub const sdl_color_white = sdl.Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

/// The CHIP-8 system font.
pub const system_font = [80]u8{
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
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};

/// Representation for the hardware and components of a CHIP-8 system.
pub const Hardware = struct {
    memory: [memory_size_in_bytes]u8 = .{0} ** memory_size_in_bytes,
    display: [display_height_in_pixels][display_width_in_pixels]u1 = .{.{0} ** display_width_in_pixels} ** display_height_in_pixels,
    PC: u16 = 0x200,
    I: u16 = 0,
    stack: [stack_size]u16 = .{0} ** stack_size, // 64B / 2B
    stack_pointer: u8 = 0,
    delay_timer: u8 = 0,
    sound_timer: u8 = 0,
    V: [16]u8 = .{0} ** 16,
    randomizer: std.Random,

    was_key_pressed_this_frame: bool = false,

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
        for (0..display_height_in_pixels) |i| {
            for (0..display_width_in_pixels) |j| {
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
