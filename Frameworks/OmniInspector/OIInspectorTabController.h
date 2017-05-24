// Copyright 2006-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

#import <OmniInspector/OIInspector.h>
#import <OmniInspector/OIInspectorRegistry.h>

NS_ASSUME_NONNULL_BEGIN

@class NSArray, NSBundle; // Foundation
@class NSBox, NSImage, NSMenuItem, NSView; // AppKit

@interface OIInspectorTabController : NSObject
{
    NSArray *_currentlyInspectedObjects;
    NSImage *_image;
    NSBox *_dividerView;
    struct {
        unsigned hasLoadedView: 1;
        unsigned needsInspectObjects: 1;
    } _flags;
    OIVisibilityState _visibilityState;
}

- initWithInspectorDictionary:(NSDictionary *)tabPlist inspectorRegistry:(OIInspectorRegistry *)inspectorRegistry bundle:(NSBundle *)fromBundle;

@property(nonatomic,readonly) OIInspector <OIConcreteInspector> *inspector;
@property (nonatomic, weak) OIInspectorRegistry *inspectorRegistry;

- (NSImage *)image;
- (NSView *)inspectorView;
- (NSView *)dividerView;
- (BOOL)isPinned;
- (BOOL)isVisible;
- (OIVisibilityState)visibilityState;
- (void)setVisibilityState:(OIVisibilityState)newValue;
- (BOOL)hasLoadedView;

- (void)inspectObjects:(BOOL)inspectNothing;

- (NSDictionary *)copyConfiguration;
- (void)loadConfiguration:(NSDictionary *)config;

// Covers for OIInspector methods
- (NSString *)inspectorIdentifier;
- (NSString *)displayName;
- (NSString *)shortcutKey;
- (NSUInteger)shortcutModifierFlags;
- (NSMenuItem *)menuItemForTarget:(nullable id)target action:(SEL)action;

@end

@protocol OIInspectorTabContainer
- (OIInspectorTabController *)tabWithIdentifier:(NSString *)identifier;
@end

NS_ASSUME_NONNULL_END
