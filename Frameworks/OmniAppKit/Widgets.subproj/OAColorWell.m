// Copyright 2003-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAColorWell.h>
#if defined(MAC_OS_VERSION_11_0) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_VERSION_11_0
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#endif

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$");

/*
 NSColorWell and NSColorPanel have some terrible interaction.  In particular, if you have an active color well on an inspector but your main window's first responder has a -changeColor: method, the first responder's method still gets called instead of the inspector's action being responsible!

 Note that this probably only happens in inspectors since NSColorPanel uses -sendAction:to:from: with a nil 'to' and inspectors aren't in key windows typically.

 This class provides a means to determine if there is an active color well.  Thus, in your -changeColor: methods you can just do nothing if there is an active color well or do your default color changing if there isn't.
 */

static NSMutableArray *activeColorWells;
static NSColor *OAColorWellInactiveColor = nil;

NSString * const OAColorWellWillActivate = @"OAColorWellWillActivate";
NSString * const OAColorWellDidDeactivate = @"OAColorWellDidDeactivate";

@interface OAColorWell (Private)
- (void)_containingWindowWillClose:(NSNotification *)notification;
@end

@implementation OAColorWell

+ (void)initialize;
{
    OBINITIALIZE;

    // Don't want to retain them and prevent them from being deallocated (and thus deactivated)!
    activeColorWells = (NSMutableArray *)OFCreateNonOwnedPointerArray();
    OAColorWellInactiveColor = [[NSColor colorWithWhite:0.9f alpha:1.0f] retain];
}

//
// NSColorWell subclass
//

- (void)dealloc;
{
    [self deactivate];
    [super dealloc];
}

- (void)drawWellInside:(NSRect)insideRect;
{
    // NSColorWell draws the color even if it is disabled. We usually don't want to do that - we want to look fully disabled, so we
    if (self.isEnabled || self.showsColorWhenDisabled) {
        [super drawWellInside:insideRect];
    } else {
        [[[self class] inactiveColor] set];
        NSRectFill(insideRect);
    }
}

- (void)deactivate;
{
    [super deactivate];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:NSWindowWillCloseNotification object:[self window]];

    CFIndex idx = [activeColorWells indexOfObjectIdenticalTo:self];
    
    if (idx != NSNotFound) {    
        CFArrayRemoveValueAtIndex((CFMutableArrayRef)activeColorWells, idx);
        [center postNotificationName:OAColorWellDidDeactivate object:self];
    }
}

- (void)activate:(BOOL)exclusive;
{
    [[NSNotificationCenter defaultCenter] postNotificationName:OAColorWellWillActivate object:self];

    // listen for windowWillClose notifications on our window, if we don't have a window yet we will register in -viewWillMoveToWindow instead.
    if ([self window] != nil)
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_containingWindowWillClose:) name:NSWindowWillCloseNotification object:[self window]];

    // Do this first since this the super implementation will poke the color panel into poking -changeColor: on the responder chain.  We want to know that a color well is activated by then.
    if (![activeColorWells containsObjectIdenticalTo:self])
        [activeColorWells addObject:self];

    [super activate:exclusive];
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow;
{
    if ([self isActive]) {
        if (newWindow == nil) {
            [self deactivate];
        } else {
            [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowWillCloseNotification object:[self window]];
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_containingWindowWillClose:) name:NSWindowWillCloseNotification object:newWindow];
        }
    }
}

//
// API
//

+ (NSColor *)inactiveColor;
{
    return OAColorWellInactiveColor;
}

+ (BOOL)hasActiveColorWell;
{
    return [activeColorWells count] > 0;
}

+ (NSArray *)activeColorWells;
{
    return [NSArray arrayWithArray:activeColorWells];
}

+ (void)deactivateAllColorWells;
{
    while ([activeColorWells count])
        [[activeColorWells lastObject] deactivate];
}

- (IBAction)setPatternColorByPickingImage:(id)sender;
{
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];

    [openPanel setAllowsMultipleSelection:NO];
    [openPanel setCanChooseDirectories:NO];
    [openPanel setCanChooseFiles:YES];
    if (@available(macOS 11, *)) {
        openPanel.allowedContentTypes = [[NSImage imageTypes] arrayByPerformingBlock:^id _Nonnull (NSString * _Nonnull identifier) {
            return [UTType typeWithIdentifier: identifier];
        }];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [openPanel setAllowedFileTypes:[NSImage imageTypes]];
#pragma clang diagnostic pop
    }
    
    // Not using a sheet since this will typically be run from an inspector.  If you want to convert this to a sheet, make sure to check whether you are in an inspector (probably easiest to add a new action and factor the method guts out into a private method).
    if ([openPanel runModal] == NSModalResponseOK) {
        NSURL *url = [openPanel URL];
        NSImage *image = [[[NSImage alloc] initWithContentsOfURL:url] autorelease];
        if (!image) {
            NSBeep();
            return;
        }
        
        [self setColor:[NSColor colorWithPatternImage:image]];

        // Send our action too so the target will change the color it is using
        [[self target] performSelector:[self action] withObject:self];
    }
}

@synthesize showsColorWhenDisabled = _showsColorWhenDisabled;

- (void)setShowsColorWhenDisabled:(BOOL)newValue;
{
    if (_showsColorWhenDisabled == newValue) {
        return;
    }
    
    _showsColorWhenDisabled = newValue;
    
    // If we're disabled, changing this value affects our display, so we need to make sure we get redisplayed
    if (![self isEnabled]) {
        [self setNeedsDisplay:YES];
    }
}

@end

@implementation OAColorWell (Private)

// Do NOT call this -windowWillClose: since NSColorWell uses that method name to listen for closes of the NSColorPanel
- (void)_containingWindowWillClose:(NSNotification *)notification;
{
    OBASSERT([notification object] == [self window]);
    [self deactivate];
}

@end

