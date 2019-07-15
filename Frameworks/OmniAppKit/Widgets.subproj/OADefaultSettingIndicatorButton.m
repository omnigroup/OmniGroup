// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OADefaultSettingIndicatorButton.h>

#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/NSImage-OAExtensions.h>
#import <OmniAppKit/OAVersion.h>

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

@implementation OADefaultSettingIndicatorButton
{
    IBOutlet NSView *snuggleUpToRightSideOfView;
    IBOutlet id delegate;

    struct {
        unsigned int displaysEvenInDefaultState:1;
    } _flags;
}

static NSImage *OnImage = nil;
static NSImage *OffImage = nil;
const static CGFloat horizontalSpaceFromSnuggleView = 2.0f;

+ (void)initialize;
{
    OBINITIALIZE;
    
    OnImage = OAImageNamed(@"OADefaultSettingIndicatorOn", OMNI_BUNDLE);
    OffImage = OAImageNamed(@"OADefaultSettingIndicatorOff", OMNI_BUNDLE);
}

+ (OADefaultSettingIndicatorButton *)defaultSettingIndicatorWithIdentifier:(id <NSCopying>)settingIdentifier forView:(NSView *)view delegate:(id)delegate;
{
    NSSize buttonSize = [OnImage size];
    OADefaultSettingIndicatorButton *indicator = [[[self class] alloc] initWithFrame:NSMakeRect(0, 0, buttonSize.height, buttonSize.width)];
    if (view != nil) {
        OBASSERT([view superview] != nil);
        [[view superview] addSubview:indicator];
        [indicator setSnuggleUpToRightSideOfView:view];
        [indicator repositionWithRespectToSnuggleViewAllowingResize:NO];
    }
    indicator.settingIdentifier = settingIdentifier;
    [indicator setDelegate:delegate];
    
    return indicator;
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

@dynamic identifier; // Needed to acknowledge that we won't get storage for _identifier since the superclass implements it.

- (void)setSettingIdentifier:(id<NSCopying>)settingIdentifier;
{
    _settingIdentifier = [settingIdentifier copyWithZone:NULL];
    
    [self validate];
}

- (void)validate;
{
    if ([delegate respondsToSelector:@selector(stateForSettingIndicatorButton:)]) {
        [self setState:[delegate stateForSettingIndicatorButton:self]];
        
    } else {
        id defaultObjectValue = [self _defaultObjectValue];
        id objectValue = [self _objectValue];

        [self setState:OFNOTEQUAL(defaultObjectValue, objectValue)];
    }

    if ([delegate respondsToSelector:@selector(toolTipForSettingIndicatorButton:)])
        [self setToolTip:[delegate toolTipForSettingIndicatorButton:self]];
    else
        [self setToolTip:nil];

    [self _showOrHide];
}

- (void)setDisplaysEvenInDefaultState:(BOOL)displays;
{
    BOOL displaysEvenInDefaultState = (_flags.displaysEvenInDefaultState != 0);
    if (displaysEvenInDefaultState == displays)
        return;
    _flags.displaysEvenInDefaultState = displays ? 1 : 0;
    [self setNeedsDisplay:YES];
    [self _showOrHide];
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
    
    snuggleUpToRightSideOfView = view;
}

- (NSView *)snuggleUpToRightSideOfView;
{
    return snuggleUpToRightSideOfView;
}

- (void)repositionWithRespectToSnuggleView;
{
    [self repositionWithRespectToSnuggleViewAllowingResize:YES];
}

- (void)repositionWithRespectToSnuggleViewAllowingResize:(BOOL)allowResize;
{
    
    if (snuggleUpToRightSideOfView == nil)
        return;
    
    NSSize iconSize = [OnImage size];
    
    if ([snuggleUpToRightSideOfView isKindOfClass:[NSControl class]]) {
        NSControl *snuggleUpToRightSideOfControl = (id)snuggleUpToRightSideOfView;
        NSCell *cell = [snuggleUpToRightSideOfControl cell];

        if (allowResize && [cell alignment] == NSTextAlignmentLeft &&
            ![snuggleUpToRightSideOfControl isKindOfClass:[NSSlider class]] && ![snuggleUpToRightSideOfControl isKindOfClass:[NSPopUpButton class]] && 
            !([snuggleUpToRightSideOfControl isKindOfClass:[NSTextField class]] && [(NSTextField *)snuggleUpToRightSideOfControl isEditable]) &&
            ![snuggleUpToRightSideOfControl isKindOfClass:[NSImageView class]]) {
            [snuggleUpToRightSideOfControl sizeToFit];

            // Make sure we just didn't obliterate whatever we resized (might indicate that you need to excluded another type of UI element above)
            OBASSERT(!NSEqualSizes(NSZeroSize, [snuggleUpToRightSideOfControl frame].size));
        }
    }
    
    NSRect controlFrame = [snuggleUpToRightSideOfView frame];

    CGFloat xEdge = NSMaxX(controlFrame);
    xEdge -= [snuggleUpToRightSideOfView alignmentRectInsets].right;
    
    NSPoint origin;
    origin.x = rint(xEdge + horizontalSpaceFromSnuggleView);
    origin.y = ceil(NSMidY(controlFrame) - (iconSize.height / 2.0f));
    
    if ([self.snuggleUpToRightSideOfView isKindOfClass:[NSSegmentedControl class]]) {
        origin.y -= 1.0f;
    }

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

#pragma mark - Private

- (void)_setupButton;
{
    [self setButtonType:NSButtonTypeToggle];
    [[self cell] setType:NSImageCellType];
    [[self cell] setBordered:NO];
    [self setImagePosition:NSImageOnly];
    [self setImage:OffImage];
    [self setAlternateImage:OnImage];
    [self setDisplaysEvenInDefaultState:NO];
    [self setTarget:self];
    [self setAction:@selector(resetDefaultValue:)];
}

- (BOOL)_shouldShow;
{
    return ([self state] == 1 || _flags.displaysEvenInDefaultState);
}

- (nullable id)_objectValue;
{
    if ([delegate respondsToSelector:@selector(objectValueForSettingIndicatorButton:)])
        return [delegate objectValueForSettingIndicatorButton:self];
    else
        return nil;
}

- (nullable id)_defaultObjectValue;
{
    if ([delegate respondsToSelector:@selector(defaultObjectValueForSettingIndicatorButton:)])
        return [delegate defaultObjectValueForSettingIndicatorButton:self];
    else
        return nil;
}

- (void)_showOrHide;
{
    self.hidden = ![self _shouldShow];
}

@end

NS_ASSUME_NONNULL_END
