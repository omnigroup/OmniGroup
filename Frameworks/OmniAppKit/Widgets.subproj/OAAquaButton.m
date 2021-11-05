// Copyright 2000-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAAquaButton.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/NSImage-OAExtensions.h>

RCS_ID("$Id$")

@implementation OAAquaButton

- (id)initWithFrame:(NSRect)frameRect;
{
    if (!(self = [super initWithFrame:frameRect]))
        return nil;

    [self setButtonType:NSButtonTypeMomentaryLight];
    [self setImagePosition:NSImageOnly];

    if (@available(macOS 11, *)) {
#if DEBUG
        NSLog(@"should move from using OAAquaButtons, as they don't take a newer NSAppearance-based view of our world");
#endif
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_controlTintChanged:) name:NSControlTintDidChangeNotification object:nil];
#pragma clang diagnostic pop
    }
    
    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

//
// NSButton subclass
//

- (void)setState:(NSInteger)value;
{
    [super setState:value];
    [self _setButtonImages];
}

- (void)setImageName:(NSString *)anImageName inBundle:(NSBundle *)aBundle;
{
    clearImage = OAImageNamed(anImageName, aBundle);
    aquaImage = OAImageNamed([anImageName stringByAppendingString:OAAquaImageTintSuffix], aBundle);
    graphiteImage = OAImageNamed([anImageName stringByAppendingString:OAGraphiteImageTintSuffix], aBundle);
    
    [self _setButtonImages];
}

#pragma mark - Private

- (void)_controlTintChanged:(NSNotification *)notification;
{
    [self _setButtonImages];
}

// Sets the image and alternate image as appropriate (if state != 0, image is set to the "On" image)
- (void)_setButtonImages;
{
    if ([self state] == 0) {
        [self setImage:clearImage];
        [self setAlternateImage:[self _imageForCurrentControlTint]];
    } else {
        [self setImage:[self _imageForCurrentControlTint]];
        [self setAlternateImage:clearImage];
    }
}

// Returns the "On" image for the current control tint
- (NSImage *)_imageForCurrentControlTint;
{
    return ([NSColor currentControlTint] == NSGraphiteControlTint ? graphiteImage : aquaImage);
}

@end
