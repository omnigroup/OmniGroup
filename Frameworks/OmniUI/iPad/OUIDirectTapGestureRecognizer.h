// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UITapGestureRecognizer.h>

@interface OUIDirectTapGestureRecognizer : UITapGestureRecognizer {
@private
    CGPoint _firstTapLocation;  // in case the view has shifted (ex: keyboard shows/hides) and calling -locationInView will not be accurate (see <bug:///74636> (Zoomed in double-tap to switch to a different text editor is sometimes wrong)). OG is using this for its double-tap gesture recognizer where the first tap may dismiss the editor
}

@property (nonatomic, readonly) CGPoint firstTapLocation;
@end

@interface OUIDirectLongPressGestureRecognizer : UILongPressGestureRecognizer
@end
