// bidi_lib.zig - Full UAX #9 Unicode Bidirectional Algorithm
// Clean FFI exports without std.testing - Tests are in bidi.zig

// ============================================================================
// BIDI CHARACTER CLASSES (UAX #9)
// ============================================================================

/// Unicode Bidirectional Character Classes
pub const BidiClass = enum(u8) {
    // Strong types
    L = 0, // Left-to-Right (Latin, Greek, Cyrillic)
    R = 1, // Right-to-Left (Hebrew)
    AL = 2, // Arabic Letter (treated as R for simplicity)

    // Weak types
    EN = 3, // European Number (0-9)
    ES = 4, // European Separator (+, -)
    ET = 5, // European Terminator ($, %, degree)
    AN = 6, // Arabic Number
    CS = 7, // Common Separator (,./: etc)
    NSM = 8, // Non-spacing Mark (combining chars, nikud)
    BN = 9, // Boundary Neutral (format chars)

    // Neutral types
    B = 10, // Paragraph Separator
    S = 11, // Segment Separator (tab)
    WS = 12, // Whitespace
    ON = 13, // Other Neutral (punctuation)
};

// ============================================================================
// CHARACTER CLASSIFICATION
// ============================================================================

/// Get the BiDi class for a Unicode codepoint
fn getBidiClass(cp: u21) BidiClass {
    // === RTL Scripts ===

    // Hebrew letters: U+05D0-U+05EA (aleph through tav)
    if (cp >= 0x05D0 and cp <= 0x05EA) return .R;

    // Hebrew nikud (vowel points): U+05B0-U+05BD - these are NSM
    if (cp >= 0x05B0 and cp <= 0x05BD) return .NSM;

    // Hebrew punctuation: U+05BE (maqaf), U+05C0, U+05C3, U+05C6
    if (cp == 0x05BE or cp == 0x05C0 or cp == 0x05C3 or cp == 0x05C6) return .R;

    // Hebrew points: U+05BF, U+05C1, U+05C2, U+05C4, U+05C5, U+05C7 - NSM
    if (cp == 0x05BF or cp == 0x05C1 or cp == 0x05C2 or
        cp == 0x05C4 or cp == 0x05C5 or cp == 0x05C7) return .NSM;

    // Hebrew te'amim (cantillation): U+0591-U+05AF - NSM
    if (cp >= 0x0591 and cp <= 0x05AF) return .NSM;

    // === LTR Scripts ===

    // Latin letters (A-Z, a-z)
    if ((cp >= 'A' and cp <= 'Z') or (cp >= 'a' and cp <= 'z')) return .L;

    // Extended Latin (Latin Extended-A, B, etc)
    if (cp >= 0x00C0 and cp <= 0x024F) return .L;

    // Greek
    if (cp >= 0x0370 and cp <= 0x03FF) return .L;

    // Cyrillic
    if (cp >= 0x0400 and cp <= 0x04FF) return .L;

    // === Numbers ===

    // European numbers (0-9)
    if (cp >= '0' and cp <= '9') return .EN;

    // Superscript/subscript numbers
    if (cp == 0x00B2 or cp == 0x00B3 or cp == 0x00B9) return .EN; // superscripts
    if (cp >= 0x2070 and cp <= 0x2079) return .EN; // more superscripts
    if (cp >= 0x2080 and cp <= 0x2089) return .EN; // subscripts

    // === Separators and Terminators ===

    // European separators: + -
    if (cp == '+' or cp == '-') return .ES;

    // European terminators: # $ % etc
    if (cp == '#' or cp == '$' or cp == '%' or cp == 0x00A2 or // cent
        cp == 0x00A3 or cp == 0x00A4 or cp == 0x00A5 or // pound, currency, yen
        cp == 0x00B0 or cp == 0x2030 or cp == 0x2031) return .ET; // degree, per mille

    // Common separators: , . / :
    if (cp == ',' or cp == '.' or cp == '/' or cp == ':') return .CS;

    // === Whitespace and Separators ===

    // Paragraph separator
    if (cp == 0x2029) return .B;

    // Segment separator (tab)
    if (cp == '\t') return .S;

    // Whitespace
    if (cp == ' ' or cp == '\n' or cp == '\r' or cp == 0x000C or // form feed
        cp == 0x00A0 or // nbsp
        cp == 0x2000 or cp == 0x2001 or cp == 0x2002 or cp == 0x2003 or
        cp == 0x2004 or cp == 0x2005 or cp == 0x2006 or cp == 0x2007 or
        cp == 0x2008 or cp == 0x2009 or cp == 0x200A or cp == 0x200B or
        cp == 0x3000) return .WS;

    // Boundary neutral (zero-width chars)
    if (cp == 0x200B or cp == 0x200C or cp == 0x200D or cp == 0x2060 or
        cp == 0xFEFF) return .BN;

    // === Neutral (everything else including punctuation) ===
    return .ON;
}

/// Check if a class is a strong type (L or R)
fn isStrong(class: BidiClass) bool {
    return class == .L or class == .R or class == .AL;
}

/// Check if a class is neutral (B, S, WS, ON)
fn isNeutral(class: BidiClass) bool {
    return class == .B or class == .S or class == .WS or class == .ON;
}

/// Get the strong direction for a class (L or R)
fn getStrongDirection(class: BidiClass) BidiClass {
    return switch (class) {
        .L => .L,
        .R, .AL, .AN => .R,
        .EN => .L, // EN is treated as L for direction purposes after resolution
        else => .L, // Neutrals default to paragraph direction
    };
}

// ============================================================================
// UAX #9 ALGORITHM IMPLEMENTATION
// ============================================================================

/// Maximum line length we support
const MAX_LINE_LEN = 4096;

/// Working arrays for BiDi processing
const BidiWorkspace = struct {
    classes: [MAX_LINE_LEN]BidiClass,
    levels: [MAX_LINE_LEN]u8,
    visual_to_logical: [MAX_LINE_LEN]i32,
    logical_to_visual: [MAX_LINE_LEN]i32,
};

/// Static workspace to avoid allocation
var workspace: BidiWorkspace = undefined;

// --- Rule W1: NSM inherits type from previous character ---
fn applyW1(classes: []BidiClass, para_level: u8) void {
    // sos type based on paragraph level
    var prev_class: BidiClass = if (para_level % 2 == 0) .L else .R;

    for (classes) |*class| {
        if (class.* == .NSM) {
            class.* = prev_class;
        } else if (class.* != .BN) {
            prev_class = class.*;
        }
    }
}

// --- Rule W2: EN after AL becomes AN ---
fn applyW2(classes: []BidiClass) void {
    var last_strong: BidiClass = .L; // sos

    for (classes) |*class| {
        if (class.* == .R or class.* == .L or class.* == .AL) {
            last_strong = class.*;
        } else if (class.* == .EN and last_strong == .AL) {
            class.* = .AN;
        }
    }
}

// --- Rule W3: AL becomes R ---
fn applyW3(classes: []BidiClass) void {
    for (classes) |*class| {
        if (class.* == .AL) {
            class.* = .R;
        }
    }
}

// --- Rule W4: Single ES between EN+EN -> EN, CS between same number types ---
fn applyW4(classes: []BidiClass) void {
    if (classes.len < 3) return;

    var i: usize = 1;
    while (i < classes.len - 1) : (i += 1) {
        const prev = classes[i - 1];
        const curr = classes[i];
        const next = classes[i + 1];

        if (curr == .ES and prev == .EN and next == .EN) {
            classes[i] = .EN;
        } else if (curr == .CS) {
            if ((prev == .EN and next == .EN) or (prev == .AN and next == .AN)) {
                classes[i] = prev;
            }
        }
    }
}

// --- Rule W5: ET adjacent to EN becomes EN ---
fn applyW5(classes: []BidiClass) void {
    // Forward pass: ET after EN
    var i: usize = 0;
    while (i < classes.len) : (i += 1) {
        if (classes[i] == .EN) {
            // Convert following ET sequence to EN
            var j = i + 1;
            while (j < classes.len and classes[j] == .ET) : (j += 1) {
                classes[j] = .EN;
            }
        }
    }

    // Backward pass: ET before EN
    if (classes.len > 0) {
        i = classes.len - 1;
        while (true) {
            if (classes[i] == .EN) {
                // Convert preceding ET sequence to EN
                if (i > 0) {
                    var j = i - 1;
                    while (classes[j] == .ET) {
                        classes[j] = .EN;
                        if (j == 0) break;
                        j -= 1;
                    }
                }
            }
            if (i == 0) break;
            i -= 1;
        }
    }
}

// --- Rule W6: ES, ET, CS become ON ---
fn applyW6(classes: []BidiClass) void {
    for (classes) |*class| {
        if (class.* == .ES or class.* == .ET or class.* == .CS) {
            class.* = .ON;
        }
    }
}

// --- Rule W7: EN after last strong L becomes L ---
fn applyW7(classes: []BidiClass, para_level: u8) void {
    var last_strong: BidiClass = if (para_level % 2 == 0) .L else .R;

    for (classes) |*class| {
        if (class.* == .L or class.* == .R) {
            last_strong = class.*;
        } else if (class.* == .EN and last_strong == .L) {
            class.* = .L;
        }
    }
}

// --- Rule N1: Neutrals between characters of same direction ---
fn applyN1(classes: []BidiClass, para_level: u8) void {
    if (classes.len == 0) return;

    const sos: BidiClass = if (para_level % 2 == 0) .L else .R;
    const eos: BidiClass = if (para_level % 2 == 0) .L else .R;

    var i: usize = 0;
    while (i < classes.len) {
        if (isNeutral(classes[i])) {
            const neutral_start = i;

            // Find end of neutral run
            while (i < classes.len and isNeutral(classes[i])) : (i += 1) {}

            // Get surrounding strong types
            const before: BidiClass = if (neutral_start > 0)
                getStrongFromClass(classes[neutral_start - 1])
            else
                sos;

            const after: BidiClass = if (i < classes.len)
                getStrongFromClass(classes[i])
            else
                eos;

            // N1: If both sides are same direction, neutrals adopt that direction
            if (before == after) {
                var j = neutral_start;
                while (j < i) : (j += 1) {
                    classes[j] = before;
                }
            }
        } else {
            i += 1;
        }
    }
}

fn getStrongFromClass(class: BidiClass) BidiClass {
    return switch (class) {
        .L => .L,
        .R, .AN, .EN => .R,
        else => .L, // Default
    };
}

// --- Rule N2: Remaining neutrals adopt embedding direction ---
fn applyN2(classes: []BidiClass, para_level: u8) void {
    const embed_class: BidiClass = if (para_level % 2 == 0) .L else .R;

    for (classes) |*class| {
        if (isNeutral(class.*)) {
            class.* = embed_class;
        }
    }
}

// --- Rule I1 & I2: Implicit level assignment ---
fn applyImplicitLevels(classes: []const BidiClass, levels: []u8, para_level: u8) void {
    for (classes, 0..) |class, i| {
        const level = para_level; // We use simplified single-level embedding

        // I1: At even (LTR) levels
        if (level % 2 == 0) {
            if (class == .R) {
                levels[i] = level + 1;
            } else if (class == .AN or class == .EN) {
                levels[i] = level + 2;
            } else {
                levels[i] = level;
            }
        }
        // I2: At odd (RTL) levels
        else {
            if (class == .L or class == .EN or class == .AN) {
                levels[i] = level + 1;
            } else {
                levels[i] = level;
            }
        }
    }
}

// --- Rule L2: Reorder based on levels ---
fn reorderLine(
    levels: []const u8,
    visual_to_logical: []i32,
    logical_to_visual: []i32,
    len: usize,
) void {
    // Initialize identity mapping
    for (0..len) |i| {
        visual_to_logical[i] = @intCast(i);
    }

    // Find maximum level
    var max_level: u8 = 0;
    for (levels[0..len]) |level| {
        if (level > max_level) {
            max_level = level;
        }
    }

    // L2: From max level down to 1, reverse runs at each level
    var level = max_level;
    while (level >= 1) {
        var i: usize = 0;
        while (i < len) {
            // Find run of characters at >= current level
            const logical_idx: usize = @intCast(visual_to_logical[i]);
            if (levels[logical_idx] >= level) {
                const run_start = i;
                while (i < len) {
                    const li: usize = @intCast(visual_to_logical[i]);
                    if (levels[li] < level) break;
                    i += 1;
                }
                // Reverse this run
                reverseRange(visual_to_logical, run_start, i);
            } else {
                i += 1;
            }
        }

        if (level == 0) break;
        level -= 1;
    }

    // Build logical_to_visual from visual_to_logical
    for (0..len) |visual| {
        const logical: usize = @intCast(visual_to_logical[visual]);
        logical_to_visual[logical] = @intCast(visual);
    }
}

fn reverseRange(arr: []i32, start: usize, end: usize) void {
    if (start >= end) return;
    var i = start;
    var j = end - 1;
    while (i < j) {
        const temp = arr[i];
        arr[i] = arr[j];
        arr[j] = temp;
        i += 1;
        j -= 1;
    }
}

// ============================================================================
// EXPORTED FUNCTIONS (C FFI)
// ============================================================================

/// Test FFI connection - returns 42
pub export fn bidi_test_connection() i32 {
    return 42;
}

/// Get paragraph direction based on first strong character
/// Returns: 0 = LTR, 1 = RTL
pub export fn bidi_get_paragraph_direction(
    text: [*]const u32,
    len: usize,
) u8 {
    if (len == 0) return 0;

    for (text[0..len]) |cp| {
        const class = getBidiClass(@intCast(cp));
        switch (class) {
            .L => return 0,
            .R, .AL => return 1,
            else => continue,
        }
    }

    return 0; // Default LTR
}

/// Check if a codepoint is Hebrew/RTL
pub export fn bidi_is_hebrew(cp: u32) bool {
    const class = getBidiClass(@intCast(cp));
    return class == .R;
}

/// Check if a line contains any RTL characters
pub export fn bidi_has_rtl(text: [*]const u32, len: usize) bool {
    if (len == 0) return false;

    for (text[0..len]) |cp| {
        const class = getBidiClass(@intCast(cp));
        if (class == .R or class == .AL) {
            return true;
        }
    }
    return false;
}

/// Process a line of text and compute BiDi reordering
/// @param text: Unicode codepoints (UTF-32)
/// @param len: Number of codepoints
/// @param visual_to_logical: Output - maps visual position to logical position
/// @param logical_to_visual: Output - maps logical position to visual position
/// @param resolved_levels: Output - embedding level per character
/// @return Paragraph direction (0 = LTR, 1 = RTL)
pub export fn bidi_process_line(
    text: [*]const u32,
    len: usize,
    visual_to_logical: [*]i32,
    logical_to_visual: [*]i32,
    resolved_levels: [*]u8,
) u8 {
    if (len == 0) return 0;
    if (len > MAX_LINE_LEN) return 0; // Too long, skip processing

    // Step 1: Get paragraph direction (P2-P3)
    const para_level = bidi_get_paragraph_direction(text, len);

    // Step 2: Assign initial BiDi classes
    for (0..len) |i| {
        workspace.classes[i] = getBidiClass(@intCast(text[i]));
        workspace.levels[i] = para_level;
    }

    // Step 3: Apply weak type resolution (W1-W7)
    applyW1(workspace.classes[0..len], para_level);
    applyW2(workspace.classes[0..len]);
    applyW3(workspace.classes[0..len]);
    applyW4(workspace.classes[0..len]);
    applyW5(workspace.classes[0..len]);
    applyW6(workspace.classes[0..len]);
    applyW7(workspace.classes[0..len], para_level);

    // Step 4: Apply neutral type resolution (N1-N2)
    applyN1(workspace.classes[0..len], para_level);
    applyN2(workspace.classes[0..len], para_level);

    // Step 5: Apply implicit level assignment (I1-I2)
    applyImplicitLevels(workspace.classes[0..len], workspace.levels[0..len], para_level);

    // Step 6: Compute reordering (L2)
    reorderLine(
        workspace.levels[0..len],
        workspace.visual_to_logical[0..len],
        workspace.logical_to_visual[0..len],
        len,
    );

    // Copy results to output arrays
    for (0..len) |i| {
        visual_to_logical[i] = workspace.visual_to_logical[i];
        logical_to_visual[i] = workspace.logical_to_visual[i];
        resolved_levels[i] = workspace.levels[i];
    }

    return para_level;
}

/// Convert logical cursor position to visual position
pub export fn bidi_logical_to_visual(
    logical_to_visual: [*]const i32,
    len: usize,
    logical_pos: i32,
) i32 {
    if (logical_pos < 0) return 0;
    if (@as(usize, @intCast(logical_pos)) >= len) return @intCast(len);
    return logical_to_visual[@intCast(logical_pos)];
}

/// Convert visual cursor position to logical position
pub export fn bidi_visual_to_logical(
    visual_to_logical: [*]const i32,
    len: usize,
    visual_pos: i32,
) i32 {
    if (visual_pos < 0) return 0;
    if (@as(usize, @intCast(visual_pos)) >= len) return @intCast(len);
    return visual_to_logical[@intCast(visual_pos)];
}

/// Move cursor in visual order through BiDi text.
/// Takes codepoints, byte offsets, current byte position, and direction.
/// Returns new byte position, or -1 if at boundary or no RTL text.
/// @param text: array of Unicode codepoints
/// @param byte_offsets: byte offset for each character
/// @param char_count: number of characters
/// @param cur_byte_pos: current cursor byte position
/// @param direction: +1 for right, -1 for left
pub export fn bidi_cursor_move_visual(
    text: [*]const u32,
    byte_offsets: [*]const i32,
    char_count: usize,
    cur_byte_pos: i32,
    direction: i32,
) i32 {
    if (char_count == 0) return -1;
    if (char_count > MAX_LINE_LEN) return -1;

    // Quick check: if no RTL, signal to use normal movement
    var has_rtl = false;
    for (0..char_count) |i| {
        const cp: u21 = @intCast(text[i] & 0x1FFFFF);
        const class = getBidiClass(cp);
        if (class == .R or class == .AL) {
            has_rtl = true;
            break;
        }
    }
    if (!has_rtl) return -1;

    // Find current character index from byte position
    var cur_char: i32 = -1;
    for (0..char_count) |i| {
        if (byte_offsets[i] == cur_byte_pos) {
            cur_char = @intCast(i);
            break;
        }
        if (byte_offsets[i] > cur_byte_pos) {
            // Cursor in middle of multi-byte char, use previous
            cur_char = if (i > 0) @intCast(i - 1) else 0;
            break;
        }
    }
    // If not found, cursor is at end of line
    if (cur_char < 0) {
        cur_char = @intCast(char_count - 1);
    }

    // Get paragraph direction
    const para_level = bidi_get_paragraph_direction(text, char_count);

    // Assign initial BiDi classes and levels (using global workspace)
    for (0..char_count) |i| {
        const cp: u21 = @intCast(text[i] & 0x1FFFFF);
        workspace.classes[i] = getBidiClass(cp);
        workspace.levels[i] = para_level;
    }

    // Apply UAX #9 rules
    applyW1(workspace.classes[0..char_count], para_level);
    applyW2(workspace.classes[0..char_count]);
    applyW3(workspace.classes[0..char_count]);
    applyW4(workspace.classes[0..char_count]);
    applyW5(workspace.classes[0..char_count]);
    applyW6(workspace.classes[0..char_count]);
    applyW7(workspace.classes[0..char_count], para_level);
    applyN1(workspace.classes[0..char_count], para_level);
    applyN2(workspace.classes[0..char_count], para_level);
    applyImplicitLevels(workspace.classes[0..char_count], workspace.levels[0..char_count], para_level);
    reorderLine(
        workspace.levels[0..char_count],
        workspace.visual_to_logical[0..char_count],
        workspace.logical_to_visual[0..char_count],
        char_count,
    );

    // Convert logical → visual, move, convert back
    const visual_pos = workspace.logical_to_visual[@intCast(cur_char)];
    const new_visual = visual_pos + direction;

    if (new_visual < 0 or new_visual >= @as(i32, @intCast(char_count))) {
        return -1; // At boundary
    }

    const new_logical = workspace.visual_to_logical[@intCast(new_visual)];
    if (new_logical < 0 or new_logical >= @as(i32, @intCast(char_count))) {
        return -1;
    }

    return byte_offsets[@intCast(new_logical)];
}

/// Get byte position of character at visual column in BiDi text.
/// Computes BiDi reordering and returns the byte position of the character
/// displayed at the given visual column.
///
/// @param text: array of Unicode codepoints
/// @param byte_offsets: byte offset for each character
/// @param char_count: number of characters
/// @param visual_col: visual column (screen position)
/// @return byte position, or -1 if no RTL text or out of range
pub export fn bidi_visual_col_to_byte(
    text: [*]const u32,
    byte_offsets: [*]const i32,
    char_count: usize,
    visual_col: i32,
) i32 {
    if (char_count == 0) return -1;
    if (char_count > MAX_LINE_LEN) return -1;
    if (visual_col < 0 or visual_col >= @as(i32, @intCast(char_count))) return -1;

    // Quick check: if no RTL, visual = logical
    var has_rtl = false;
    for (0..char_count) |i| {
        const cp: u21 = @intCast(text[i] & 0x1FFFFF);
        const class = getBidiClass(cp);
        if (class == .R or class == .AL) {
            has_rtl = true;
            break;
        }
    }
    if (!has_rtl) {
        // No RTL - visual column equals logical index
        return byte_offsets[@intCast(visual_col)];
    }

    // Get paragraph direction
    const para_level = bidi_get_paragraph_direction(text, char_count);

    // Assign initial BiDi classes and levels
    for (0..char_count) |i| {
        const cp: u21 = @intCast(text[i] & 0x1FFFFF);
        workspace.classes[i] = getBidiClass(cp);
        workspace.levels[i] = para_level;
    }

    // Apply UAX #9 rules
    applyW1(workspace.classes[0..char_count], para_level);
    applyW2(workspace.classes[0..char_count]);
    applyW3(workspace.classes[0..char_count]);
    applyW4(workspace.classes[0..char_count]);
    applyW5(workspace.classes[0..char_count]);
    applyW6(workspace.classes[0..char_count]);
    applyW7(workspace.classes[0..char_count], para_level);
    applyN1(workspace.classes[0..char_count], para_level);
    applyN2(workspace.classes[0..char_count], para_level);
    applyImplicitLevels(workspace.classes[0..char_count], workspace.levels[0..char_count], para_level);
    reorderLine(
        workspace.levels[0..char_count],
        workspace.visual_to_logical[0..char_count],
        workspace.logical_to_visual[0..char_count],
        char_count,
    );

    // Get logical index for this visual column
    const logical_idx = workspace.visual_to_logical[@intCast(visual_col)];
    if (logical_idx < 0 or logical_idx >= @as(i32, @intCast(char_count))) {
        return -1;
    }

    return byte_offsets[@intCast(logical_idx)];
}
