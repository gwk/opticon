// Copyright 2012 George King.
// Permission to use this file is granted in license-libqk.txt (ISC License).


#import "qk-macros.h"
#import "NSArray+QK.h"
#import "NSString+QK.h"


@implementation NSString (QK)


+ (instancetype)withFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2) {
  NSString* s;
  va_list args;
  va_start(args, format);
  s = [[self alloc] initWithFormat:format arguments:args];
  va_end(args);
  return s;
}


#pragma mark - UTF


+ (instancetype)withUtf8:(Utf8)string {
  if (!string) {
    return nil;
  }
  return [self stringWithUTF8String:string];
}


+ (instancetype)withUtf32:(Utf32)string {
  ASSERT_WCHAR_IS_UTF32;
  if (!string) {
    return nil;
  }
  int length = 0;
  while (string[length]) length++; // count non-null 4-byte characters.
  return [[self alloc] initWithBytes:string length:length * 4 encoding:NSUTF32LittleEndianStringEncoding];
}


+ (instancetype)withUtf8M:(Utf8M)string free:(BOOL)freeString {
  if (!string) {
    return nil;
  }
  id s = [self stringWithUTF8String:string];
  if (freeString) {
    free(string);
  }
  return s;
}


+ (instancetype)withUtf32M:(Utf32M)string free:(BOOL)freeString {
  if (!string) {
    return nil;
  }
  qk_assert(sizeof(wchar_t) == 4, @"bad wchar size");
  int length = 0;
  while (string[length]) length++; // count non-null 4-byte characters.
  id s = [[self alloc] initWithBytes:string length:length * 4 encoding:NSUTF32LittleEndianStringEncoding];
  if (freeString) {
    free(string);
  }
  return s;
}


- (void*)asUtfNew:(NSStringEncoding)encoding pad:(NSUInteger)pad {
  
  NSUInteger len = [self lengthOfBytesUsingEncoding:encoding];
  
  void* bytes = malloc(len + pad);
  
  NSUInteger len_act;
  NSRange range_left;
  
  [self getBytes:bytes
       maxLength:len
        usedLength:&len_act
        encoding:encoding
         options:0
           range:NSRangeLength(self)
  remainingRange:&range_left];
  
  qk_assert(len_act == len, @"Utf32 buffer filled %lu; expected %lu", (unsigned long)len_act, (unsigned long)len);
  qk_assert(!range_left.length, @"Utf32 buffer could not be filled; terminated at position %lu", (unsigned long)range_left.location);
  
  memset((U8*)bytes + len, 0, pad); // null terminate
  return bytes;
}


- (Utf8)asUtf8 NS_RETURNS_INNER_POINTER {
  return self.UTF8String;
}


- (Utf32)asUtf32 NS_RETURNS_INNER_POINTER {
  // create an autoreleased NSData object; return the bytes inner pointer, which will be released in the same scope.
  return (Utf32)[[NSData dataWithBytesNoCopy:self.asUtf32M
                                      length:(self.length + 1) * 4
                                freeWhenDone:YES] bytes];
}


- (Utf8M)asUtf8M {
  return (Utf8M)[self asUtfNew:NSUTF8StringEncoding pad:1];
}


- (Utf32M)asUtf32M {
  return (Utf32M)[self asUtfNew:NSUTF32LittleEndianStringEncoding pad:4];
}


- (NSData*)asUtf8Data {
  Utf8 s = self.asUtf8;
  return [NSData dataWithBytes:s length:strlen(s)];
}


- (NSData*)asUtf32Data {
  return [NSData dataWithBytes:self.asUtf32 length:self.length * 4];
}


- (NSRange)range {
    return NSRangeMake(0, self.length);
}


#pragma mark - lines


- (Int)lineCount {
  Int c = 0;
  for_in(i, self.length) {
    if ([self characterAtIndex:i] == '\n') {
      c++;
    }
  }
  return c;
}


- (NSString*)numberedLinesFrom:(Int)from {
  NSArray* a = [self componentsSeparatedByString:@"\n"];
  NSArray* an = [a mapIndexed:^(NSString* line, Int index){
    return fmt(@"%3ld: %@", index + from, line);
  }];
  return [an componentsJoinedByString:@"\n"];
}


- (NSString*)numberedLines {
  return [self numberedLinesFrom:1];
}

- (NSString*)numberedLinesFrom0 {
  return [self numberedLinesFrom:0];
}


#pragma mark - split


- (NSArray*)splitBySpace {
    return [self componentsSeparatedByString:@" "];
}


- (NSArray*)splitByWS {
    return [self componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}


- (NSArray*)splitByWSNL {
    return [self componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}


#pragma mark paths


- (void)walkPathDeep:(BlockDoString)block {
  auto enumerator = [[NSFileManager defaultManager] enumeratorAtPath:self];
  NSString* path;
  while ((path = [enumerator nextObject])) {
    block([self stringByAppendingPathComponent:path]);
  }
}


#if TARGET_OS_IPHONE

+ (NSDictionary*)attributesForFont:(UIFont*)font
                         lineBreak:(NSLineBreakMode)lineBreak
                         alignment:(NSTextAlignment)alignment {
  NSMutableParagraphStyle* style = [NSMutableParagraphStyle new];
  style.lineBreakMode = lineBreak;
  style.alignment = alignment;
  return @{NSFontAttributeName: font, NSParagraphStyleAttributeName: style};
}


- (CGSize)sizeForFont:(UIFont*)font
            lineBreak:(NSLineBreakMode)lineBreak
                    w:(CGFloat)w
                    h:(CGFloat)h {
  // note: NSLineBreakModeTruncating* modes indicate single line.
  CGRect r = [self boundingRectWithSize:CGSizeMake(w, h)
                                options:(lineBreak < NSLineBreakByTruncatingHead
                                         ? NSStringDrawingUsesLineFragmentOrigin
                                         : (NSStringDrawingOptions)0)
                             attributes:[NSString attributesForFont:font
                                                          lineBreak:lineBreak
                                                          alignment:NSTextAlignmentLeft]
                                context:nil];
  return CGSizeMake(ceil(r.size.height), ceil(r.size.width));
}


- (CGFloat)widthForFont:(UIFont*)font lineBreak:(NSLineBreakMode)lineBreak w:(CGFloat)w {
  qk_assert(lineBreak >= NSLineBreakByTruncatingHead, @"bad line break mode");
  CGSize s = [self sizeForFont:font lineBreak:lineBreak w:w h:font.lineHeight];
  return s.width;
}


- (CGFloat)heightForFont:(UIFont*)font
               lineBreak:(NSLineBreakMode)lineBreak
                       w:(CGFloat)w
                       h:(CGFloat)h
                 lineMin:(int)lineMin {
  qk_assert(lineMin >= 0, @"invalid lineMin: %d", lineMin);
  CGSize s = [self sizeForFont:font lineBreak:lineBreak w:w h:h];
  return MAX(font.lineHeight * lineMin, s.height);
}


- (CGFloat)heightForFont:(UIFont*)font
               lineBreak:(NSLineBreakMode)lineBreak
                       w:(CGFloat)w
                 lineMin:(int)lineMin
                 lineMax:(int)lineMax {
  qk_assert(lineMax >= lineMin, @"invalid lineMax: %d", lineMax);
  return [self heightForFont:font lineBreak:lineBreak w:w h:font.lineHeight * lineMax lineMin:lineMin];
}


- (void)drawInRect:(CGRect)rect
              font:(UIFont*)font
         lineBreak:(NSLineBreakMode)lineBreak
         alignment:(NSTextAlignment)alignment {
  [self drawInRect:rect
    withAttributes:[NSString attributesForFont:font
                                     lineBreak:lineBreak
                                     alignment:alignment]];
}

#endif


@end


#pragma mark - UTF autorelease


Utf8 Utf8AR(Utf8 string) {
  return [[NSString withUtf8:string] asUtf8];
}


Utf32 Utf32AR(Utf32 string) {
  return [[NSString withUtf32:string] asUtf32];
}


Utf32 Utf32With8(Utf8 string) {
  return [[NSString withUtf8:string] asUtf32];
}


Utf8 Utf8With32(Utf32 string) {
  return [[NSString withUtf32:string] asUtf8];
}


Utf32 Utf32MWith8(Utf8 string) {
  return [[NSString withUtf8:string] asUtf32M];
}


Utf8 Utf8MWith32(Utf32 string) {
  return [[NSString withUtf32:string] asUtf8M];
}

