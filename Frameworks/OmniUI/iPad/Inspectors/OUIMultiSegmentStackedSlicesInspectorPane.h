// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIStackedSlicesInspectorPane.h>
#import <OmniUI/OUITabBarAppearanceDelegate.h>

NS_ASSUME_NONNULL_BEGIN
@class OUITabBar;

@interface OUIInspectorSegment : NSObject
// setting a title is required even for tabs which are image-only, because OUITabBar currently uses the title to destermine which image goes with which tab.
// currently if you set an image, the tab will be set to use images and not display the title, it will only be used internally.
@property(nonatomic,copy) NSString *title;
@property(nonatomic,copy) NSArray *slices;
@property(nonatomic,copy) UIImage *image;
@end

@interface OUIMultiSegmentStackedSlicesInspectorPane : OUIStackedSlicesInspectorPane <OUITabBarAppearanceDelegate>

@property(nonatomic,readonly) OUITabBar *titleTabBar;
@property(nonatomic,strong) NSArray<OUIInspectorSegment *> *segments;
@property(nonatomic,strong) OUIInspectorSegment *selectedSegment;

- (void)reloadAvailableSegments; // this will end up calling makeAvailableSegments

// For subclasses
@property (nonatomic,readonly) BOOL wantsEmbeddedTitleTabBar; // return NO if you want a segmented control in the navigation items instead of tabs in the content.
- (NSArray<OUIInspectorSegment *> *)makeAvailableSegments;

@end

NS_ASSUME_NONNULL_END
