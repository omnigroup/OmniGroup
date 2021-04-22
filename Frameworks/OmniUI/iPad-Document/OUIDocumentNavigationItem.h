// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UINavigationBar.h>

@class OUIDocument;

@interface OUIDocumentNavigationItem : UINavigationItem

@property (nonatomic, weak, readonly) OUIDocument *document;

- (instancetype)initWithDocument:(OUIDocument *)document;

- (void)documentWillClose;

@property(nonatomic,strong) UIColor *titleColor;
@property(nonatomic,assign) BOOL hideTitle;
/*!
 * @brief Causes the navigation item to leave 'rename mode'.
 * @return YES if the navigation item successfully returned to normal mode. If called, while in normal mode it will return YES. NO otherwise.
 */
- (BOOL)endRenaming;

@end

// UserInfo Keys
extern NSString * const OUIDocumentNavigationItemNewDocumentNameUserInfoKey;
extern NSString * const OUIDocumentNavigationItemOriginalDocumentNameUserInfoKey;
