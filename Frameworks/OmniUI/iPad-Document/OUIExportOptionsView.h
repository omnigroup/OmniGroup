// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIImageView.h>


@interface OUIExportOptionsView : UIImageView
{
@private
    NSMutableArray *_choiceButtons;
}

- (void)addChoiceWithImage:(UIImage *)image label:(NSString *)label target:(id)target selector:(SEL)selector;

@end
