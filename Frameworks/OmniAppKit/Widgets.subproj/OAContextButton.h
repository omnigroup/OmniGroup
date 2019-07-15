// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSButton.h>
#import <AppKit/NSNibDeclarations.h>

@class NSMenu;
@protocol OAContextControlDelegate;

@interface OAContextButtonCell : NSButtonCell
@end

@interface OAContextButton : NSButton

+ (NSImage *)actionImage;
+ (NSImage *)miniActionImage;

@property (nonatomic,weak) IBOutlet id <OAContextControlDelegate> delegate;

// If YES (the default), clicking on the button will show a menu (via private action). If NO, the button will act like a normal button (and you should set a target/action on it).
@property(nonatomic,assign) BOOL showsMenu;

- (BOOL)validate;
- (NSMenu *)locateActionMenu;

@end
