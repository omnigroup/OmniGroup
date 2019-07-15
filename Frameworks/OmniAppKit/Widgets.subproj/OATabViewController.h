// Copyright 1998-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class NSDocument, NSTabView, NSWindow, NSWindowController;

#import <AppKit/NSNibDeclarations.h>

@interface OATabViewController : OFObject
{
    IBOutlet NSWindow *scratchWindow;
    IBOutlet NSWindowController *windowController;
    
    struct {
        unsigned int alreadyAwoke:1;
    } flags;
}


// API
- (NSString *)label;

- (NSDocument *)document;

- (void)refreshUserInterface;

@end

@interface OATabViewController (FriendClassesOnly)
- (NSWindow *)scratchWindow;
@end
