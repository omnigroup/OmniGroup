// Copyright 2003-2005, 2007, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OADefaultSettingIndicatorButton.h"

#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

@interface OADefaultSettingIndicatorButton (Private)
- (void)_setupButton;
- (BOOL)_shouldShow;
- (id)_objectValue;
- (id)_defaultObjectValue;
@end

@implementation OADefaultSettingIndicatorButton

static NSImage *ledOnImage = nil;
static NSImage *ledOffImage = nil;
const static CGFloat horizontalSpaceFromSnuggleView = 2.0f;

+ (void)initialize;
{
    OBINITIALIZE;
    
    NSBundle *bundle = [NSBundle bundleForClass:[OADefaultSettingIndicatorButton class]];
    ledOnImage = [[NSImage alloc] initWithContentsOfFile:[bundle pathForImageResource:@"OADefaultSettingIndicatorOn"]];
    ledOffImage = [[NSImage alloc] initWithContentsOfFile:[bundle pathForImageResource:@"OADefaultSettingIndicatorOff"]];
}

- (id)initWithFrame:(NSRect)frame;
{
    self = [super initWithFrame:frame];
    if (self == nil)
        return nil;

    [self _setupButton];
    return self;
}

- (void)dealloc;
{
    delegate = nil;
    [identifier release];
    
    [super dealloc];
}

// Actions

- (IBAction)resetDefaultValue:(id)sender;
{
    if (snuggleUpToRightSideOfView == nil)
        return;
        
    if ([delegate respondsToSelector:@selector(restoreDefaultObjectValueForSettingIndicatorButton:)])
        [delegate restoreDefaultObjectValueForSettingIndicatorButton:self];
}


// API

- (id)delegate;
{
    return delegate;
}

- (void)setDelegate:(id)newDelegate;
{
    delegate = newDelegate;
}

- (id)identifier;
{
    return identifier;
}

- (void)setIdentifier:(id)newIdentifier;
{
    [identifier release];
    identifier = [newIdentifier retain];
    
    [self validate];
}

- (void)validate;
{
    id defaultObjectValue = [self _defaultObjectValue];
    id objectValue = [self _objectValue];

    [self setState:OFNOTEQUAL(defaultObjectValue, objectValue)];

    if ([delegate respondsToSelector:@selector(toolTipForSettingIndicatorButton:)])
        [self setToolTip:[delegate toolTipForSettingIndicatorButton:self]];
    else
        [self setToolTip:nil];
}

- (void)setDisplaysEvenInDefaultState:(BOOL)displays;
{
    BOOL displaysEvenInDefaultState = (_flags.displaysEvenInDefaultState != 0);
    if (displaysEvenInDefaultState == displays)
        return;
    _flags.displaysEvenInDefaultState = displays ? 1 : 0;
    [self setNeedsDisplay];
}

- (BOOL)displaysEvenInDefaultState;
{
    return _flags.displaysEvenInDefaultState;
}

//

- (void)setSnuggleUpToRightSideOfView:(NSView *)view;
{
    if (view == snuggleUpToRightSideOfView)
        return;
    
    [snuggleUpToRightSideOfView release];
    snuggleUpToRightSideOfView = [view retain];
}

- (NSView *)snuggleUpToRightSideOfView;
{
    return snuggleUpToRightSideOfView;
}

- (void)repositionWithRespectToSnuggleView;
{
    
    if (snuggleUpToRightSideOfView == nil)
        return;
    
    NSSize iconSize = [ledOnImage size];
    
    if ([snuggleUpToRightSideOfView isKindOfClass:[NSControl class]]) {
        NSControl *snuggleUpToRightSideOfControl = (id)snuggleUpToRightSideOfView;
        NSCell *cell = [snuggleUpToRightSideOfControl cell];

        if ([cell alignment] == NSLeftTextAlignment &&
            ![snuggleUpToRightSideOfControl isKindOfClass:[NSSlider class]] && ![snuggleUpToRightSideOfControl isKindOfClass:[NSPopUpButton class]] && 
            !([snuggleUpToRightSideOfControl isKindOfClass:[NSTextField class]] && [(NSTextField *)snuggleUpToRightSideOfControl isEditable]) &&
            ![snuggleUpToRightSideOfControl isKindOfClass:[NSImageView class]]) {
            [snuggleUpToRightSideOfControl sizeToFit];

            // Make sure we just didn't obliterate whatever we resized (might indicate that you need to excluded another type of UI element above)
            OBASSERT(!NSEqualSizes(NSZeroSize, [snuggleUpToRightSideOfControl frame].size));
        }
    }
    
    NSRect controlFrame = [snuggleUpToRightSideOfView frame];
    
    NSPoint origin = NSMakePoint((CGFloat)rint(NSMaxX(controlFrame) + horizontalSpaceFromSnuggleView), (CGFloat)rint(NSMinY(controlFrame) + (NSHeight(controlFrame) - iconSize.height) / 2.0f));
    
    [self setFrame:(NSRect){origin, iconSize}];
    
}

// NSObject (NSNibAwaking)

- (void)awakeFromNib;
{
    [super awakeFromNib];
    [self _setupButton];
    [self repositionWithRespectToSnuggleView];
}


// NSResponder subclass

- (void)mouseDown:(NSEvent *)event;
{
    if ([self _shouldShow])
        [super mouseDown:event];
}


// NSView subclass

- (BOOL)isOpaque;
{
    return NO;   
}

- (void)drawRect:(NSRect)rect;
{
    if ([self _shouldShow])
        [super drawRect:rect];
}

@end

@implementation OADefaultSettingIndicatorButton (Private)

- (void)_setupButton;
{
    [self setButtonType:NSToggleButton];
    [[self cell] setType:NSImageCellType];
    [[self cell] setBordered:NO];
    [self setImagePosition:NSImageOnly];
    [self setImage:ledOffImage];
    [self setAlternateImage:ledOnImage];
    [self setDisplaysEvenInDefaultState:NO];
    [self setTarget:self];
    [self setAction:@selector(resetDefaultValue:)];
}

- (BOOL)_shouldShow;
{
    return ([self state] == 1 || _flags.displaysEvenInDefaultState);
}

- (id)_objectValue;
{
    if ([delegate respondsToSelector:@selector(objectValueForSettingIndicatorButton:)])
        return [delegate objectValueForSettingIndicatorButton:self];
    else
        return nil;
}

- (id)_defaultObjectValue;
{
    if ([delegate respondsToSelector:@selector(defaultObjectValueForSettingIndicatorButton:)])
        return [delegate defaultObjectValueForSettingIndicatorButton:self];
    else
        return nil;
}

@end
