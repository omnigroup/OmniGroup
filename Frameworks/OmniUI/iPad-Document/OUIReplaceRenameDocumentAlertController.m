// Copyright 2016-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIReplaceRenameDocumentAlertController.h>

#import <OmniDAV/ODAVFileInfo.h>

RCS_ID("$Id$")

@implementation OUIReplaceRenameDocumentAlertController

+ (instancetype)replaceRenameAlertForURL:(NSURL *)aURL withCancelHandler:(void (^)(void))cancel replaceHandler:(void (^)(void))replace renameHandler:(void (^)(void))rename
{
    NSString *urlName = [ODAVFileInfo nameForURL:aURL];
    
    NSString *message = [NSString stringWithFormat: NSLocalizedStringFromTableInBundle(@"A document with the name \"%@\" already exists. Do you want to replace it? This cannot be undone.", @"OmniUIDocument", OMNI_BUNDLE, @"replace document description"), urlName];
    
    NSString *title = NSLocalizedStringFromTableInBundle(@"Replace document?", @"OmniUIDocument", OMNI_BUNDLE, @"replace document title");

    OUIReplaceRenameDocumentAlertController *controller = [super alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    
    [controller addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUIDocument", OMNI_BUNDLE, @"cancel button title") style:UIAlertActionStyleCancel handler:^(UIAlertAction * __nonnull action) {
        if (cancel) {
            cancel();
        }
    }]];
    [controller addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Replace", @"OmniUIDocument", OMNI_BUNDLE, @"replace button title") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * __nonnull action) {
        if (replace) {
            replace();
        }
    }]];
    [controller addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Rename",@"OmniUIDocument", OMNI_BUNDLE, @"rename button title") style:UIAlertActionStyleDefault handler:^(UIAlertAction * __nonnull action) {
        if (rename) {
            rename();
        }
    }]];
    
    return controller;
}

@end
