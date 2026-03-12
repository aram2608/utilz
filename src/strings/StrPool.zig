const std = @import("std");

/// `StrPool` is a string interner for externally owned slices.
/// Memory needs to be managed carefully so the interner does not return a
/// dangling pointer.
const StrPool = @This();

gpa: std.mem.Allocator,
pool: std.StringArrayHashMap(void),

/// Type safe ID for looking into the `pool` of Strings.
/// Has a limit of 4,294,967,295 so its probably fine for most use cases.
pub const StringID = enum(u32) {
    empty = std.math.maxInt(u32),
    _,
};

pub fn init(gpa: std.mem.Allocator) StrPool {
    return .{
        .gpa = gpa,
        .pool = std.StringArrayHashMap(void).init(gpa),
    };
}

pub fn deinit(self: *StrPool) void {
    self.pool.deinit();
}

pub fn intern(self: *StrPool, string: []const u8) !StringID {
    if (string.len == 0) return .empty;

    const gop = try self.pool.getOrPut(string);
    return @enumFromInt(gop.index);
}

pub fn lookUp(self: *StrPool, id: StringID) []const u8 {
    if (id == .empty) return "";
    return self.pool.keys()[@intFromEnum(id)];
}

test "test interning" {
    var interner = init(std.testing.allocator);
    defer interner.deinit();

    const id = try interner.intern("hello");
    const lookup = interner.lookUp(id);

    const id_2 = try interner.intern("hello");
    const lookup_2 = interner.lookUp(id_2);

    try std.testing.expectEqualSlices(u8, "hello", lookup);
    try std.testing.expectEqualSlices(u8, lookup, lookup_2);
    try std.testing.expectEqual(id, id_2);
}
