// Copyright 2011-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OATinyPopUpButton.h>

#import <Cocoa/Cocoa.h>
#import <OmniAppKit/OmniAppKit.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@implementation OATinyPopUpButton

- initWithFrame:(NSRect)frame;
{
    if ((self = [super initWithFrame:frame]) == nil)
        return nil;
    [self setPullsDown:YES]; // set to pull down, so the superclass doesn't munge with our menu items, trying to check one of them and uncheck the rest
    [[self cell] setArrowPosition:NSPopUpNoArrow];
    return self;
}

- initWithCoder:(NSCoder *)coder;
{
    if ((self = [super initWithCoder:coder]) == nil)
        return nil;
    [[self cell] setArrowPosition:NSPopUpNoArrow];
    return self;
}

- (void)setMenu:(NSMenu *)menu;
{
    if ([menu numberOfItems] == 0 || ![[menu itemAtIndex:0] isSeparatorItem]) {
        // NSPopUpButton shows the first item it's title, but this subclass doesn't. To prevent it from vanishing, add a separator item at the top (but in case this is calls more than once for a given menu, check if there is one already).
        NSMenuItem *separator = [NSMenuItem separatorItem];
        [menu insertItem:separator atIndex:0];
    }
    
    [super setMenu:menu];
}

// NSView subclass

#define TINY_TRIANGLE_BOTTOM_PADDING 3  // pixels

- (void)drawRect:(NSRect)aRect;
{
    if ([[self window] firstResponder] == self) {
        NSSetFocusRingStyle(NSFocusRingAbove);
        [self setKeyboardFocusRingNeedsDisplayInRect:[self frame]];
    }
    if ([self isEnabled]) {
        // Draw image near top center of its view
        NSImage *dropDownImage = OAImageNamed(@"OADropDownTriangle", OMNI_BUNDLE);
        if ([self.effectiveAppearance OA_isDarkAppearance]) {
            static NSImage *whiteImage = nil;
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                NSRect imageRect = NSMakeRect(0, 0, dropDownImage.size.width, dropDownImage.size.height);
                whiteImage = [NSImage imageWithSize:imageRect.size flipped:NO drawingHandler:^(NSRect dst) {
                    [[NSColor whiteColor] set];
                    NSRectFill(dst);
                    [dropDownImage drawInRect:imageRect fromRect:imageRect operation:NSCompositingOperationDestinationIn fraction:1.0];
                    return YES;
                }];
            });
            dropDownImage = whiteImage;
        }
        NSSize imageSize = [dropDownImage size];
        CGRect bounds = [self bounds];
        CGRect imageRect;
        imageRect.size = imageSize;
        imageRect.origin.x = floor((bounds.size.width - imageSize.width)/2);
        imageRect.origin.y = /*bounds.size.height - imageSize.height - */ TINY_TRIANGLE_BOTTOM_PADDING;
        
        [dropDownImage drawFlippedInRect:imageRect operation:NSCompositingOperationSourceOver];
    }
}

@end

