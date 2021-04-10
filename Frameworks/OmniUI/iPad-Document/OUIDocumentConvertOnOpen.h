// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

NS_ASSUME_NONNULL_BEGIN

// Some file types we accept we don't edit in place, but will convert them to a new file type.
// Right now, the OUIDocumentAppController can conform to this.
@protocol OUIDocumentConvertOnOpen
- (BOOL)shouldOpenFileTypeForConversion:(NSString *)fileType;
- (void)saveConvertedFileIfAppropriateFromFileURL:(NSURL *)fileURL completionHandler:(void (^)(NSURL * _Nullable savedFileURL, NSError * _Nullable errorOrNil))completionBlock;
@end

NS_ASSUME_NONNULL_END
