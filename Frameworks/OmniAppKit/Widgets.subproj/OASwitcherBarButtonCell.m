// Copyright 2002-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OASwitcherBarButtonCell.h"

#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/OAAquaButton.h>
#import <OmniAppKit/NSImage-OAExtensions.h>

RCS_ID("$Id$");

static BOOL ImagesSetup = NO;
static BOOL BlueImagesSetup = NO;
static BOOL GraphiteImagesSetup = NO;
static NSImage *FillImage[7];
static NSImage *CapLeftImage[7];
static NSImage *CapRightImage[7];
static NSImage *DividerLeftImage[7];
static NSImage *DividerRightImage[7];

@interface OASwitcherBarButtonCell (Private)
+ (void)setupImages;
+ (void)setupBlueImages;
+ (void)setupGraphiteImages;
@end

@implementation OASwitcherBarButtonCell

// API

- (void)setCellLocation:(OASwitcherBarCellLocation)location;
{
    cellLocation = location;
}


// NSCell subclass

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
{
    BOOL isSelected;
    int tintHighlightIndex;
    NSImage *leftImage, *fillImage, *rightImage;
    NSRect leftImageFrame, fillImageFrame, rightImageFrame;
        
    OBASSERT([controlView isKindOfClass:[NSMatrix class]]);

    NSControlTint controlTint = [NSColor currentControlTint];
    if (controlTint == NSGraphiteControlTint && !GraphiteImagesSetup)
        [isa setupGraphiteImages];
    else if (controlTint == NSBlueControlTint && !BlueImagesSetup)
        [isa setupBlueImages];

    if (!ImagesSetup) // shared images
        [isa setupImages];

//#warning RDR: Having trouble putting together on/off state and highlight state the right way; see comment.
    // Currently, when you mouseDown, the cell turns dark blue regardless of whether it was blue or gray before. If you switch the "isSelected =" lines below, the cell turns dark gray regardless of what color it was before. It's supposed to turn dark blue if it was blue, and dark gray if it was gray. Tried messing around with various wasy to get it to do the right thing, including implementing -highlight:withFrame:inView:, but without any luck -- ended up with some double-drawing instead (resulting in an undesirable dark shadow).
    isSelected = ([(NSMatrix *)[self controlView] selectedCell] == self);
    //isSelected = ([self state] == NSOnState);
    if (isSelected && ![[controlView window] isKeyWindow])
        tintHighlightIndex = 6;
    else
        switch (controlTint) { // check  the setupImages methods below to see what each array index maps to
            case NSGraphiteControlTint:
                if (!isSelected)
                    tintHighlightIndex = [self isHighlighted] ? 1 : 0;
                else
                    tintHighlightIndex = [self isHighlighted] ? 5 : 4;
                break;
            case NSBlueControlTint:
            default:
                if (!isSelected)
                    tintHighlightIndex = [self isHighlighted] ? 1 : 0;
                else
                    tintHighlightIndex = [self isHighlighted] ? 3 : 2;
                break;
        }

    switch (cellLocation) {
        case OASwitcherBarLeft:
            leftImage = CapLeftImage[tintHighlightIndex];
            rightImage = DividerRightImage[tintHighlightIndex];
            break;
        case OASwitcherBarRight:
            leftImage = DividerLeftImage[tintHighlightIndex];
            rightImage = CapRightImage[tintHighlightIndex];
            break;
        case OASwitcherBarMiddle:
        default:
            leftImage = DividerLeftImage[tintHighlightIndex];
            rightImage = DividerRightImage[tintHighlightIndex];
    }
    fillImage = FillImage[tintHighlightIndex];
    
    leftImageFrame = NSMakeRect(NSMinX(cellFrame), NSMinY(cellFrame),
                                [leftImage size].width, NSHeight(cellFrame));
    rightImageFrame = NSMakeRect(NSMaxX(cellFrame) - [rightImage size].width, NSMinY(cellFrame),
                                 [rightImage size].width, NSHeight(cellFrame));
    fillImageFrame = NSMakeRect(NSMinX(cellFrame) + leftImageFrame.size.width, NSMinY(cellFrame),
                                NSWidth(cellFrame) - (NSWidth(leftImageFrame) + NSWidth(rightImageFrame)), NSHeight(cellFrame));

    [leftImage drawFlippedInRect:leftImageFrame operation:NSCompositeSourceOver fraction:1.0];
    [fillImage drawFlippedInRect:fillImageFrame operation:NSCompositeSourceOver fraction:1.0];
    [rightImage drawFlippedInRect:rightImageFrame operation:NSCompositeSourceOver fraction:1.0];
    
    [self drawInteriorWithFrame:cellFrame inView:controlView];
}

/*
- (void)highlight:(BOOL)flag withFrame:(NSRect)cellFrame inView:(NSView *)controlView;
{
// maybe fix the problem here? how to do it without darkening partially transparent regions?
}
*/

@end

@implementation OASwitcherBarButtonCell (NotificationsDelegatesDatasources)
@end

@implementation OASwitcherBarButtonCell (Private)

+ (void)setupImages; //shared images between aqua and graphite appearance schemes
{
    NSBundle *bundle = [self bundle];
    
    // clear, normal
    FillImage[0] = [[NSImage imageNamed:@"SwitcherBar_Fill" inBundle:bundle] retain];
    CapLeftImage[0] = [[NSImage imageNamed:@"SwitcherBar_CapLeft" inBundle:bundle] retain];
    CapRightImage[0] = [[NSImage imageNamed:@"SwitcherBar_CapRight" inBundle:bundle] retain];
    DividerLeftImage[0] = [[NSImage imageNamed:@"SwitcherBar_DivLeft" inBundle:bundle] retain];
    DividerRightImage[0] = [[NSImage imageNamed:@"SwitcherBar_DivRight" inBundle:bundle] retain];
    // clear, pressed
    FillImage[1] = [[NSImage imageNamed:@"SwitcherBar_Fill_Press" inBundle:bundle] retain];
    CapLeftImage[1] = [[NSImage imageNamed:@"SwitcherBar_CapLeft_Press" inBundle:bundle] retain];
    CapRightImage[1] = [[NSImage imageNamed:@"SwitcherBar_CapRight_Press" inBundle:bundle] retain];
    DividerLeftImage[1] = [[NSImage imageNamed:@"SwitcherBar_DivLeft_Press" inBundle:bundle] retain];
    DividerRightImage[1] = [[NSImage imageNamed:@"SwitcherBar_DivRight_Press" inBundle:bundle] retain];
    // window is not key
    FillImage[6] = [[NSImage imageNamed:@"SwitcherBar_Fill_Select" inBundle:bundle] retain];
    CapLeftImage[6] = [[NSImage imageNamed:@"SwitcherBar_CapLeft_Select" inBundle:bundle] retain];
    CapRightImage[6] = [[NSImage imageNamed:@"SwitcherBar_CapRight_Select" inBundle:bundle] retain];
    DividerLeftImage[6] = [[NSImage imageNamed:@"SwitcherBar_DivLeft_Select" inBundle:bundle] retain];
    DividerRightImage[6] = [[NSImage imageNamed:@"SwitcherBar_DivRight_Select" inBundle:bundle] retain];
    
    ImagesSetup = YES; // that's a whole damn lot of images.
}

+ (void)setupBlueImages;
{
    NSBundle *bundle = [self bundle];

    // blue, normal
    FillImage[2] = [[NSImage imageNamed:@"SwitcherBar_Fill_A" inBundle:bundle] retain];
    CapLeftImage[2] = [[NSImage imageNamed:@"SwitcherBar_CapLeft_A" inBundle:bundle] retain];
    CapRightImage[2] = [[NSImage imageNamed:@"SwitcherBar_CapRight_A" inBundle:bundle] retain];
    DividerLeftImage[2] = [[NSImage imageNamed:@"SwitcherBar_DivLeft_A" inBundle:bundle] retain];
    DividerRightImage[2] = [[NSImage imageNamed:@"SwitcherBar_DivRight_A" inBundle:bundle] retain];
    // blue, pressed
    FillImage[3] = [[NSImage imageNamed:@"SwitcherBar_Fill_Press_A" inBundle:bundle] retain];
    CapLeftImage[3] = [[NSImage imageNamed:@"SwitcherBar_CapLeft_Press_A" inBundle:bundle] retain];
    CapRightImage[3] = [[NSImage imageNamed:@"SwitcherBar_CapRight_Press_A" inBundle:bundle] retain];
    DividerLeftImage[3] = [[NSImage imageNamed:@"SwitcherBar_DivLeft_Press_A" inBundle:bundle] retain];
    DividerRightImage[3] = [[NSImage imageNamed:@"SwitcherBar_DivRight_Press_A" inBundle:bundle] retain];
    
    BlueImagesSetup = YES;
}

+ (void)setupGraphiteImages;
{
    NSBundle *bundle = [self bundle];

    // graphite, normal
    FillImage[4] = [[NSImage imageNamed:@"SwitcherBar_Fill_G" inBundle:bundle] retain];
    CapLeftImage[4] = [[NSImage imageNamed:@"SwitcherBar_CapLeft_G" inBundle:bundle] retain];
    CapRightImage[4] = [[NSImage imageNamed:@"SwitcherBar_CapRight_G" inBundle:bundle] retain];
    DividerLeftImage[4] = [[NSImage imageNamed:@"SwitcherBar_DivLeft_G" inBundle:bundle] retain];
    DividerRightImage[4] = [[NSImage imageNamed:@"SwitcherBar_DivRight_G" inBundle:bundle] retain];
    // graphite, pressed
    FillImage[5] = [[NSImage imageNamed:@"SwitcherBar_Fill_Press_G" inBundle:bundle] retain];
    CapLeftImage[5] = [[NSImage imageNamed:@"SwitcherBar_CapLeft_Press_G" inBundle:bundle] retain];
    CapRightImage[5] = [[NSImage imageNamed:@"SwitcherBar_CapRight_Press_G" inBundle:bundle] retain];
    DividerLeftImage[5] = [[NSImage imageNamed:@"SwitcherBar_DivLeft_Press_G" inBundle:bundle] retain];
    DividerRightImage[5] = [[NSImage imageNamed:@"SwitcherBar_DivRight_Press_G" inBundle:bundle] retain];
    
    GraphiteImagesSetup = YES;
}


@end
