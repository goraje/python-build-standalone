#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

set -ex

ROOT=`pwd`

export PATH=${TOOLS_PATH}/deps/bin:${TOOLS_PATH}/${TOOLCHAIN}/bin:${TOOLS_PATH}/host/bin:$PATH
export PKG_CONFIG_PATH=${TOOLS_PATH}/deps/share/pkgconfig:${TOOLS_PATH}/deps/lib/pkgconfig

tar -xf tk${TK_VERSION}-src.tar.gz

pushd tk*/unix

patch -p1 << 'EOF'
diff --git a/macosx/tkMacOSXDialog.c b/macosx/tkMacOSXDialog.c
--- a/macosx/tkMacOSXDialog.c
+++ b/macosx/tkMacOSXDialog.c
@@ -31,24 +31,7 @@ static void setAllowedFileTypes(
     NSSavePanel *panel,
     NSMutableArray *extensions)
 {
-#if MAC_OS_X_VERSION_MAX_ALLOWED >= 110000
-/* UTType exists in the SDK */
-    if (@available(macOS 11.0, *)) {
-       NSMutableArray<UTType *> *allowedTypes = [NSMutableArray array];
-       for (NSString *ext in extensions) {
-           UTType *uttype = [UTType typeWithFilenameExtension: ext];
-           [allowedTypes addObject:uttype];
-       }
-       [panel setAllowedContentTypes:allowedTypes];
-    } else {
-# if MAC_OS_X_VERSION_MIN_REQUIRED < 110000
-/* setAllowedFileTypes is not deprecated */
-       [panel setAllowedFileTypes:extensions];
-#endif
-    }
-#else
     [panel setAllowedFileTypes:extensions];
-#endif
 }
EOF

patch -p1 << 'EOF'
diff --git a/macosx/tkMacOSXFileTypes.c b/macosx/tkMacOSXFileTypes.c
--- a/macosx/tkMacOSXFileTypes.c
+++ b/macosx/tkMacOSXFileTypes.c
@@ -42,14 +42,7 @@ MODULE_SCOPE NSString *TkMacOSXOSTypeToUTI(OSType ostype) {
 	return nil;
     }
     NSString *result = nil;
-#if MAC_OS_X_VERSION_MAX_ALLOWED >= 110000
-    if (@available(macOS 11.0, *)) {
-	return [UTType typeWithTag:tag tagClass:@"com.apple.ostype" conformingToType:nil].identifier;
-    }
-#endif
-#if MAC_OS_X_VERSION_MIN_REQUIRED < 110000
     result = (NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassOSType, (CFStringRef)tag, NULL);
-#endif
     return result;
 }
 
@@ -59,50 +52,7 @@ MODULE_SCOPE NSString *TkMacOSXOSTypeToUTI(OSType ostype) {
  * or a Uniform Type Idenfier.  This function can serve as a replacement.
  */
 MODULE_SCOPE NSImage *TkMacOSXIconForFileType(NSString *filetype) {
-#if MAC_OS_X_VERSION_MAX_ALLOWED < 110000
-// We don't have UTType but iconForFileType is not deprecated, so use it.
-    return [[NSWorkspace sharedWorkspace] iconForFileType:filetype];
-#else
-// We might have UTType but iconForFileType might be deprecated.
-    if (@available(macOS 11.0, *)) {
-	/* Yes, we do have UTType */
-	if (filetype == nil) {
-	    /*
-	     * Bug 9be830f61b: match the behavior of
-	     * [NSWorkspace.sharedWorkspace iconForFileType:nil]
-	     */
-	     filetype = @"public.data";
-	}
-	UTType *uttype = [UTType typeWithIdentifier: filetype];
-	if (uttype == nil || !uttype.isDeclared) {
-	    uttype = [UTType typeWithFilenameExtension: filetype];
-	}
-	if (uttype == nil || (!uttype.isDeclared && filetype.length == 4)) {
-	    OSType ostype = CHARS_TO_OSTYPE(filetype.UTF8String);
-	    NSString *UTI = TkMacOSXOSTypeToUTI(ostype);
-	    if (UTI) {
-		uttype = [UTType typeWithIdentifier:UTI];
-	    }
-	}
-	if (uttype == nil || !uttype.isDeclared) {
-	    return nil;
-	}
-	return [[NSWorkspace sharedWorkspace] iconForContentType:uttype];
-    } else {
-	/* No, we don't have UTType. */
- #if MAC_OS_X_VERSION_MIN_REQUIRED < 110000
-	/* but iconForFileType is not deprecated, so we can use it. */
     return [[NSWorkspace sharedWorkspace] iconForFileType:filetype];
- #else
-    /*
-     * Cannot be reached: MIN_REQUIRED >= 110000 yet 11.0 is not available.
-     * But the compiler can't figure that out, so it will warn about an
-     * execution path with no return value unless we put a return here.
-     */
-    return nil;
- #endif
-    }
-#endif
 }
EOF

CFLAGS="${EXTRA_TARGET_CFLAGS} -fPIC"
LDFLAGS="${EXTRA_TARGET_LDFLAGS}"

if [ "${PYBUILD_PLATFORM}" = "macos" ]; then
    CFLAGS="${CFLAGS} -I${TOOLS_PATH}/deps/include -Wno-availability"
    CFLAGS="${CFLAGS} -Wno-deprecated-declarations -Wno-unknown-attributes -Wno-typedef-redefinition"
    LDFLAGS="-L${TOOLS_PATH}/deps/lib"
    EXTRA_CONFIGURE_FLAGS="--enable-aqua=yes --without-x"
else
    EXTRA_CONFIGURE_FLAGS="--x-includes=${TOOLS_PATH}/deps/include --x-libraries=${TOOLS_PATH}/deps/lib"
fi

CFLAGS="${CFLAGS}" CPPFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}" ./configure \
    --build=${BUILD_TRIPLE} \
    --host=${TARGET_TRIPLE} \
    --prefix=/tools/deps \
    --with-tcl=${TOOLS_PATH}/deps/lib \
    --enable-shared=no \
    --enable-threads \
    ${EXTRA_CONFIGURE_FLAGS}

# Remove wish, since we don't need it.
if [ "${PYBUILD_PLATFORM}" != "macos" ]; then
    sed -i 's/all: binaries libraries doc/all: libraries/' Makefile
    sed -i 's/install-binaries: $(TK_STUB_LIB_FILE) $(TK_LIB_FILE) ${WISH_EXE}/install-binaries: $(TK_STUB_LIB_FILE) $(TK_LIB_FILE)/' Makefile
fi

# For some reason musl isn't link libXau and libxcb. So we hack the Makefile
# to do what we want.
if [ "${CC}" = "musl-clang" ]; then
    sed -i 's/-ldl  -lpthread /-ldl  -lpthread -lXau -lxcb/' tkConfig.sh
    sed -i 's/-lpthread $(X11_LIB_SWITCHES) -ldl  -lpthread/-lpthread $(X11_LIB_SWITCHES) -ldl  -lpthread -lXau -lxcb/' Makefile
fi

make -j ${NUM_CPUS}
touch wish
make -j ${NUM_CPUS} install DESTDIR=${ROOT}/out
make -j ${NUM_CPUS} install-private-headers DESTDIR=${ROOT}/out

# For some reason libtk*.a have weird permissions. Fix that.
chmod 644 /${ROOT}/out/tools/deps/lib/libtk*.a

rm ${ROOT}/out/tools/deps/bin/wish*
