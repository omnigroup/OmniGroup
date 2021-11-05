// Copyright 2001-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAToolbarItem.h>
#import <OmniAppKit/OAApplication.h>
#import <OmniAppKit/NSImage-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>


RCS_ID("$Id$");

@implementation OAToolbarItem
{
    NSImage *_optionKeyImage;
    NSString *_optionKeyLabel;
    NSString *_optionKeyToolTip;
    SEL _optionKeyAction;

    BOOL inOptionKeyState;
    BOOL observingTintOverrideChanges;

    // If these are non-nil, we'll change our image when the control tint changes.
    NSString *tintedImageStem, *tintedOptionImageStem;
    NSBundle *tintedImageBundle;
}

#define TINT_PREFERENCE ([OFPreference preferenceForKey:OAToolbarItemTintOverridePreference enumeration:[NSImage tintNameEnumeration]])

- (id)initWithItemIdentifier:(NSString *)itemIdentifier;
{
    if (!(self = [super initWithItemIdentifier:itemIdentifier]))
        return nil;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(modifierFlagsChanged:) name:OAFlagsChangedQueuedNotification object:nil];
    inOptionKeyState = NO;
    
    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OAFlagsChangedQueuedNotification object:nil];
    if (observingTintOverrideChanges) {
        observingTintOverrideChanges = NO;
        [OFPreference removeObserver:self forPreference:TINT_PREFERENCE];
    }
}

#pragma mark API

- (void)setUsesTintedImage:(NSString *)imageName inBundle:(NSBundle *)imageBundle;
{
    [self setUsesTintedImage:imageName optionKeyImage:nil inBundle:imageBundle];
}

- (void)setUsesTintedImage:(NSString *)imageName optionKeyImage:(NSString *)alternateImageName inBundle:(NSBundle *)imageBundle;
{
    OBASSERT(imageBundle != nil);
    OBASSERT(![NSString isEmptyString:imageName]);
    
    if (alternateImageName && [imageName isEqualToString:alternateImageName])
        alternateImageName = nil;
    
    if (OFISEQUAL(imageName, tintedImageStem) && OFISEQUAL(alternateImageName, tintedOptionImageStem) && (imageBundle == tintedImageBundle))
        return;
    
    tintedImageStem = [imageName copy];
    tintedOptionImageStem = [alternateImageName copy];
    tintedImageBundle = imageBundle;

    [self _tintsDidChange:nil];
    if (!observingTintOverrideChanges) {
        observingTintOverrideChanges = YES;
        [OFPreference addObserver:self selector:@selector(_tintsDidChange:) forPreference:TINT_PREFERENCE];
    }
}

#pragma mark NSToolbarItem subclass

- (void)validate;
{
    [super validate];
    NSObject *myDelegate = self.delegate;
    if (myDelegate) {
        self.enabled = [myDelegate validateToolbarItem:self];
    }
}

// Called when the toolbar item is moved into the "overflow" menu (accessible via the double-chevron at the end of the toolbar) or toolbar is text-only.
- (NSMenuItem *)menuFormRepresentation;
{
    NSMenuItem *menuFormRepresentation = [super menuFormRepresentation];
    if (![menuFormRepresentation image]) {
        NSImage *image = [[self image] copy];
        [image setSize:NSMakeSize(16,16)];
        [menuFormRepresentation setImage:image];
    }
    
    return menuFormRepresentation;
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    OAToolbarItem *copy = [super copyWithZone:zone];
    copy->_optionKeyImage = [_optionKeyImage copy];
    copy->_optionKeyLabel = [_optionKeyLabel copy];
    copy->_optionKeyToolTip = [_optionKeyToolTip copy];
    copy->tintedImageStem = [tintedImageStem copy];
    copy->tintedOptionImageStem = [tintedOptionImageStem copy];
    copy->tintedImageBundle = [tintedImageBundle copy];
    return copy;
}

#pragma mark - NotificationsDelegatesDatasources

- (void)modifierFlagsChanged:(NSNotification *)note;
{
    BOOL optionDown = ([[note object] modifierFlags] & NSEventModifierFlagOption) ? YES : NO;

    if (optionDown != inOptionKeyState) {
        if ([self optionKeyImage])
            [self _swapImage];
        if ([self optionKeyLabel])
            [self _swapLabel];
        if ([self optionKeyToolTip])
            [self _swapToolTip];
	
	// bug://bugs/30641 - Assignment toolbar button stops working properly once you Option-click it
	// toolbar buttons with a drop-down as one of the 'states' needs to have the ability to setup a nil action
        if ([self optionKeyAction] || [self optionKeyImage])	
            [self _swapAction];
        inOptionKeyState = optionDown;
    } 
}

#pragma mark - Private

- (void)_swapImage;
{
    NSImage *image = [self image];
    [self setImage:[self optionKeyImage]];
    [self setOptionKeyImage:image];
}

- (void)_swapLabel;
{
    NSString *label = [self label];
    [self setLabel:[self optionKeyLabel]];
    [self setOptionKeyLabel:label];
}

- (void)_swapToolTip;
{
    NSString *toolTip = [self toolTip];
    [self setToolTip:[self optionKeyToolTip]];
    [self setOptionKeyToolTip:toolTip];
}

- (void)_swapAction;
{
    SEL action = [self action];
    [self setAction:[self optionKeyAction]];
    [self setOptionKeyAction:action];
}

- (void)_tintsDidChange:(id)sender;
{
    NSImage *base, *opt;
    
    OFPreference *tintOverride = TINT_PREFERENCE;
    NSControlTint desiredTint = [tintOverride enumeratedValue];
    if (desiredTint == NSDefaultControlTint) {
        base = [NSImage tintedImageNamed:tintedImageStem inBundle:tintedImageBundle allowingNil:NO];
        if (tintedOptionImageStem)
            opt = [NSImage tintedImageNamed:tintedOptionImageStem inBundle:tintedImageBundle allowingNil:NO];
        else
            opt = nil;
    } else {
        base = [NSImage imageNamed:tintedImageStem withTint:desiredTint inBundle:tintedImageBundle];
        if (tintedOptionImageStem)
            opt = [NSImage imageNamed:tintedOptionImageStem withTint:desiredTint inBundle:tintedImageBundle];
        else
            opt = nil;
    }
    
    if (opt != nil && inOptionKeyState)
        SWAP(base, opt);
    if ([self image] != base)
        [self setImage:base];
    [self setOptionKeyImage:opt];
}

@end

OB_REQUIRE_ARC // Since we're using weak

@implementation OAToolbarItemButton

+ (Class)cellClass;
{
    return [OAToolbarItemButtonCell class];
}

@synthesize toolbarItem = _weak_toolbarItem;

@end

@implementation OAToolbarItemButtonCell

static BOOL _isRetina(NSView *view)
{
    NSWindow *window = view.window;

    CGFloat backingFactor;
    if (window != nil) {
        backingFactor = [window backingScaleFactor];
    } else {
        backingFactor = [[NSScreen mainScreen] backingScaleFactor];
    }

    return (backingFactor == 2.0);
}

- (NSRect)imageRectForBounds:(NSRect)rect;
{
    NSRect imageRect = [super imageRectForBounds:rect];

    if ([OFVersionNumber isOperatingSystemMojaveOrLater]) {
        // On Mojave, the image is one point too high on non-Retina.
        CGFloat imageShift;

        if (_isRetina(self.controlView)) {
            imageShift = 0.0;
        } else {
            imageShift = 1.0;
        }
        
        imageRect.origin.y += imageShift;
    } else {
        // On High Sierra, the image is one point too low on Retina.
        CGFloat imageShift;

        if (_isRetina(self.controlView)) {
            imageShift = -0.5;
        } else {
            imageShift = 0.0;
        }

        imageRect.origin.y += imageShift;
    }

    return imageRect;
}

- (void)drawBezelWithFrame:(NSRect)frame inView:(NSView*)controlView;
{
    // On 10.13, toolbar button frames render too low, and should be shifted up (the amount differs between Retina and non-Retina).
    if (![OFVersionNumber isOperatingSystemMojaveOrLater]) {
        CGFloat bezelShift;

        if (_isRetina(controlView)) {
            bezelShift = -0.5;
        } else {
            bezelShift = -1.0;
        }

        frame.origin.y += bezelShift;
    }

    [super drawBezelWithFrame:frame inView:controlView];
}

@end

@implementation OAUserSuppliedImageToolbarItemButton

+ (nullable Class)cellClass;
{
    Class cellClass = [OAUserSuppliedImageToolbarItemButtonCell class];
    OBASSERT([cellClass superclass] == [[self superclass] cellClass]);
    return cellClass;
}

@end

@implementation OAUserSuppliedImageToolbarItemButtonCell

- (NSRect)imageRectForBounds:(NSRect)rect;
{
    NSRect imageRect = [super imageRectForBounds:rect];

    if ([OFVersionNumber isOperatingSystemBigSurOrLater]) {
        // When using a system symbol image on Big Sur, it won't be vertically centered (but *other* images are).
        // If a symbol is set on a regular NSToolbarItem (not a view-containing one) or set on a regular NSButton, it works. So something we are doing it probably messing up the default behavior.
        imageRect.origin.y = floor(CGRectGetMinY(rect) + (rect.size.height - imageRect.size.height)/2);
    } else if (![OFVersionNumber isOperatingSystemMojaveOrLater]) {
        // We end up with too big of a rect here for arbitrary user supplied images. Our OAScriptIcon.png has built-in padding, but random images might not.
        // Mojave does a better job here.
        imageRect = OAInsetRectBySize(imageRect, NSMakeSize(0, 3));
    }

    return imageRect;
}

@end
