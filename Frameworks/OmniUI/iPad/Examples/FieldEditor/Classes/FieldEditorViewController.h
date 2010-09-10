//
//  FieldEditorViewController.h
//  FieldEditor
//
//  Created by Timothy J. Wood on 8/12/10.
//  Copyright The Omni Group 2010. All rights reserved.
//

#import <UIKit/UIKit.h>

@class TextLayoutView, OUIEditableFrame;

@interface FieldEditorViewController : UIViewController
{
@private
    NSAttributedString *_text;
    TextLayoutView *_textLayoutView;
    OUIEditableFrame *_editableFrame;
}

- (IBAction)toggleEditor:(id)sender;

@end

