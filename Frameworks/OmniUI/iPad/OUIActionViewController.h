// Copyright 2011-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

/*
 Single-shot view controllers that want to pass back results to a caller w/o having to invent some delegate protocol each time.
 */
@interface OUIActionViewController : UIViewController

// Typed as id so you can pass a block that takes the actual type of the view controller.
@property(nonatomic,copy) void (^finished)(id viewController, NSError *errorOrNil);

- (void)finishWithError:(NSError *)error;
- (void)cancel; // The finished block will be called with a user-cancelled error.

@end
