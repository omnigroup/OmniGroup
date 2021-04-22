// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentInbox.h"

#import <OmniFoundation/OFUTI.h>
#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIErrors.h>
#import <OmniUIDocument/OUIDocumentConvertOnOpen.h>

@implementation OUIDocumentInbox

+ (void)takeInboxItem:(NSURL *)inboxURL completionHandler:(void (^)(NSURL *newFileURL, NSError *errorOrNil))completionHandler;
{
    completionHandler = [completionHandler copy];
    
    __autoreleasing NSError *fileTypeError = nil;
    NSString *fileType = OFUTIForFileURLPreferringNative(inboxURL, &fileTypeError);
    if (!fileType) {
        completionHandler(nil, fileTypeError);
        return;
    }
    
    OUIDocumentAppController *controller = [OUIDocumentAppController controller];
    if (![controller canViewFileTypeWithIdentifier:fileType]) {
        OBASSERT_NOT_REACHED("Delegate says it cannot view file type \"%@\" but is maybe declaring it in its Info.plist", fileType);
        
        NSString *appName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
        OBASSERT(![NSString isEmptyString:appName]);
        
        __autoreleasing NSError *error = nil;
        NSString *title = NSLocalizedStringFromTableInBundle(@"Unable to open file.", @"OmniUIDocument", OMNI_BUNDLE, @"error title");
        NSString *localizedDescription = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ cannot open this type of file.", @"OmniUIDocument", OMNI_BUNDLE, @"error description"), appName];
        NSString *detailedDescription = [NSString stringWithFormat:@"%@ [%@ (%@)]", localizedDescription, inboxURL.lastPathComponent, fileType];
        OUIDocumentError(&error, OUIDocumentErrorCannotMoveItemFromInbox, title, detailedDescription);
        
        completionHandler(nil, error);
        return;
    }
    
    // This deals with read-only files given to us in the Inbox on iOS. <bug:///60499> (OmniGraphSketcher needs to handle read-only files)
    {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        __autoreleasing NSError *attributesError = nil;
        NSDictionary *attributes = [fileManager attributesOfItemAtPath:[[inboxURL absoluteURL] path] error:&attributesError];
        if (!attributes) {
            // Hopefully non-fatal, but worrisome. We'll log it at least....
            NSLog(@"Error getting attributes of \"%@\": %@", [inboxURL absoluteString], [attributesError toPropertyList]);
        } else {
            NSUInteger mode = [attributes filePosixPermissions];
            if ((mode & S_IWUSR) == 0) {
                mode |= S_IWUSR;
                attributesError = nil;
                if (![fileManager setAttributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInteger:mode] forKey:NSFilePosixPermissions] ofItemAtPath:[[inboxURL absoluteURL] path] error:&attributesError]) {
                    NSLog(@"Error setting attributes of \"%@\": %@", [inboxURL absoluteString], [attributesError toPropertyList]);
                }
            }
        }
    }
    
    id <OUIDocumentConvertOnOpen> convertOnOpen;
    if ([controller conformsToProtocol:@protocol(OUIDocumentConvertOnOpen)]) {
        convertOnOpen = (id <OUIDocumentConvertOnOpen>)controller;
    }
    
    if (convertOnOpen && [convertOnOpen shouldOpenFileTypeForConversion:fileType]) {
        [convertOnOpen saveConvertedFileIfAppropriateFromFileURL:inboxURL completionHandler:^(NSURL *savedFileURL, NSError *errorOrNil) {
            OBFinishPorting;
#if 0
            [docPicker.documentStore moveItems:[NSSet setWithObject:savedItem] fromScope:currentScope toScope:scope inFolder:scope.rootFolder completionHandler:^(NSSet *movedFileItems, NSArray *errorsOrNil) {
                finishedBlock([movedFileItems anyObject], [errorsOrNil firstObject]);
            }];
#endif
        }];
        return;
    }
    
    NSURL *availableURL;
    {
        NSURL *documentDirectoryURL = OUIDocumentAppController.sharedController.localDocumentsURL;
        NSURL *desiredURL = [documentDirectoryURL URLByAppendingPathComponent:[inboxURL lastPathComponent]];
        __autoreleasing NSError *error = nil;
        NSString *availablePath = [[NSFileManager defaultManager] uniqueFilenameFromName:[[desiredURL absoluteURL] path] allowOriginal:YES create:NO error:&error];
        if (availablePath == nil) {
            completionHandler(nil, error);
            return;
        }
        availableURL = [NSURL fileURLWithPath:availablePath];
    }

    
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    
    // Using deleting here since nothing should really be keeping a reference to the source file from the Inbox, even if we end up moving it.
    NSFileAccessIntent *sourceIntent = [NSFileAccessIntent writingIntentWithURL:inboxURL options:NSFileCoordinatorWritingForDeleting];
    
    // Merging to make other presenters save instead of thinking that their file (if racing with us) will be deleted (we want to get an error if there is a race condition rather than overwriting the destination).
    NSFileAccessIntent *destinationIntent = [NSFileAccessIntent writingIntentWithURL:availableURL options:NSFileCoordinatorWritingForMerging];
    
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    [coordinator coordinateAccessWithIntents:@[sourceIntent, destinationIntent] queue:queue byAccessor:^(NSError * _Nullable coordinationError) {
        if (coordinationError) {
            completionHandler(nil, coordinationError);
            return;
        }
            
        __autoreleasing NSError *copyError;
        if (![[NSFileManager defaultManager] moveItemAtURL:sourceIntent.URL toURL:destinationIntent.URL error:&copyError]) {
            completionHandler(nil, copyError);
        }
            
        completionHandler(availableURL, nil);
    }];
}

@end
