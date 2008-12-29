// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Widgets.subproj/OAFontView.h 68913 2005-10-03 19:36:19Z kc $

#import <AppKit/NSView.h>

@class NSString;
@class NSFont;

#import <AppKit/NSNibDeclarations.h> // For IBOutlet and IBAction

@interface OAFontView : NSView
{
    IBOutlet id delegate;

    NSFont *font;
    NSString *fontDescription;
    NSSize textSize;
}

- (void) setDelegate: (id) aDelegate;
- (id) delegate;

- (NSFont *)font;
- (void)setFont:(NSFont *)newFont;

- (IBAction)setFontUsingFontPanel:(id)sender;

@end


@interface NSObject (OAFontViewDelegate)
- (BOOL)fontView:(OAFontView *)aFontView shouldChangeToFont:(NSFont *)newFont;
- (void)fontView:(OAFontView *)aFontView didChangeToFont:(NSFont *)newFont;

// We pass along the NSFontPanel delegate message, adding in the last font view to have been sent -setFontUsingFontPanel:
- (BOOL)fontView:(OAFontView *)aFontView fontManager:(id)sender willIncludeFont:(NSString *)fontName;
@end
