// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIPasswordAlert.h>
#import <OmniUI/OUIEnqueueableAlertController.h>

NS_ASSUME_NONNULL_BEGIN

@interface OUIPasswordAlert ()

@property (nonatomic, strong, readonly) OUIEnqueueableAlertController *alertController;
@property (nonatomic, readonly) OUIPasswordAlertOptions options;
@property (nonatomic, readonly, getter = isDismissed) BOOL dismissed;

- (void)configurePasswordTextField:(UITextField *)textField forConfirmation:(BOOL)forConfirmation NS_REQUIRES_SUPER;

- (void)dismissWithAction:(OUIPasswordAlertAction)action;

@end

NS_ASSUME_NONNULL_END
