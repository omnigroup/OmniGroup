// Copyright 2002-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>

#define OIInspectorResizerWidth (11.0f)

/*"
 This class exists because our inspector windows don't want title bars (instead they have special views, a role handled by OIInspectorHeaderView) but some of them need to be resizable. However, making a window resizable forces it to have a standard title bar. So we instead use this widget to handle resizing for our inspector windows.
 Unfortunately, this has some negative side-effects: the NSView inLiveResize stuff doesn't work because the window isn't doing the resizing, instead we are doing the resizing. To get around this, we define some methods that we will call on the window (if it implements them) to inform it when we begin and end a resizing operation. OIInspectorWindow implements these methods to inform its delegate, the inspector controller, which then informs its inspector group, allowing the group to know when resizing begins and ends, in order to do any positioning/resizing required for other inspector windows in the group.
"*/
@interface OIInspectorResizer : NSView 
@end


@interface NSWindow (OIInspectorResizer)
- (void)resizerWillBeginResizing:(OIInspectorResizer *)resizer;
- (void)resizerDidFinishResizing:(OIInspectorResizer *)resizer;
@end
