// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSWindow.h>
#import <AppKit/NSBox.h>

typedef BOOL (^OAViewPickerCompletionHandler)(NSView *pickedView); // completion handler should return YES to dismiss the picker

@interface OAViewPicker : NSWindow
{
    NSBox *_nonretained_highlightBox;
    id _nonretained_parentWindowObserver;
    NSView *_pickedView;
    BOOL _trackingMouse;
    BOOL _isInMouseDown;
    
    OAViewPickerCompletionHandler _completionHandler;
}

+ (void)beginPickingForWindow:(NSWindow *)window withCompletionHandler:(OAViewPickerCompletionHandler)completionHandler;
+ (void)pickView:(NSView *)view;
+ (BOOL)cancelActivePicker; // returns YES if there was a picker session that was canceled

@end
