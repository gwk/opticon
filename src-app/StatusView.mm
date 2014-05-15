// Copyright 2014 George King.
// Permission to use this file is granted in license-opticon.txt (ISC license).

#import "qk-macros.h"
#import "qk-log.h"
#import "CRView.h"
#import "QKTextLayer.h"
#import "StatusView.h"


@interface StatusView ()
@end



@implementation StatusView


- (void)mouseDown:(NSEvent*)event {
  self.isLit = YES;
}


- (void)mouseUp:(NSEvent*)event {
  self.isLit = NO;
  [appDelegate toggleIsLoggingEnabled];
}


- (void)rightMouseDown:(NSEvent*)event {
  [appDelegate updateMenuDisplayed];
}


- (void)rightMouseUp:(NSEvent*)event {
}


- (instancetype)initWithFrame:(CGRect)frame {
  INIT(super initWithFrame:frame);
  return self;
}


- (void)drawRect:(NSRect)rect {
  if (!_richText) return;
  CGRect b = self.bounds;
  CGSize s = self.bounds.size;
  auto ctx = CRCurrentCtx();
  CGContextSaveGState(ctx);
  CGContextClearRect(ctx, b);
  if (_isLit) {
    CGContextSetFillColorWithColor(ctx, [CRColor r:0 g:.5 b:1].CGColor);
    CGContextFillRect(ctx, b);
  }
  auto line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)_richText);
  CGRect tb = CTLineGetImageBounds(line, ctx);
  CGSize ts = tb.size;
  
  CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
  CGContextTranslateCTM(ctx, (s.width - ts.width) * .5 - 1, (s.height - ts.height) * .5 - 1); // x:-1, y:
  // this is weird - even though the text is correct, the text rect is off on the secondary (non-active) menu bar.
  //CGContextSetFillColorWithColor(ctx, [CRColor r].CGColor);
  //CGContextFillRect(ctx, tb);
  CTLineDraw(line, ctx);
  CGContextRestoreGState(ctx);
}


DEF_SET_NEEDS_DISPLAY(NSAttributedString*, richText, RichText);
DEF_SET_NEEDS_DISPLAY(BOOL, isLit, IsLit);


@end
