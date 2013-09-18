// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDocumentStore/ODSItem.h>

#import <OmniDocumentStore/ODSScope.h>

@class ODSScope;

extern NSString * const ODSFileItemFileURLBinding;
extern NSString * const ODSFileItemDownloadRequestedBinding;

extern NSString * const ODSFileItemContentsChangedNotification;
extern NSString * const ODSFileItemFinishedDownloadingNotification;
extern NSString * const ODSFileItemInfoKey;

@interface ODSFileItem : ODSItem <ODSItem>

+ (NSString *)displayNameForFileURL:(NSURL *)fileURL fileType:(NSString *)fileType;
+ (NSString *)editingNameForFileURL:(NSURL *)fileURL fileType:(NSString *)fileType;
+ (NSString *)exportingNameForFileURL:(NSURL *)fileURL fileType:(NSString *)fileType;

- initWithScope:(ODSScope *)scope fileURL:(NSURL *)fileURL isDirectory:(BOOL)isDirectory fileModificationDate:(NSDate *)fileModificationDate userModificationDate:(NSDate *)userModificationDate;

@property(readonly,nonatomic) NSURL *fileURL;
@property(readonly,nonatomic) NSString *fileType;

@property(readonly) NSData *emailData; // packages cannot currently be emailed, so this allows subclasses to return a different content for email
@property(readonly) NSString *emailFilename;

@property(readonly,nonatomic) NSString *editingName;
@property(readonly,nonatomic) NSString *name;
@property(readonly,nonatomic) NSString *exportingName;

@property(copy,nonatomic) NSDate *fileModificationDate; // The modification date of the file on disk, not the user-edited metadata (which might be different for synchronized files).
@property(copy,nonatomic) NSDate *userModificationDate;

- (BOOL)requestDownload:(NSError **)outError;
@property(readonly,assign,nonatomic) BOOL downloadRequested;

@property(assign,nonatomic) BOOL draggingSource;

- (NSComparisonResult)compare:(ODSFileItem *)otherItem;

@end
