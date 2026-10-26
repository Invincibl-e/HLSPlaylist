#ifndef HLS_C_URI_PARSER_H
#define HLS_C_URI_PARSER_H
// Uri.h self-includes for its ANSI/Unicode passes. Select the ANSI pass before
// Clang's module importer sees it so the public declarations are not skipped.
#define URI_PASS_ANSI 1
#include "uriparser/Uri.h"
#undef URI_PASS_ANSI
#endif
