find_path2(BIDI_INCLUDE_DIR bidi.h)
find_library2(BIDI_LIBRARY NAMES bidi)
find_package_handle_standard_args(Bidi DEFAULT_MSG
  BIDI_LIBRARY BIDI_INCLUDE_DIR)
mark_as_advanced(BIDI_LIBRARY BIDI_INCLUDE_DIR)

add_library(bidi INTERFACE)
target_include_directories(bidi SYSTEM BEFORE INTERFACE ${BIDI_INCLUDE_DIR})
target_link_libraries(bidi INTERFACE ${BIDI_LIBRARY})
