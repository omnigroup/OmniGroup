// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>
#import "OUISyncMenuController.h"

enum {
    OUIExportOptionsExport,
    OUIExportOptionsEmail,
}; 
typedef NSUInteger OUIExportOptionsType;

@class OUIExportOptionsView;
@interface OUIExportOptionsController : UIViewController
{
@private
    OUIExportOptionsView *_exportView;
    UILabel *_exportDescriptionLabel;
    UILabel *_exportDestinationLabel;
    
    OUISyncType _syncType;
    OUIExportOptionsType _exportType;
}

- (id)initWithExportType:(OUIExportOptionsType)exportType;
- (void)exportData:(NSData *)data toFileNamed:(NSString *)filename;
- (void)signOut:(id)sender;

@property(nonatomic, retain) IBOutlet OUIExportOptionsView *exportView;
@property(nonatomic, retain) IBOutlet UILabel *exportDescriptionLabel;
@property(nonatomic, retain) IBOutlet UILabel *exportDestinationLabel;

@property (nonatomic, assign) OUISyncType syncType;

@end
