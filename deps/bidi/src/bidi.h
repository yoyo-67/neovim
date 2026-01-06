#ifndef BIDI_H
#define BIDI_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// BASIC FUNCTIONS
// ============================================================================

/// Test FFI connection - returns 42 if working correctly
int32_t bidi_test_connection(void);

/// Get paragraph direction based on first strong character
/// @param text Array of Unicode codepoints (UTF-32)
/// @param len Number of codepoints in text
/// @return 0 = LTR, 1 = RTL
uint8_t bidi_get_paragraph_direction(const uint32_t *text, size_t len);

/// Check if a codepoint is Hebrew (RTL)
/// @param cp Unicode codepoint
/// @return true if the codepoint is Hebrew/RTL
bool bidi_is_hebrew(uint32_t cp);

/// Check if a line contains any RTL characters
/// @param text Array of Unicode codepoints (UTF-32)
/// @param len Number of codepoints
/// @return true if any RTL character is present
bool bidi_has_rtl(const uint32_t *text, size_t len);

// ============================================================================
// FULL UAX #9 BiDi PROCESSING
// ============================================================================

/// Process a line of text and compute BiDi reordering
///
/// This implements the Unicode Bidirectional Algorithm (UAX #9) to determine
/// how mixed RTL/LTR text should be displayed visually.
///
/// @param text Array of Unicode codepoints (UTF-32) in logical order
/// @param len Number of codepoints in text
/// @param visual_to_logical Output array mapping visual position -> logical position
///                          (must be pre-allocated with size >= len)
/// @param logical_to_visual Output array mapping logical position -> visual position
///                          (must be pre-allocated with size >= len)
/// @param resolved_levels Output array with embedding level per character
///                        (must be pre-allocated with size >= len)
/// @return Paragraph direction (0 = LTR, 1 = RTL)
///
/// Example:
///   "Hello שלום World" (logical order)
///   After processing, visual_to_logical maps how to reorder for display:
///   - Positions 0-5 map to "Hello " (unchanged, LTR)
///   - Positions 6-9 map to "םולש" (reversed, RTL)
///   - Positions 10-15 map to " World" (unchanged, LTR)
uint8_t bidi_process_line(
    const uint32_t *text,
    size_t len,
    int32_t *visual_to_logical,
    int32_t *logical_to_visual,
    uint8_t *resolved_levels
);

// ============================================================================
// CURSOR POSITION MAPPING
// ============================================================================

/// Convert logical cursor position to visual position
///
/// When editing BiDi text, the cursor moves through characters in logical order
/// (how they're stored), but needs to be displayed at the visual position
/// (where they appear on screen).
///
/// @param logical_to_visual Mapping array from bidi_process_line()
/// @param len Array length (number of characters)
/// @param logical_pos Logical cursor position (0-based)
/// @return Visual cursor position
int32_t bidi_logical_to_visual(
    const int32_t *logical_to_visual,
    size_t len,
    int32_t logical_pos
);

/// Convert visual cursor position to logical position
///
/// For mouse clicks or visual cursor movements, convert the visual position
/// (where clicked/moved) to the logical position (buffer position).
///
/// @param visual_to_logical Mapping array from bidi_process_line()
/// @param len Array length (number of characters)
/// @param visual_pos Visual cursor position (0-based)
/// @return Logical cursor position
int32_t bidi_visual_to_logical(
    const int32_t *visual_to_logical,
    size_t len,
    int32_t visual_pos
);

/// Move cursor in visual order through BiDi text
///
/// Computes BiDi reordering and returns the byte position of the next
/// character in visual order.
///
/// @param text Array of Unicode codepoints (UTF-32)
/// @param byte_offsets Byte offset for each character in the line
/// @param char_count Number of characters
/// @param cur_byte_pos Current cursor byte position
/// @param direction +1 for right, -1 for left
/// @return New byte position, or -1 if at boundary or no RTL text
int32_t bidi_cursor_move_visual(
    const uint32_t *text,
    const int32_t *byte_offsets,
    size_t char_count,
    int32_t cur_byte_pos,
    int32_t direction
);

/// Get byte position of character at visual column in BiDi text
///
/// Computes BiDi reordering and returns the byte position of the character
/// displayed at the given visual column. Used for operations like 'x' to
/// delete the visually displayed character.
///
/// @param text Array of Unicode codepoints (UTF-32)
/// @param byte_offsets Byte offset for each character in the line
/// @param char_count Number of characters
/// @param visual_col Visual column (screen position, 0-based)
/// @return Byte position, or -1 if no RTL text or out of range
int32_t bidi_visual_col_to_byte(
    const uint32_t *text,
    const int32_t *byte_offsets,
    size_t char_count,
    int32_t visual_col
);

#ifdef __cplusplus
}
#endif

#endif // BIDI_H
