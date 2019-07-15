// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSView.h>

@class NSString;
@class NSFont;

#import <AppKit/NSNibDeclarations.h> // For IBOutlet and IBAction

@interface OAFontView : NSView

@property(nonatomic,weak) id delegate;

@property(nonatomic,strong) NSFont *font;
@property(nonatomic,readonly) NSString *fontDescription;

- (IBAction)setFontUsingFontPanel:(id)sender;

@end


@interface NSObject (OAFontViewDelegate)
- (BOOL)fontView:(OAFontView *)aFontView shouldChangeToFont:(NSFont *)newFont;
- (void)fontView:(OAFontView *)aFontView didChangeToFont:(NSFont *)newFont;

- (IBAction)changeFontFamily:(id)sender;

@end
