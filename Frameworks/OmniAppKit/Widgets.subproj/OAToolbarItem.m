// Copyright 2001-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAToolbarItem.h"
#import "OAApplication.h"
#import "NSImage-OAExtensions.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>


RCS_ID("$Id$");

@interface OAToolbarItem (Private)
- (void)_swapImage;
- (void)_swapLabel;
- (void)_swapToolTip;
- (void)_swapAction;
- (void)_tintsDidChange:(id)sender;
@end

@implementation OAToolbarItem

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
    if (observingTintChanges) {
        observingTintChanges = NO;
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSControlTintDidChangeNotification object:nil];
    }
    if (observingTintOverrideChanges) {
        observingTintOverrideChanges = NO;
        [OFPreference removeObserver:self forPreference:TINT_PREFERENCE];
    }
    [_optionKeyImage release];
    [_optionKeyLabel release];
    [_optionKeyToolTip release];
    
    [tintedImageStem release];
    [tintedOptionImageStem release];
    [tintedImageBundle release];

    [super dealloc];
}

#pragma mark API

@synthesize delegate = _nonretained_delegate;
@synthesize optionKeyImage = _optionKeyImage;
@synthesize optionKeyLabel = _optionKeyLabel;
@synthesize optionKeyToolTip = _optionKeyToolTip;
@synthesize optionKeyAction = _optionKeyAction;

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
    
    [tintedImageStem autorelease];
    tintedImageStem = [imageName copy];
    [tintedOptionImageStem autorelease];
    tintedOptionImageStem = [alternateImageName copy];
    [tintedImageBundle release];
    tintedImageBundle = [imageBundle retain];
    
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
    if (_nonretained_delegate)
        [self setEnabled:[_nonretained_delegate validateToolbarItem:self]];
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    OAToolbarItem *copy = [super copyWithZone:zone];
    copy->_optionKeyImage = [_optionKeyImage retain];
    copy->_optionKeyLabel = [_optionKeyLabel copy];
    copy->_optionKeyToolTip = [_optionKeyToolTip copy];
    copy->tintedImageStem = [tintedImageStem copy];
    copy->tintedOptionImageStem = [tintedOptionImageStem copy];
    copy->tintedImageBundle = [tintedImageBundle retain];
    return copy;
}

@end

@implementation OAToolbarItem (NotificationsDelegatesDatasources)

- (void)modifierFlagsChanged:(NSNotification *)note;
{
    BOOL optionDown = ([[note object] modifierFlags] & NSAlternateKeyMask) ? YES : NO;

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

@end

@implementation OAToolbarItem (Private)

- (void)_swapImage;
{
    NSImage *image = [[self image] retain];
    [self setImage:[self optionKeyImage]];
    [self setOptionKeyImage:image];
    [image release];
}

- (void)_swapLabel;
{
    NSString *label = [[self label] retain];
    [self setLabel:[self optionKeyLabel]];
    [self setOptionKeyLabel:label];
    [label release];
}

- (void)_swapToolTip;
{
    NSString *toolTip = [[self toolTip] retain];
    [self setToolTip:[self optionKeyToolTip]];
    [self setOptionKeyToolTip:toolTip];
    [toolTip release];
}

- (void)_swapAction;
{
    SEL action = [self action];
    [self setAction:[self optionKeyAction]];
    [self setOptionKeyAction:action];
}

- (void)_tintsDidChange:(id)sender
{
    BOOL shouldBeObserving;
    NSImage *base, *opt;
    
    OFPreference *tintOverride = TINT_PREFERENCE;
    NSControlTint desiredTint = [tintOverride enumeratedValue];
    if (desiredTint == NSDefaultControlTint) {
        shouldBeObserving = YES;
        base = [NSImage tintedImageNamed:tintedImageStem inBundle:tintedImageBundle];
        if (tintedOptionImageStem)
            opt = [NSImage tintedImageNamed:tintedOptionImageStem inBundle:tintedImageBundle];
        else
            opt = nil;
    } else {
        shouldBeObserving = NO;
        base = [NSImage imageNamed:tintedImageStem withTint:desiredTint inBundle:tintedImageBundle];
        if (tintedOptionImageStem)
            opt = [NSImage imageNamed:tintedOptionImageStem withTint:desiredTint inBundle:tintedImageBundle];
        else
            opt = nil;
    }
    
    if (observingTintChanges && !shouldBeObserving) {
        observingTintChanges = NO;
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSControlTintDidChangeNotification object:nil];
    }
    if (!observingTintChanges && shouldBeObserving) {
        observingTintChanges = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:_cmd name:NSControlTintDidChangeNotification object:nil];
    }
    
    if (opt != nil && inOptionKeyState)
        SWAP(base, opt);
    if ([self image] != base)
        [self setImage:base];
    [self setOptionKeyImage:opt];
}

@end

