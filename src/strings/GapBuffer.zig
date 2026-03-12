const std = @import("std");

pub const GapBuffer = struct {
    gpa: std.mem.Allocator,
    capacity: usize,
    buffer: []u8,
    start: usize,
    end: usize,

    pub fn init(gpa: std.mem.Allocator, gap_size: usize) !GapBuffer {
        const buff_size = gap_size * 2;
        return .{
            .gpa = gpa,
            .buffer = try gpa.alloc(u8, buff_size),
            .start = 0,
            .end = gap_size,
            .capacity = buff_size,
        };
    }

    pub fn deinit(self: *GapBuffer) void {
        self.gpa.free(self.allocatedSlice());
    }

    pub fn insert(self: *GapBuffer, char: u8) !void {
        if (self.start == self.end) try self.ensureGap(self.buffer.len * 2);
        self.start += 1;
        self.buffer[self.start - 1] = char;
    }

    pub fn delete(self: *GapBuffer) void {
        if (self.start == 0) return;
        self.start -= 1;
    }

    // TODO: Implement cursor movement logic
    pub fn moveCursor(self: *GapBuffer) void {
        _ = self;
    }

    pub fn ensureGap(self: *GapBuffer, minimum: usize) !void {
        const new_cap = growCapacity(minimum);

        // Reallocate memory.
        const old_memory = self.allocatedSlice();
        if (self.gpa.remap(old_memory, new_cap)) |new_memory| {
            self.buffer.ptr = new_memory.ptr;
            self.capacity = new_memory.len;
        } else {
            const new_memory = try self.gpa.alloc(u8, new_cap);
            const old_cap = self.buffer.len;
            @memcpy(new_memory[0..self.start], self.buffer[0..self.start]);
            @memcpy(new_memory[new_cap - (old_cap - self.end) ..], self.buffer[self.end..]);
            self.gpa.free(old_memory);
            self.buffer.ptr = new_memory.ptr;
            self.capacity = new_memory.len;
        }
    }

    pub fn toString(self: *GapBuffer, gpa: std.mem.Allocator) ![]u8 {
        const string = try gpa.alloc(u8, self.capacity);
        @memcpy(string[0..self.start], self.buffer[0..self.start]);
        @memcpy(string[self.start + 1 ..], self.buffer[self.end..]);
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

    try buffer.insert('g');
}
