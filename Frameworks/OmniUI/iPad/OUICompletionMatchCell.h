// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UITableViewCell.h>

@class OFCompletionMatch, OFCompletionMatchLabel;

@interface OUICompletionMatchCell : UITableViewCell

// Designated initializer
- (id)initWithStyle:(UITableViewCellStyle)style completionMatch:(OFCompletionMatch *)completionMatch reuseIdentifier:(NSString *)reuseIdentifier;
- (id)initWithCompletionMatch:(OFCompletionMatch *)completionMatch reuseIdentifier:(NSString *)reuseIdentifier;

// Generally, clients of this class should set the completionMatch and not set the label contents or attributes directly.
// We'll do the right thing based on whether or not we can draw attributed strings on the target OS.

@property (nonatomic, strong) OFCompletionMatch *completionMatch;

@end
