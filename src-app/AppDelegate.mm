// Copyright 2014 George King.
// Permission to use this file is granted in opticon/license.txt.


#import "AppDelegate.h"


AppDelegate* appDelegate;


@interface AppDelegate ()

@property (nonatomic) FILE* logFile;

@end


@implementation AppDelegate


CGEventRef eventTapped(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void* ctx) {
  // event tap callback.
  switch (type) {
    case kCGEventMouseMoved: break;
    case kCGEventLeftMouseDragged: break;
    case kCGEventRightMouseDragged: break;
    case kCGEventNull:
    case kCGEventLeftMouseDown:
    case kCGEventLeftMouseUp:
    case kCGEventRightMouseDown:
    case kCGEventRightMouseUp:
    case kCGEventKeyDown:
    case kCGEventKeyUp:
    case kCGEventFlagsChanged:
    case kCGEventScrollWheel:
    case kCGEventTabletPointer:
    case kCGEventTabletProximity:
    case kCGEventOtherMouseDown:
    case kCGEventOtherMouseUp:
    case kCGEventOtherMouseDragged:
      NSLog(@"event: %d", type);
  }
  return NULL;
}


- (void)workspaceNote:(NSNotification*)note {
  // workspace notification callback.
  NSRunningApplication* app = note.userInfo[NSWorkspaceApplicationKey];
  NSLog(@"note: %@: %@", note.name, app.bundleIdentifier);
}


- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary*)change
                       context:(void *)context {
  if ([keyPath isEqualToString:@"frontmostApplication"]) {
    NSLog(@"frontmostApplication %@", change);
  }
  else if ([keyPath isEqualToString:@"menuBarOwningApplication"]) {
    NSLog(@"menuBarOwningApplication %@", change);
  }
  else {
    NSLog(@"unknown observation: %@", keyPath);
  }
}


- (void)addNote:(NSString*)name {
  auto wsnc = [[NSWorkspace sharedWorkspace] notificationCenter];
  [wsnc addObserver:self selector:@selector(workspaceNote:) name:name object:nil];
}


- (void)openDB {
  //auto path = @"~/opticon.sqlite3".stringByExpandingTildeInPath;
}


- (void)setupMonitors {

  [self addNote:NSWorkspaceWillLaunchApplicationNotification];
  [self addNote:NSWorkspaceDidLaunchApplicationNotification];
  [self addNote:NSWorkspaceDidTerminateApplicationNotification];
  [self addNote:NSWorkspaceDidHideApplicationNotification];
  [self addNote:NSWorkspaceDidUnhideApplicationNotification];
  [self addNote:NSWorkspaceDidActivateApplicationNotification];
  [self addNote:NSWorkspaceDidDeactivateApplicationNotification];

  auto opts = NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld;
  [[NSWorkspace sharedWorkspace] addObserver:self forKeyPath:@"frontmostApplication" options:opts context:NULL];
  [[NSWorkspace sharedWorkspace] addObserver:self forKeyPath:@"menuBarOwningApplication" options:opts context:NULL];

  CGEventMask eventMask = 0
  | CGEventMaskBit(kCGEventLeftMouseDown)
  | CGEventMaskBit(kCGEventLeftMouseUp)
  | CGEventMaskBit(kCGEventRightMouseDown)
  | CGEventMaskBit(kCGEventRightMouseUp)
  | CGEventMaskBit(kCGEventMouseMoved)
  | CGEventMaskBit(kCGEventLeftMouseDragged)
  | CGEventMaskBit(kCGEventRightMouseDragged)
  | CGEventMaskBit(kCGEventKeyDown)
  | CGEventMaskBit(kCGEventKeyUp)
  | CGEventMaskBit(kCGEventFlagsChanged)
  | CGEventMaskBit(kCGEventScrollWheel)
  | CGEventMaskBit(kCGEventTabletPointer)
  | CGEventMaskBit(kCGEventTabletProximity)
  | CGEventMaskBit(kCGEventOtherMouseDown)
  | CGEventMaskBit(kCGEventOtherMouseUp)
  | CGEventMaskBit(kCGEventOtherMouseDragged)
  ;
  
  CFMachPortRef tap =
  CGEventTapCreate(kCGAnnotatedSessionEventTap, // tap events as they flow into applications (as late as possible).
                   kCGTailAppendEventTap, // insert tap after any existing filters.
                   kCGEventTapOptionListenOnly, // passive tap.
                   eventMask,
                   eventTapped,
                   NULL);
  
  NSLog(@"tap: %p; enabled: %d", tap, CGEventTapIsEnabled(tap));
  
  CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
  CFRunLoopAddSource([[NSRunLoop currentRunLoop] getCFRunLoop], source, kCFRunLoopCommonModes);
  CFRelease(source);
  
  // key down/up events are only delivered if the current process is running as root,
  // or the process has been approved as trusted for accessibility.
  // this is set in System Preferences -> Security and Privacy -> Privacy -> Accessibility.
  auto options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
  BOOL isTrusted = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
  NSLog(@"accessibility trusted: %d", isTrusted);
}



- (void)applicationDidFinishLaunching:(NSNotification*)note {
  [self setupMonitors];
}


@end
