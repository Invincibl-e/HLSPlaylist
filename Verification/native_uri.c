#include <uriparser/Uri.h>
#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

/* Include this translation unit to reach its static item-count boundary. */
#include "../Sources/CURIParser/src/UriQuery.c"

static void parse(UriUriA *uri, const char *text) {
    assert(uriParseSingleUriA(uri, text, NULL) == URI_SUCCESS);
}

static void expect_uri(UriUriA *uri, const char *expected, int host) {
    char buffer[256];
    assert(uriToStringA(buffer, uri, sizeof(buffer), NULL) == URI_SUCCESS);
    if (strcmp(buffer, expected)) {
        fprintf(stderr, "expected %s; got %s\n", expected, buffer);
        abort();
    }
    UriUriA reparsed, copied;
    parse(&reparsed, buffer);
    assert((reparsed.hostText.first != NULL) == host);
    assert(uriEqualsUriA(uri, &reparsed));
    assert(uriCopyUriA(&copied, uri) == URI_SUCCESS);
    assert(uriEqualsUriA(uri, &copied));
    uriFreeUriMembersA(&copied);
    uriFreeUriMembersA(&reparsed);
}

static void normalization(void) {
    const char *inputs[] = {
        "scheme:..///foo/bar?query#fragment", "scheme:a/..///foo/bar",
        "scheme:/a/..//foo/bar", "scheme://host/a/..//foo/bar",
        "/a/..", "/a/../", "scheme:/a/..", "scheme:/a/../"
    };
    /* RFC 3986 5.2.4 leaves ///foo after a/..; /. prevents authority parsing. */
    const char *expected[] = {
        "scheme:.///foo/bar?query#fragment", "scheme:/.///foo/bar",
        "scheme:/.//foo/bar", "scheme://host//foo/bar",
        "/", "/", "scheme:/", "scheme:/"
    };
    for (size_t i = 0; i < sizeof(inputs) / sizeof(*inputs); ++i) {
        for (int owned = 0; owned < 2; ++owned) {
            UriUriA uri;
            parse(&uri, inputs[i]);
            if (owned) assert(uriMakeOwnerA(&uri) == URI_SUCCESS);
            for (int pass = 0; pass < 2; ++pass) {
                assert(uriNormalizeSyntaxA(&uri) == URI_SUCCESS);
                expect_uri(&uri, expected[i], i == 3);
            }
            uriFreeUriMembersA(&uri);
        }
    }
}

static void resolution(void) {
    const char *inputs[] = {
        "scheme:..///foo/bar?query#fragment", "scheme:a/..///foo/bar",
        "scheme:/a/..//foo/bar", "/a/..//foo/bar", "a/..//foo/bar",
        "scheme:/a/..", "/a/..", "scheme://host/a/..//foo/bar"
    };
    const char *expected[] = {
        "scheme:.///foo/bar?query#fragment", "scheme:/.///foo/bar",
        "scheme:/.//foo/bar", "base:/.//foo/bar", "base:/root//foo/bar",
        "scheme:/", "base:/", "scheme://host//foo/bar"
    };
    UriUriA base;
    parse(&base, "base:/root/file");
    for (size_t i = 0; i < sizeof(inputs) / sizeof(*inputs); ++i) {
        UriUriA input, result;
        parse(&input, inputs[i]);
        assert(uriAddBaseUriA(&result, &input, &base) == URI_SUCCESS);
        expect_uri(&result, expected[i], i == 7);
        uriFreeUriMembersA(&result);
        uriFreeUriMembersA(&input);
    }
    uriFreeUriMembersA(&base);
}

static void parse_failure(void) {
    const char *inputs[] = {"ab%zz", "scheme:/a b", "http://[::1", "http://x/#a#b"};
    for (size_t i = 0; i < sizeof(inputs) / sizeof(*inputs); ++i) {
        char *text = strdup(inputs[i]);
        UriUriA uri;
        const char *error = NULL;
        assert(uriParseSingleUriA(&uri, text, &error) == URI_ERROR_SYNTAX);
        assert(error >= text && error <= text + strlen(text));
        assert(uri.scheme.first == NULL && uri.scheme.afterLast == NULL);
        assert(uri.hostText.first == NULL && uri.pathHead == NULL);
        assert(uri.owner == URI_FALSE);
        const char host[] = "host";
        assert(uriSetHostRegNameA(&uri, host, host + 4) == URI_SUCCESS);
        uriFreeUriMembersA(&uri);
        free(text);
    }
}

static void tostring_boundary(const char *variant) {
    const size_t length = (size_t)INT_MAX + 4096;
    char *text = mmap(NULL, length, PROT_READ | PROT_WRITE,
            MAP_PRIVATE | MAP_ANON, -1, 0);
    assert(text != MAP_FAILED);
    UriUriA uri = {0};
    UriIp4 ip4 = {{255, 255, 255, 255}};
    UriIp6 ip6 = {{0}};
    UriPathSegmentA path = {0}, second = {0};
    int count = 0;
    uri.scheme.first = text;
    uri.scheme.afterLast = text + INT_MAX;
    if (!strcmp(variant, "authority")) {
        uri.scheme.afterLast -= 1;
        uri.hostText.first = uri.hostText.afterLast = text;
    } else if (!strcmp(variant, "ipv4") || !strcmp(variant, "ipv6")) {
        uri.scheme.afterLast -= 3;
        uri.hostText.first = uri.hostText.afterLast = text;
        if (!strcmp(variant, "ipv4")) uri.hostData.ip4 = &ip4;
        else uri.hostData.ip6 = &ip6;
    } else if (!strcmp(variant, "query-mark")) {
        uri.scheme.afterLast -= 1;
        uri.query.first = uri.query.afterLast = text;
    } else if (!strcmp(variant, "fragment")) {
        uri.scheme.afterLast -= 1;
        uri.fragment.first = uri.fragment.afterLast = text;
    } else if (!strcmp(variant, "path")) {
        uri.scheme.afterLast -= 1;
        uri.absolutePath = URI_TRUE;
        uri.pathHead = uri.pathTail = &path;
        path.text.first = path.text.afterLast = text;
    } else if (!strcmp(variant, "separator")) {
        uri.scheme.afterLast -= 1;
        uri.pathHead = &path;
        uri.pathTail = &second;
        path.next = &second;
        path.text.first = path.text.afterLast = text;
        second.text = path.text;
    }
    assert(uriToStringCharsRequiredA(&uri, &count) == URI_ERROR_TOSTRING_TOO_LONG);
    assert(munmap(text, length) == 0);
}

static void query_boundary(void) {
    const size_t nodes = 8000, key_length = 50000;
    char *key = malloc(key_length + 1);
    UriQueryListA *items = calloc(nodes, sizeof(*items));
    assert(key && items);
    memset(key, '\n', key_length);
    key[key_length] = '\0';
    for (size_t i = 0; i < nodes; ++i) {
        items[i].key = key;
        items[i].next = i + 1 < nodes ? &items[i + 1] : NULL;
    }
    int count = 0;
    assert(uriComposeQueryCharsRequiredExA(items, &count, URI_TRUE, URI_TRUE)
            == URI_ERROR_OUTPUT_TOO_LARGE);
    /* A normal list still composes and reports its conservative bound. */
    items[0].next = NULL;
    assert(uriComposeQueryCharsRequiredExA(items, &count, URI_TRUE, URI_TRUE)
            == URI_SUCCESS);
    assert(count == 300000);
    free(items);
    free(key);
}

static int allocations_left;
static void *limited_malloc(UriMemoryManager *memory, size_t bytes) {
    (void)memory;
    if (allocations_left-- <= 0) return NULL;
    return malloc(bytes);
}

static void append_boundary(void) {
    UriMemoryManager memory = defaultMemoryManager;
    UriQueryListA *item = NULL;
    int count = INT_MAX;
    const char empty[] = "";
    const char key[] = "k";
    assert(uriAppendQueryItemA(&item, &count, key, key + 1, empty, empty,
            URI_TRUE, URI_BR_DONT_TOUCH, &memory) == URI_FALSE);
    assert(item == NULL && count == INT_MAX);
}

static void allocation_failure(void) {
    for (int limit = 0; limit < 2; ++limit) {
        UriUriA uri;
        parse(&uri, "scheme:..///foo/bar");
        assert(uriMakeOwnerA(&uri) == URI_SUCCESS);
        UriMemoryManager memory = defaultMemoryManager;
        memory.malloc = limited_malloc;
        allocations_left = limit;
        assert(uriNormalizeSyntaxExMmA(&uri, URI_NORMALIZE_PATH, &memory)
                == URI_ERROR_MALLOC);
        assert(allocations_left == -1);
        uriFreeUriMembersA(&uri);
    }
}

int main(int argc, char **argv) {
    assert(argc == 2);
    if (!strcmp(argv[1], "normalize")) normalization();
    else if (!strcmp(argv[1], "resolve")) resolution();
    else if (!strcmp(argv[1], "parse-failure")) parse_failure();
    else if (!strcmp(argv[1], "query")) query_boundary();
    else if (!strcmp(argv[1], "append")) append_boundary();
    else if (!strcmp(argv[1], "allocation-failure")) allocation_failure();
    else tostring_boundary(argv[1]);
    printf("passed: %s\n", argv[1]);
    return 0;
}
