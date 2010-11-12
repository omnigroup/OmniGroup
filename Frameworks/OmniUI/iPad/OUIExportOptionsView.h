// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>


@interface OUIExportOptionsView : UIView

- (void)addChoiceToIndex:(NSUInteger)index image:(UIImage *)image label:(NSString *)label target:(id)target selector:(SEL)selector;

@end
