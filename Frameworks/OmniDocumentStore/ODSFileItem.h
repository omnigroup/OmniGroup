// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDocumentStore/ODSItem.h>
#import <OmniFoundation/OFFileEdit.h>

@class ODSScope;
@class ODSFileItemEdit;

extern NSString * const ODSFileItemFileURLBinding;
extern NSString * const ODSFileItemDownloadRequestedBinding;

extern NSString * const ODSFileItemContentsChangedNotification;
extern NSString * const ODSFileItemFinishedDownloadingNotification;
extern NSString * const ODSFileItemInfoKey;

@interface ODSFileItemMotion : NSObject

@property(nonatomic,readonly) ODSFileItem *fileItem;
@property(nonatomic,readonly) ODSFileItemEdit *originalItemEdit; // Might be nil for files that haven't been downloaded
@property(nonatomic,readonly) NSURL *sourceFileURL;
@property(nonatomic,readonly) NSURL *destinationFileURL;

@end

@protocol ODSFileItem <NSObject>
@property(readonly,nonatomic) NSURL *fileURL;
@property(copy,nonatomic) OFFileEdit *fileEdit;
@property(readonly,nonatomic) NSString *fileType;
@property(readonly,nonatomic) NSDate *fileModificationDate;
@property(nonatomic,readonly) BOOL isValid;
@property(nonatomic) BOOL isDownloaded;
@property(weak,nonatomic) ODSScope *scope;
- (NSString *)name;
@end

// destinationEditOrNil is nil if the copy failed
typedef void (^ODSScopeItemMotionStatus)(ODSFileItemMotion *itemMotion, NSURL *destinationURL, ODSFileItemEdit *destinationEditOrNil, NSError *errorOrNil);

@interface ODSFileItem : ODSItem <ODSItem, ODSFileItem>

+ (NSString *)displayNameForFileURL:(NSURL *)fileURL fileType:(NSString *)fileType;
+ (NSString *)editingNameForFileURL:(NSURL *)fileURL fileType:(NSString *)fileType;
+ (NSString *)exportingNameForFileURL:(NSURL *)fileURL fileType:(NSString *)fileType;

- initWithScope:(ODSScope *)scope fileURL:(NSURL *)fileURL isDirectory:(BOOL)isDirectory fileEdit:(OFFileEdit *)fileEdit userModificationDate:(NSDate *)userModificationDate;

@property(readonly,nonatomic) NSURL *fileURL;
@property(readonly,nonatomic) NSString *fileType;

@property(readonly) NSData *emailData; // packages cannot currently be emailed, so this allows subclasses to return a different content for email
@property(readonly) NSString *emailFilename;

@property(readonly) NSData *dataForWritingToExternalStorage;  // should be flat file marked as always flat file so desktop doesn't inflate it on edit

@property(readonly,nonatomic) NSString *editingName;
@property(readonly,nonatomic) NSString *name;
@property(readonly,nonatomic) NSString *exportingName;

@property(copy,nonatomic) OFFileEdit *fileEdit; // Information about the last edited state of the file on disk; nil if not present.
@property(readonly,nonatomic) NSDate *fileModificationDate; // Wrapper for fileEdit.fileModificationDate

@property(copy,nonatomic) NSDate *userModificationDate;

- (BOOL)requestDownload:(NSError **)outError;
@property(readonly,assign,nonatomic) BOOL downloadRequested;

@property(assign,nonatomic) BOOL draggingSource;

- (NSComparisonResult)compare:(ODSFileItem *)otherItem;

@end

// A snapshot of the edit information about a file item at the time it was taken.
@interface ODSFileItemEdit : NSObject

+ (instancetype)fileItemEditWithFileItem:(ODSFileItem *)fileItem;

@property(nonatomic,readonly) ODSFileItem *fileItem;
@property(nonatomic,readonly) OFFileEdit *originalFileEdit; // Might be nil for items that haven't been downloaded
@property(nonatomic,readonly) NSURL *originalFileURL;

@end
