// Copyright 2002-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSPanel.h>

@interface OIInspectorWindow : NSPanel
@end

@protocol OIInspectorWindowDelegate <NSWindowDelegate>
- (void)windowWillBeginResizing:(NSWindow *)window;
- (void)windowDidFinishResizing:(NSWindow *)window;
- (NSRect)windowWillResizeFromFrame:(NSRect)fromRect toFrame:(NSRect)toRect;
@end
