// Copyright 2000-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OASplitView.h"

#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

@interface OASplitView (Private)
- (void)didResizeSubviews:(NSNotification *)notification;
- (void)observeSubviewResizeNotifications;
@end

@implementation OASplitView

- (id)initWithFrame:(NSRect)frame;
{
    if ([super initWithFrame:frame] == nil)
        return nil;
        
    [self observeSubviewResizeNotifications];
    
    return self;
}

- (id)initWithCoder:(NSCoder *)coder;
{
    if ([super initWithCoder:coder] == nil)
        return nil;
        
    [self observeSubviewResizeNotifications];

    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [positionAutosaveName release];
    
    [super dealloc];
}

// TODO: only handle clicks which are actually in the divider (currently if a subview doesn't fill the area left for it, we handle clicks there).
- (void)mouseDown:(NSEvent *)mouseEvent;
{
    if ([mouseEvent clickCount] > 1) {
	id <OASplitViewExtendedDelegate> delegate = (id)[self delegate];
        if ([delegate respondsToSelector:@selector(splitView:multipleClick:)]) {
            [delegate splitView:self multipleClick:mouseEvent];
            return;
        }
    }
    [super mouseDown:mouseEvent];
}

- (void)setPositionAutosaveName:(NSString *)name;
{
    if (OFNOTEQUAL(positionAutosaveName, name)) {
        [positionAutosaveName release];
        positionAutosaveName = [name retain];
        [self restoreAutosavedPositions];
    }
}

- (NSString *)positionAutosaveName;
{
    return positionAutosaveName;
}

- (void)restoreAutosavedPositions;
{
    NSArray *subviewFrameStrings;
    if ((subviewFrameStrings = [[NSUserDefaults standardUserDefaults] arrayForKey:[self positionAutosaveName]]) != nil) {
        NSArray *subviews;
        unsigned int frameStringsCount;
        unsigned int subviewIndex, subviewCount;
    
        frameStringsCount = [subviewFrameStrings count];
        subviews = [self subviews];
        subviewCount = [subviews count];

        // Walk through our subviews re-applying frames so we don't explode in the event that the archived frame strings become out of sync with our subview count
        for (subviewIndex = 0; subviewIndex < subviewCount && subviewIndex < frameStringsCount; subviewIndex++) {
            NSView *subview;
            
            subview = [subviews objectAtIndex:subviewIndex];
            [subview setFrame:NSRectFromString([subviewFrameStrings objectAtIndex:subviewIndex])];
        }
    }
}

@end

@implementation OASplitView (Private)

- (void)didResizeSubviews:(NSNotification *)notification;
{
    NSArray *subviews;
    NSMutableArray *subviewFrameStrings;
    unsigned int subviewIndex, subviewCount;
    NSUserDefaults *defaults;

    if ([NSString isEmptyString:positionAutosaveName])
        return;

    subviewFrameStrings = [NSMutableArray array];
    subviews = [self subviews];
    for (subviewIndex = 0, subviewCount = [subviews count]; subviewIndex < subviewCount; subviewIndex++) {
        NSView *subview;
        
        subview = [subviews objectAtIndex:subviewIndex];
        [subviewFrameStrings addObject:NSStringFromRect([subview frame])];
    }
    
    defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:subviewFrameStrings forKey:positionAutosaveName];
    [defaults autoSynchronize];
}

- (void)observeSubviewResizeNotifications;
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didResizeSubviews:) name:NSSplitViewDidResizeSubviewsNotification object:self];
}

@end
