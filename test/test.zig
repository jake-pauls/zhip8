const std = @import("std");
const testing = std.testing;

fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "logic" {
    try testing.expect(add(3, 7) == 10);
}

test "reason" {
    var list: std.ArrayList(i32) = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit();

    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
