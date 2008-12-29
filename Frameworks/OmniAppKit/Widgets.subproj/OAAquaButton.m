// Copyright 2000-2007 Omni Development, Inc.  All rights reserved.
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

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Widgets.subproj/OAAquaButton.m 92241 2007-10-03 19:33:24Z wiml $")

@interface OAAquaButton (PrivateAPI)
- (void)_setButtonImages;
- (NSImage *)_imageForCurrentControlTint;
@end

NSString *OAAquaButtonAquaImageSuffix = @"Aqua";
NSString *OAAquaButtonGraphiteImageSuffix = @"Graphite";
NSString *OAAquaButtonClearImageSuffix = @"Clear";

@implementation OAAquaButton

- (id)initWithFrame:(NSRect)frameRect;
{
    if (![super initWithFrame:frameRect])
        return nil;

    [self setButtonType:NSMomentaryLightButton];
    [self setImagePosition:NSImageOnly];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_controlTintChanged:) name:NSControlTintDidChangeNotification object:nil];
    
    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [clearImage release];
    [aquaImage release];
    [graphiteImage release];
    
    [super dealloc];
}

//
// NSButton subclass
//

- (void)setState:(int)value;
{
    [super setState:value];
    [self _setButtonImages];
}

- (void)setImageName:(NSString *)anImageName inBundle:(NSBundle *)aBundle;
{
    [clearImage release];
    [aquaImage release];
    [graphiteImage release];
    clearImage = [[NSImage imageNamed:anImageName inBundle:aBundle] retain];
    aquaImage = [[NSImage imageNamed:[anImageName stringByAppendingString:OAAquaButtonAquaImageSuffix] inBundle:aBundle] retain];
    graphiteImage = [[NSImage imageNamed:[anImageName stringByAppendingString:OAAquaButtonGraphiteImageSuffix] inBundle:aBundle] retain];
    
    [self _setButtonImages];
}

@end

@implementation OAAquaButton (PrivateAPI)

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
