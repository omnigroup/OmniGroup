// Copyright 2003-2005, 2008, 2010, 2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAPatternColorPicker.h"

#import <OmniAppKit/NSBundle-OAExtensions.h>
#import <OmniAppKit/NSImage-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$");

/*
 For this color picker to get installed, add a copy-files build phase to your application that puts in it 'Resources/ColorPickers'

 Originally I added a custom mode 'mode' bit, but it didn't seem to do anything useful.  Maybe they just remember the current mode and restore it when you get reactivated.

 Future:

 - Create a OAPatternColor subclass of NSColor
 - Store the original image data (important for PDF, I think)
 - Store an affine transform and provide UI for setting it.
 - Implement -set on our color to create a CGPattern
 - Add a class method (in OmniOutliner's OODrawing.m) to pin the pattern origin to a particular spot
 - Add archive/unarchive via our XML NSColor extensions to save all the extra state.
 - Possibly switch to an archiving format where we attach the original image data as a NSFileWrapper attachment.  Consider the case of OO3 exporting to HTML, the XSL plugin has no easy way of forming a image from a blob of hex data (possibly a data: URL...).
 
 */

@interface OAPatternColorPicker ()

@property (nonatomic, retain) IBOutlet NSView *view;
@property (nonatomic, assign) IBOutlet NSImageView *imageView;

@end

@implementation OAPatternColorPicker

- (void)dealloc;
{
    [_view release];
    [super dealloc];
}

//
// NSColorPicker subclass
//

- (NSImage *)provideNewButtonImage;
{
    return [NSImage imageNamed:@"OAPatternColorPicker" inBundle:OMNI_BUNDLE];
}

//
// NSColorPickingCustom protocol
//
- (BOOL)supportsMode:(NSColorPanelMode)mode;
{
#ifdef DEBUG_bungi
    // I've never seen this get called.
    NSLog(@"%s: mode = 0x%lx\n", __FUNCTION__, mode);
#endif
    return YES;
}

- (NSColorPanelMode)currentMode;
{
    return NSRGBModeColorPanel;
}

// "Yes" on very first call (load your .nibs etc when "YES").
- (NSView *)provideNewView:(BOOL)initialRequest;  // "Yes" on very first call.
{
    if (initialRequest) {
        OBASSERT(!_view);
        [[OAPatternColorPicker bundle] loadNibNamed:@"OAPatternColorPicker.nib" owner:self options:nil];
    }
    OBASSERT(_view);
    return _view;
}

- (void)setColor:(NSColor *)newColor;
{
    // This will get called with whatever the currently selected color in the well is when we become the active picker.  The color will NOT necessarily be one a pattern color; we need to check that.  If it isn't a color we like, we should just empty out our UI.
    if (![[newColor colorSpaceName] isEqualToString:NSPatternColorSpace]) {
        [self.imageView setImage:nil];
        return;
    }

    NSImage *image = [newColor patternImage];
    [self.imageView setImage:image];
}

//
// Outlets
//

@synthesize view = _view;
@synthesize imageView = _nonretained_imageView;

//
// Actions
//

- (IBAction)imageChanged:(id)sender;
{
    NSImage *image = [self.imageView image];
    if (!image)
        return;

    NSColor *color = [NSColor colorWithPatternImage:image];
    [[self colorPanel] setColor:color];
}

@end
