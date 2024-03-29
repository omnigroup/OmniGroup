// Copyright 2014-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIAutolayoutInspectorHeaderView.h"

#import <OmniAppKit/OATrackingLoop.h>
#import <OmniAppKit/NSColor-OAExtensions.h>
#import <OmniInspector/OIAppearance.h>

RCS_ID("$Id$");

@interface OIAutolayoutInspectorHeaderView ()

@property (nonatomic, strong) IBOutlet NSLayoutConstraint *verticalCenteringConstraint;

@end

@implementation OIAutolayoutInspectorHeaderView

static CGFloat separatorSideInset = 0;
static NSColor *separatorColor = nil;
static CGFloat separatorHeight;

+ (void)initialize
{
    if (self == [OIAutolayoutInspectorHeaderView class]) {
        OFPreference *seperatorSideInsetPref = [[OFPreferenceWrapper sharedPreferenceWrapper] preferenceForKey:@"OIInspectorHeaderSeparatorSideInset" defaultValue:@(0)];
        separatorSideInset = [seperatorSideInsetPref doubleValue];

        if ([OFPreference hasPreferenceForKey:@"OIInspectorHeaderSeparatorColor"]) {
            id colorObject = [[OFPreferenceWrapper sharedPreferenceWrapper] objectForKey:@"OIInspectorHeaderSeparatorColor"];
            if ([colorObject isKindOfClass:[NSDictionary class]]) {
                separatorColor = [NSColor colorFromPropertyListRepresentation:colorObject withColorSpaceManager:nil shouldDefaultToGenericSpace:NO];
            } else {
                OBASSERT_NOT_REACHED("Unexpected value for OIInspectorHeaderSeparatorColor of type: %@", NSStringFromClass([colorObject class]));
            }
        } else {
            separatorColor = [NSColor gridColor];
        }
    }
}

+ (CGFloat)contentHeight;
{
    return [[OIAppearance appearance] CGFloatForKeyPath:@"InspectorHeaderContentHeight"];
}

+ (CGFloat)separatorTopPadding;
{
    return [[OIAppearance appearance] CGFloatForKeyPath:@"InspectorHeaderSeparatorTopPadding"];
}

+ (CGFloat)separatorHeight
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        OFPreference *heightPref = [OFPreference preferenceForKey:@"OIInspectorHeaderSeparatorHeight" defaultValue:@([[OIAppearance appearance] CGFloatForKeyPath:@"InspectorHeaderSeparatorHeight"])];
        separatorHeight = [heightPref doubleValue];
    });

    return separatorHeight;
}

- (void)setDrawsSeparator:(BOOL)drawsSeparator;
{
    if (drawsSeparator == _drawsSeparator)
        return;
    
    _drawsSeparator = drawsSeparator;
    
    self.verticalCenteringConstraint.constant = drawsSeparator ? -1 * ([[self class] separatorTopPadding] + [[self class] separatorHeight]) / 2 : 0.0f;
    [self invalidateIntrinsicContentSize];
}

#pragma mark - NSView subclass

#pragma mark Event handling

- (NSView *)hitTest:(NSPoint)aPoint;
{
    // We want all the clicks for ourselves!
    if (NSPointInRect(aPoint, [self frame])) {
        return self;
    }
    
    return [super hitTest:aPoint];
}

#if 0
// Eventual support for dragging slices around and into detached inspector windows
- (void)mouseDown:(NSEvent *)theEvent;
{
    [self.disclosureButton.cell setHighlighted:YES];

    OATrackingLoop *loop = [self trackingLoopForMouseDown:theEvent];
    loop.hysteresisSize = 5.0f;
    loop.dragged = ^(OATrackingLoop *loop) {
        // Hide inspector contents, grab drag image
//        NSPoint dragLocation = loop.currentMouseDraggedPointInView;
        
        NSLog(@"foo!");
        if (!loop.insideVisibleRect) {
        }
    };
    
    loop.up = ^(OATrackingLoop *loop){
        // Show inspector contents, move inspector
    };
    
    loop.shouldAutoscroll = ^(OATrackingLoop *loop){
        return YES;
    };
    
    [loop run];
}

- (void)mouseDragged:(NSEvent *)theEvent;
{
    NSPoint viewPoint = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    BOOL inBounds = NSPointInRect(viewPoint, [self bounds]);
    [self.disclosureButton.cell setHighlighted:inBounds];
}
#endif

- (void)mouseUp:(NSEvent *)theEvent;
{
    [self.disclosureButton.cell setHighlighted:NO];
    
    NSPoint viewPoint = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    BOOL inBounds = NSPointInRect(viewPoint, [self bounds]);
    
    if (inBounds) {
        [self.disclosureButton sendAction:self.disclosureButton.action to:self.disclosureButton.target];
    }
}

#pragma mark Layout

- (NSSize)intrinsicContentSize;
{
    CGFloat desiredHeight = [[self class] contentHeight];
    if (self.drawsSeparator)
        desiredHeight += [[self class] separatorTopPadding] + [[self class] separatorHeight];
    
    return (NSSize){
        .width = NSViewNoIntrinsicMetric,
        .height = desiredHeight,
    };
}

#pragma mark Drawing

- (void)drawRect:(NSRect)dirtyRect;
{
    [super drawRect:dirtyRect];
    
    if (self.drawsSeparator == NO)
        return;
    
    CGFloat height = [[self class] separatorHeight];
    CGFloat topPadding = [[self class] separatorTopPadding];

    NSRect separatorRect = (NSRect){
        .origin = (NSPoint){
            .x = separatorSideInset,
            .y = [self isFlipped] ? NSMinY(self.bounds) + topPadding : NSMaxY(self.bounds) - height - topPadding,
        },
        .size = (NSSize){
            .width = NSWidth(self.bounds) - 2 * separatorSideInset,
            .height = height,
        },
    };
    
    [separatorColor set];
    NSRectFill(separatorRect);
}

@end
