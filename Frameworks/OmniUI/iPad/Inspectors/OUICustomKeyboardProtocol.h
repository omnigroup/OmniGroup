//
//  OUICustomKeyboard.h
//  OmniUI
//
//  Created by Greg Titus on 3/16/12.
//  Copyright (c) 2012 The Omni Group. All rights reserved.
//

#import <Foundation/Foundation.h>

@class OUIInspectorTextWell, UIView;

@protocol OUICustomKeyboard <NSObject>
- (void)editInspectorTextWell:(OUIInspectorTextWell *)aTextWell;
- (UIView *)inputView;
- (UIView *)inputAccessoryView;
- (BOOL)shouldUseTextEditor;
@end
