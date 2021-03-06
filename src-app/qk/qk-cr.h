// Copyright 2013 George King.
// Permission to use this file is granted in license-libqk.txt (ISC License).

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif

#import "qk-macros.h"
#import "QKPixFmt.h"

#if TARGET_OS_IPHONE

#define CRView UIView
#define CRFont UIFont
#define CRColor UIColor

typedef UIViewAutoresizing CRFlex;
typedef UILayoutConstraintAxis UIAxis; // TODO: rename CRAxis.
typedef UIEdgeInsets CREdgeInsets;

#else

#define CRView NSView
#define CRFont NSFont
#define CRColor NSColor

typedef NSUInteger UIViewAutoresizing; // TODO: rename CRFlex.
typedef NSLayoutConstraintOrientation UIAxis; // TODO: rename CRAxis.
typedef NSLayoutPriority UILayoutPriority; // TODO: rename CRLayoutPriority.
typedef NSEdgeInsets CREdgeInsets;

#define NSTextAlignmentLeft NSLeftTextAlignment
#define NSTextAlignmentRight NSRightTextAlignment
#define NSTextAlignmentCenter NSCenterTextAlignment
#define NStextAlignmentJustified NSJustifiedTextAlignment
#define NSTextAlignmentNatural NSNaturalTextAlignment

#endif



typedef enum {
  QKVertAlignmentTop,
  QKVertAlignmentCenter,
  QKVertAlignmentBottom,
} QKVertAlignment;


typedef enum {
  QKLayoutNone,
  QKLayoutHorizontal,
  QKLayoutVertical,
} QKLayoutDirection; // TODO: replace with CRAxis?


extern const CGSize CGSizeUnit;
extern const CGRect CGRectUnit;
extern const CGRect CGRect256;


extern CGColorSpaceRef QKColorSpaceRGB();
extern CGColorSpaceRef QKColorSpaceLum();
extern CGColorSpaceRef QKColorSpaceDev(BOOL rgb);
extern CGColorSpaceRef QKColorSpaceWithFormat(QKPixFmt format);


#if OBJCPP

NSMutableDictionary* strAttrs(CRFont* font = nil,
                              CRColor* color = nil,
                              NSTextAlignment align = NSTextAlignmentNatural);


static inline CGPoint add(CGPoint a, CGPoint b) {
  return CGPointMake(a.x + b.x, a.y + b.y);
}


static inline CGSize add(CGSize a, CGSize b) {
  return CGSizeMake(a.width + b.width, a.height + b.height);
}


static inline CGPoint sub(CGPoint a, CGPoint b) {
  return CGPointMake(a.x - b.x, a.y - b.y);
}


static inline CGSize sub(CGSize a, CGSize b) {
  return CGSizeMake(a.width - b.width, a.height - b.height);
}


static inline CGPoint mul(CGPoint v, CGFloat s) {
  return CGPointMake(v.x * s, v.y * s);
}


static inline CGSize mul(CGSize v, CGFloat s) {
  return CGSizeMake(v.width * s, v.height * s);
}


static inline CGRect mul(CGRect r, CGFloat s) {
  return (CGRect){ mul(r.origin, s), mul(r.size, s) };
}

static inline CGPoint clamp(CGPoint p, CGSize s) {
  return CGPointMake(CLAMP(p.x, 0, s.width), CLAMP(p.y, 0, s.height));
}


static inline CGRect inset(CGRect r, CREdgeInsets i) {
  r.origin.x += i.left;
  r.origin.y += i.top;
  r.size.width -= i.left + i.right;
  r.size.height -= i.top  + i.bottom;
  return r;
}


static inline CGFloat CGSizeAspect(CGSize s, CGFloat eps) {
  if (s.width < eps || s.height < eps) {
    return 1;
  }
  return s.width / s.height;
}


static inline CGRect CGRectWithOE(CGPoint origin, CGPoint end) {
  return CGRectMake(origin.x, origin.y, end.x - origin.x, end.y - origin.y);
}


static inline CGRect CGRectWithS(CGSize size) {
  return (CGRect){ CGPointZero, size };
}


static inline CGRect CGRectWithWH(CGFloat w, CGFloat h) {
  return CGRectMake(0, 0, w, h);
}


// left, bottom, size
static inline CGRect CGRectWithLBS(CGFloat l, CGFloat b, CGSize s) {
  return CGRectMake(l, b - s.height, s.width, s.height);
}


// center-x, bottom, size
static inline CGRect CGRectWithCBS(CGFloat cx, CGFloat b, CGSize s) {
  return CGRectMake(cx - s.width * .5, b - s.height, s.width, s.height);
}


// right, bottom, size
static inline CGRect CGRectWithRBS(CGFloat r, CGFloat b, CGSize s) {
  return CGRectMake(r - s.width, b - s.height, s.width, s.height);
}


static inline CGRect CGRectExpand(CGRect r, CGFloat padX, CGFloat padY) {
  return CGRectMake(r.origin.x - padX, r.origin.y - padY, r.size.width + padX * 2, r.size.height + padY * 2);
}


static inline CGRect CGRectSurround(CGPoint center, CGFloat padX, CGFloat padY) {
  return CGRectMake(center.x - padX, center.y - padY, padX * 2, padY * 2);
}


CGSize CGSizeWithAspectEnclosingSize(CGFloat aspect, CGSize s);
CGSize CGSizeWithAspectEnclosedBySize(CGFloat aspect, CGSize s);
CGRect CGRectWithAspectEnclosingRect(CGFloat aspect, CGRect r);
CGRect CGRectWithAspectEnclosedByRect(CGFloat aspect, CGRect r);


#endif // __cplusplus

