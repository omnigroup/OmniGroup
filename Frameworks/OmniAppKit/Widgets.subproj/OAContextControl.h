// Copyright 2004-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSPopUpButton.h>

NS_ASSUME_NONNULL_BEGIN

// As a special case, NSViews in the responder chain can implement -menuForContextControl: and not -targetViewForContextControl: (and they will be used for the view).
@protocol OAContextControlDelegate <NSObject>
- (nullable NSMenu *)menuForContextControl:(nullable NSControl *)control;
- (nullable NSView *)targetViewForContextControl:(nullable NSControl *)control;
@end

extern NSString *OAContextControlToolTip(void);
extern NSMenu *OAContextControlNoActionsMenu(void);

@interface OAContextControlMenuAndView : NSObject
@property(nonatomic,strong,nullable) NSMenu *menu;
@property(nonatomic,strong,nullable) NSView *targetView;
@end

extern OAContextControlMenuAndView *OAContextControlGetMenu(id <OAContextControlDelegate> delegate, NSControl *control);

NS_ASSUME_NONNULL_END
