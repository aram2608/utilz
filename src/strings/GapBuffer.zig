const std = @import("std");

pub const GapBuffer = struct {
    gpa: std.mem.Allocator,
    capacity: usize,
    buffer: []u8,
    start: usize,
    end: usize,

    pub fn init(gpa: std.mem.Allocator, gap_size: usize) !GapBuffer {
        if (gap_size == 0) @panic("`gap_size` must be larger than 0");
        const buff_size = gap_size *| 2;
        return .{
            .gpa = gpa,
            .buffer = try gpa.alloc(u8, buff_size),
            .start = 0,
            .end = buff_size,
            .capacity = buff_size,
        };
    }

    pub fn deinit(self: *GapBuffer) void {
        self.gpa.free(self.allocatedSlice());
    }

    pub fn insert(self: *GapBuffer, char: u8) !void {
        if (self.start == self.end) try self.ensureGap();
        self.buffer[self.start] = char;
        self.start += 1;
    }

    pub fn delete(self: *GapBuffer) void {
        if (self.start == 0) return;
        self.start -= 1;
    }

    pub fn moveCursor(self: *GapBuffer, position: usize) void {
        if (position == self.start) return;

        const text_len = self.start + (self.capacity - self.end);
        if (position > text_len) return;

        if (position < self.start) {
            const delta = self.start - position;
            std.mem.copyBackwards(
                u8,
                self.buffer[self.end - delta .. self.end],
                self.buffer[position..self.start],
            );
            self.end -= delta;
            self.start = position;
        } else {
            const delta = position - self.start;
            std.mem.copyForwards(
                u8,
                self.buffer[self.start .. self.start + delta],
                self.buffer[self.end .. self.end + delta],
            );
            self.start += delta;
            self.end += delta;
        }
    }

    pub fn ensureGap(self: *GapBuffer) !void {
        const old_cap = self.buffer.len;
        const right_len = old_cap - self.end;
        const new_cap = growCapacity(old_cap);

        const old_memory = self.allocatedSlice();
        if (self.gpa.remap(old_memory, new_cap)) |new_memory| {
            std.mem.copyBackwards(
                u8,
                new_memory[new_cap - right_len ..],
                new_memory[self.end .. self.end + right_len],
            );
            self.buffer = new_memory;
            self.end = new_cap - right_len;
            self.capacity = new_cap;
        } else {
            const new_memory = try self.gpa.alloc(u8, new_cap);
            @memcpy(new_memory[0..self.start], self.buffer[0..self.start]);
            @memcpy(new_memory[new_cap - right_len ..], self.buffer[self.end..]);
            self.gpa.free(old_memory);
            self.buffer = new_memory;
            self.end = new_cap - right_len;
            self.capacity = new_cap;
        }
    }

    pub fn toString(self: *GapBuffer, gpa: std.mem.Allocator) ![]u8 {
        const right_len = self.capacity - self.end;
        const total_len = self.start + right_len;
        const string = try gpa.alloc(u8, total_len);
        @memcpy(string[0..self.start], self.buffer[0..self.start]);
        @memcpy(string[self.start..], self.buffer[self.end..]);
        return string;
    }

    fn allocatedSlice(self: *GapBuffer) []u8 {
        return self.buffer.ptr[0..self.capacity];
    }

    fn growCapacity(minimum: usize) usize {
        const init_capacity: comptime_int = @max(1, std.atomic.cache_line / @sizeOf(u8));
        return minimum +| (minimum / 2 + init_capacity);
    }
};

test "GapBuffer: insertion" {
    var buffer = try GapBuffer.init(std.testing.allocator, 50);
    defer buffer.deinit();

    try buffer.insert('h');
    try buffer.insert('i');
    const s = try buffer.toString(std.testing.allocator);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("hi", s);
}

test "GapBuffer: delete" {
    var buffer = try GapBuffer.init(std.testing.allocator, 50);
    defer buffer.deinit();

    try buffer.insert('h');
    try buffer.insert('i');
    buffer.delete();
    const s = try buffer.toString(std.testing.allocator);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("h", s);
}

test "GapBuffer: delete at start is no-op" {
    var buffer = try GapBuffer.init(std.testing.allocator, 50);
    defer buffer.deinit();

    buffer.delete();
    try std.testing.expectEqual(@as(usize, 0), buffer.start);
}

test "GapBuffer: moveCursor left" {
    var buffer = try GapBuffer.init(std.testing.allocator, 50);
    defer buffer.deinit();

    try buffer.insert('a');
    try buffer.insert('b');
    try buffer.insert('c');
    buffer.moveCursor(1);
    try buffer.insert('X');
    const s = try buffer.toString(std.testing.allocator);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("aXbc", s);
}

test "GapBuffer: moveCursor right" {
    var buffer = try GapBuffer.init(std.testing.allocator, 50);
    defer buffer.deinit();

    try buffer.insert('a');
    try buffer.insert('b');
    buffer.moveCursor(0);
    buffer.moveCursor(2);
    try buffer.insert('c');
    const s = try buffer.toString(std.testing.allocator);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("abc", s);
}

test "GapBuffer: moveCursor overlap (delta > gap size)" {
    var buffer = try GapBuffer.init(std.testing.allocator, 2);
    defer buffer.deinit();

    try buffer.insert('a');
    try buffer.insert('b');
    try buffer.insert('c');
    buffer.moveCursor(0);
    try buffer.insert('X');
    const s = try buffer.toString(std.testing.allocator);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("Xabc", s);
}

test "GapBuffer: moveCursor same position is no-op" {
    var buffer = try GapBuffer.init(std.testing.allocator, 50);
    defer buffer.deinit();

    try buffer.insert('a');
    const start_before = buffer.start;
    buffer.moveCursor(buffer.start);
    try std.testing.expectEqual(start_before, buffer.start);
}

test "GapBuffer: moveCursor out of bounds is no-op" {
    var buffer = try GapBuffer.init(std.testing.allocator, 50);
    defer buffer.deinit();

    try buffer.insert('a');
    const start_before = buffer.start;
    buffer.moveCursor(999);
    try std.testing.expectEqual(start_before, buffer.start);
}

test "GapBuffer: ensureGap on full buffer" {
    var buffer = try GapBuffer.init(std.testing.allocator, 1);
    defer buffer.deinit();

    try buffer.insert('a');
    try buffer.insert('b');
    try buffer.insert('c');
    const s = try buffer.toString(std.testing.allocator);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("abc", s);
}
