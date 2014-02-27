// Copyright 2014 George King.
// Permission to use this file is granted in opticon/license.txt.


#import "AppDelegate.h"


int main(int argc, const char * argv[]) {
  
  @autoreleasepool {
    [NSApplication sharedApplication]; // initialize the app

    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular]; // necessary?
    [NSApp activateIgnoringOtherApps:NO]; // necessary?
    

    // app delegate saved to global so that object is retained for lifetime of app
    appDelegate = [AppDelegate new];
    [NSApp setDelegate:appDelegate];
    
    // process name: currently named after native executable.
    NSProcessInfo* processInfo = [NSProcessInfo processInfo];
    NSString* processName = [[processInfo.arguments objectAtIndex:0] lastPathComponent];
    [processInfo setProcessName:processName];

    // menu bar
    NSMenuItem* quitItem =
    [[NSMenuItem alloc] initWithTitle:[@"Quit " stringByAppendingString:processName]
                               action:@selector(terminate:)
                        keyEquivalent:@"q"];
    
    NSMenu* appMenu = [NSMenu new];
    [appMenu addItem:quitItem];
    
    NSMenuItem *appMenuBarItem = [NSMenuItem new];
    [appMenuBarItem setSubmenu:appMenu];
    
    NSMenu *menuBar = [NSMenu new];
    [menuBar addItem:appMenuBarItem];
    [NSApp setMainMenu:menuBar];
    
    [NSApp run];
  }
}
