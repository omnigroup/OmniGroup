// Copyright 2017-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@class OUITemplatePicker, OUITemplateItem;
@class UIView;
@class NSURL;

@protocol OUITemplatePickerDelegate
- (void)templatePicker:(OUITemplatePicker *)templatePicker didSelectTemplateURL:(NSURL *)templateURL animateFrom:(UIView *)fromView;
- (void)templatePickerDidCancel:(OUITemplatePicker *)templatePicker;
@optional
- (NSArray<NSString *> *)templateUTIs;
@end


