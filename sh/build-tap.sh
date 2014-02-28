clang \
-x objective-c++ \
-arch x86_64 \
-std=gnu++11 \
-stdlib=libc++ \
-fobjc-arc \
-fpascal-strings \
-fstrict-aliasing \
-fvisibility-inlines-hidden \
-Weverything \
-Wno-implicit-atomic-properties \
-mmacosx-version-min=10.9 \
-isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.9.sdk \
-I/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/include 
-DDEBUG=1 \
-O0 \
-g \
\
-o opticon-tap \
src-tap/opticon-tap.mm
