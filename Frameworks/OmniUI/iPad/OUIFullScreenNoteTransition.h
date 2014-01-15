//
//  OUIFullScreenNoteTransition.h
//  OmniUI
//
//  Created by tom on 11/12/13.
//
//

#import <UIKit/UIKit.h>

#import <OmniUI/OUINoteTextView.h>

@interface OUIFullScreenNoteTransition : NSObject <UIViewControllerAnimatedTransitioning>

@property(readwrite,nonatomic,assign) OUINoteTextView *fromTextView;

@end
