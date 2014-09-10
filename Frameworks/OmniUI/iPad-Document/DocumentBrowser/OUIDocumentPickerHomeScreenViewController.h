// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UICollectionViewController.h>

@class OUIDocumentPicker;
@class ODSScope;

@interface OUIDocumentPickerHomeScreenViewController : UITableViewController

- (instancetype)initWithDocumentPicker:(OUIDocumentPicker *)documentPicker;

@property (readonly) OUIDocumentPicker *documentPicker;
@property (readonly) UITableViewCell *selectedCell;

@property (retain) UIView *backgroundView;

- (void)finishedLoading;
- (void)selectCellForScope:(ODSScope *)scope;

// for subclasses
- (NSArray *)additionalScopeItems;
- (void)additionalScopeItemsDidChange;

@property (readonly) NSArray *orderedScopeItems;

@end

extern NSString *const HomeScreenCellReuseIdentifier;
