// Copyright 2014 George King.
// Permission to use this file is granted in license-opticon.txt (ISC license).

#import "prefix.pch"

@interface AppDelegate : NSObject <NSApplicationDelegate>

- (void)toggleIsLoggingEnabled;
- (void)updateMenuDisplayed;

@end

extern AppDelegate* appDelegate;
