//
//  OUIFullScreenNoteTextViewController.h
//  OmniUI
//
//  Created by tom on 11/12/13.
//
//

#import <OmniUI/OUIViewController.h>

@class OUINoteTextView;
@class OUIFullScreenNoteTextViewController;

typedef void (^NoteControllerDismissed)(OUIFullScreenNoteTextViewController *);

@interface OUIFullScreenNoteTextViewController : UIViewController

@property (nonatomic, retain) NSString *text;
@property (nonatomic, assign) NSRange selectedRange;

@property (nonatomic, copy) NoteControllerDismissed dismissedCompletionHandler;

@property (nonatomic, retain) IBOutlet OUINoteTextView *textView;
@property (nonatomic, retain) IBOutlet UINavigationBar *fullScreenNavigationBar;

@end
