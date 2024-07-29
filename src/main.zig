const std = @import("std");

pub fn main() !void {
    const file_path = "data/ROM/IBM Logo.ch8";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const read_buffer = try std.fs.cwd().readFileAlloc(allocator, file_path, std.math.maxInt(u8));
    defer allocator.free(read_buffer);

    std.debug.print("reading {s}", .{file_path});
    for (0..read_buffer.len) |i| {
        std.debug.print("{d}: {X:0>4}\n", .{i, read_buffer[i]});
    }
}
