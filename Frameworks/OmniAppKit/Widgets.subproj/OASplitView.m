// Copyright 2000-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OASplitView.h>

#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

@interface OASplitView (/*Private*/)
- (void)didResizeSubviews:(NSNotification *)notification;
- (void)observeSubviewResizeNotifications;
@end

@implementation OASplitView

- (id)initWithFrame:(NSRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
        
    [self observeSubviewResizeNotifications];
    
    return self;
}

- (id)initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
        
    [self observeSubviewResizeNotifications];

    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
        positionAutosaveName = name;
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
        NSUInteger frameStringsCount = [subviewFrameStrings count];
        NSArray *subviews = [self subviews];
        NSUInteger subviewIndex, subviewCount = [subviews count];

        // Walk through our subviews re-applying frames so we don't explode in the event that the archived frame strings become out of sync with our subview count
        for (subviewIndex = 0; subviewIndex < subviewCount && subviewIndex < frameStringsCount; subviewIndex++) {
            NSView *subview;
            
            subview = [subviews objectAtIndex:subviewIndex];
            [subview setFrame:NSRectFromString([subviewFrameStrings objectAtIndex:subviewIndex])];
        }
    }
}

#pragma mark Private

- (void)didResizeSubviews:(NSNotification *)notification;
{
    if ([NSString isEmptyString:positionAutosaveName])
        return;

    NSMutableArray *subviewFrameStrings = [NSMutableArray array];
    for (NSView *subview in [self subviews])
        [subviewFrameStrings addObject:NSStringFromRect([subview frame])];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:subviewFrameStrings forKey:positionAutosaveName];
}

- (void)observeSubviewResizeNotifications;
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didResizeSubviews:) name:NSSplitViewDidResizeSubviewsNotification object:self];
}

@end
