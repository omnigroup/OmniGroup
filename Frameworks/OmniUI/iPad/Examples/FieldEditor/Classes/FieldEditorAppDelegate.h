//
//  FieldEditorAppDelegate.h
//  FieldEditor
//
//  Created by Timothy J. Wood on 8/12/10.
//  Copyright The Omni Group 2010. All rights reserved.
//

#import <OmniUI/OUIAppController.h>

@class FieldEditorViewController;

@interface FieldEditorAppDelegate : OUIAppController {
    UIWindow *window;
    FieldEditorViewController *viewController;
}

@property (nonatomic, retain) IBOutlet UIWindow *window;
@property (nonatomic, retain) IBOutlet FieldEditorViewController *viewController;

@end

