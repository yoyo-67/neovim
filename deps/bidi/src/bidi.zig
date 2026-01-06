// bidi.zig - Test wrapper that imports the library
const std = @import("std");
const lib = @import("bidi_lib.zig");

// Re-export for tests
pub const bidi_test_connection = lib.bidi_test_connection;
pub const bidi_get_paragraph_direction = lib.bidi_get_paragraph_direction;
pub const bidi_is_hebrew = lib.bidi_is_hebrew;
pub const bidi_has_rtl = lib.bidi_has_rtl;
pub const bidi_process_line = lib.bidi_process_line;
pub const bidi_logical_to_visual = lib.bidi_logical_to_visual;
pub const bidi_visual_to_logical = lib.bidi_visual_to_logical;

// ============= Basic Tests =============

test "bidi_test_connection returns 42" {
    const result = bidi_test_connection();
    try std.testing.expectEqual(@as(i32, 42), result);
}

test "Hebrew letters detected as RTL" {
    try std.testing.expect(bidi_is_hebrew(0x05D0)); // aleph
    try std.testing.expect(bidi_is_hebrew(0x05D1)); // bet
    try std.testing.expect(bidi_is_hebrew(0x05EA)); // tav
}

test "English letters detected as LTR" {
    try std.testing.expect(!bidi_is_hebrew('A'));
    try std.testing.expect(!bidi_is_hebrew('z'));
}

// ============= Paragraph Direction Tests =============

test "paragraph direction - pure Hebrew" {
    // "שלום" (shalom)
    const text = [_]u32{ 0x05E9, 0x05DC, 0x05D5, 0x05DD };
    const direction = bidi_get_paragraph_direction(&text, text.len);
    try std.testing.expectEqual(@as(u8, 1), direction); // RTL
}

test "paragraph direction - pure English" {
    const text = [_]u32{ 'H', 'e', 'l', 'l', 'o' };
    const direction = bidi_get_paragraph_direction(&text, text.len);
    try std.testing.expectEqual(@as(u8, 0), direction); // LTR
}

test "paragraph direction - mixed starting with English" {
    // "Hello שלום"
    const text = [_]u32{ 'H', 'e', 'l', 'l', 'o', ' ', 0x05E9, 0x05DC, 0x05D5, 0x05DD };
    const direction = bidi_get_paragraph_direction(&text, text.len);
    try std.testing.expectEqual(@as(u8, 0), direction); // LTR (first strong is 'H')
}

test "paragraph direction - mixed starting with Hebrew" {
    // "שלום Hello"
    const text = [_]u32{ 0x05E9, 0x05DC, 0x05D5, 0x05DD, ' ', 'H', 'e', 'l', 'l', 'o' };
    const direction = bidi_get_paragraph_direction(&text, text.len);
    try std.testing.expectEqual(@as(u8, 1), direction); // RTL (first strong is shin)
}

test "paragraph direction - starts with number" {
    // "123 Hello"
    const text = [_]u32{ '1', '2', '3', ' ', 'H', 'e', 'l', 'l', 'o' };
    const direction = bidi_get_paragraph_direction(&text, text.len);
    try std.testing.expectEqual(@as(u8, 0), direction); // LTR (first strong is 'H')
}

test "paragraph direction - empty text" {
    const direction = bidi_get_paragraph_direction(undefined, 0);
    try std.testing.expectEqual(@as(u8, 0), direction); // Default LTR
}

// ============= Has RTL Tests =============

test "bidi_has_rtl - pure English" {
    const text = [_]u32{ 'H', 'e', 'l', 'l', 'o' };
    try std.testing.expect(!bidi_has_rtl(&text, text.len));
}

test "bidi_has_rtl - pure Hebrew" {
    const text = [_]u32{ 0x05E9, 0x05DC, 0x05D5, 0x05DD };
    try std.testing.expect(bidi_has_rtl(&text, text.len));
}

test "bidi_has_rtl - mixed" {
    const text = [_]u32{ 'H', 'e', 'l', 'l', 'o', ' ', 0x05E9 };
    try std.testing.expect(bidi_has_rtl(&text, text.len));
}

// ============= Full BiDi Processing Tests =============

test "bidi_process_line - pure LTR no reordering" {
    const text = [_]u32{ 'H', 'e', 'l', 'l', 'o' };
    var v2l: [5]i32 = undefined;
    var l2v: [5]i32 = undefined;
    var levels: [5]u8 = undefined;

    const para_dir = bidi_process_line(&text, text.len, &v2l, &l2v, &levels);

    try std.testing.expectEqual(@as(u8, 0), para_dir); // LTR

    // No reordering - identity mapping
    for (0..5) |i| {
        try std.testing.expectEqual(@as(i32, @intCast(i)), v2l[i]);
        try std.testing.expectEqual(@as(i32, @intCast(i)), l2v[i]);
    }
}

test "bidi_process_line - pure RTL reversal" {
    // "שלום" - should be reversed for display
    const text = [_]u32{ 0x05E9, 0x05DC, 0x05D5, 0x05DD }; // shin, lamed, vav, mem
    var v2l: [4]i32 = undefined;
    var l2v: [4]i32 = undefined;
    var levels: [4]u8 = undefined;

    const para_dir = bidi_process_line(&text, text.len, &v2l, &l2v, &levels);

    try std.testing.expectEqual(@as(u8, 1), para_dir); // RTL

    // Characters should be reversed: visual[0] = logical[3], etc
    try std.testing.expectEqual(@as(i32, 3), v2l[0]);
    try std.testing.expectEqual(@as(i32, 2), v2l[1]);
    try std.testing.expectEqual(@as(i32, 1), v2l[2]);
    try std.testing.expectEqual(@as(i32, 0), v2l[3]);
}

test "bidi_process_line - mixed LTR paragraph with RTL word" {
    // "Hello שלום World"
    // Logical: H e l l o   ש ל ו ם   W o r l d
    // Index:   0 1 2 3 4 5 6 7 8 9 10 11 12 13 14
    // Visual:  H e l l o   ם ו ל ש   W o r l d
    const text = [_]u32{
        'H', 'e', 'l', 'l', 'o', ' ', // 0-5
        0x05E9, 0x05DC, 0x05D5, 0x05DD, // 6-9 (shin lamed vav mem)
        ' ', 'W', 'o', 'r', 'l', 'd', // 10-15
    };
    var v2l: [16]i32 = undefined;
    var l2v: [16]i32 = undefined;
    var levels: [16]u8 = undefined;

    const para_dir = bidi_process_line(&text, text.len, &v2l, &l2v, &levels);

    try std.testing.expectEqual(@as(u8, 0), para_dir); // LTR paragraph

    // "Hello " stays in place (positions 0-5)
    try std.testing.expectEqual(@as(i32, 0), v2l[0]);
    try std.testing.expectEqual(@as(i32, 1), v2l[1]);
    try std.testing.expectEqual(@as(i32, 2), v2l[2]);
    try std.testing.expectEqual(@as(i32, 3), v2l[3]);
    try std.testing.expectEqual(@as(i32, 4), v2l[4]);
    try std.testing.expectEqual(@as(i32, 5), v2l[5]);

    // Hebrew word reversed (visual 6-9 maps to logical 9,8,7,6)
    try std.testing.expectEqual(@as(i32, 9), v2l[6]);
    try std.testing.expectEqual(@as(i32, 8), v2l[7]);
    try std.testing.expectEqual(@as(i32, 7), v2l[8]);
    try std.testing.expectEqual(@as(i32, 6), v2l[9]);

    // " World" stays in place (positions 10-15)
    try std.testing.expectEqual(@as(i32, 10), v2l[10]);
    try std.testing.expectEqual(@as(i32, 11), v2l[11]);
}

test "bidi_process_line - numbers stay LTR in RTL context" {
    // "שלום 123" - RTL paragraph, but 123 should stay as 123, not 321
    // Logical: ש ל ו ם   1 2 3
    // Index:   0 1 2 3 4 5 6 7
    const text = [_]u32{
        0x05E9, 0x05DC, 0x05D5, 0x05DD, // shin lamed vav mem
        ' ',
        '1', '2', '3',
    };
    var v2l: [8]i32 = undefined;
    var l2v: [8]i32 = undefined;
    var levels: [8]u8 = undefined;

    const para_dir = bidi_process_line(&text, text.len, &v2l, &l2v, &levels);

    try std.testing.expectEqual(@as(u8, 1), para_dir); // RTL paragraph

    // In RTL paragraph, display order is reversed
    // Numbers have level 2 (even), Hebrew has level 1 (odd)
    // Visual: 1 2 3   ם ו ל ש
    // The numbers should appear first (on the right in RTL display)
    // but within the number group, they stay as 123

    // Check that numbers appear in correct relative order (1, 2, 3 not 3, 2, 1)
    var num_positions: [3]i32 = undefined;
    var num_idx: usize = 0;
    for (0..8) |visual| {
        const logical: usize = @intCast(v2l[visual]);
        if (text[logical] >= '0' and text[logical] <= '9') {
            num_positions[num_idx] = v2l[visual];
            num_idx += 1;
        }
    }
    // Numbers should be in logical order 5, 6, 7 (1, 2, 3)
    try std.testing.expectEqual(@as(i32, 5), num_positions[0]);
    try std.testing.expectEqual(@as(i32, 6), num_positions[1]);
    try std.testing.expectEqual(@as(i32, 7), num_positions[2]);
}

// ============= Cursor Mapping Tests =============

test "cursor mapping - identity for pure LTR" {
    const text = [_]u32{ 'H', 'e', 'l', 'l', 'o' };
    var v2l: [5]i32 = undefined;
    var l2v: [5]i32 = undefined;
    var levels: [5]u8 = undefined;

    _ = bidi_process_line(&text, text.len, &v2l, &l2v, &levels);

    // Logical position 2 should map to visual position 2
    try std.testing.expectEqual(@as(i32, 2), bidi_logical_to_visual(&l2v, 5, 2));
    try std.testing.expectEqual(@as(i32, 2), bidi_visual_to_logical(&v2l, 5, 2));
}

test "cursor mapping - RTL reversal" {
    const text = [_]u32{ 0x05E9, 0x05DC, 0x05D5, 0x05DD };
    var v2l: [4]i32 = undefined;
    var l2v: [4]i32 = undefined;
    var levels: [4]u8 = undefined;

    _ = bidi_process_line(&text, text.len, &v2l, &l2v, &levels);

    // Logical position 0 (first Hebrew char) should map to visual position 3 (last displayed)
    try std.testing.expectEqual(@as(i32, 3), bidi_logical_to_visual(&l2v, 4, 0));

    // Visual position 0 should map to logical position 3
    try std.testing.expectEqual(@as(i32, 3), bidi_visual_to_logical(&v2l, 4, 0));
}
