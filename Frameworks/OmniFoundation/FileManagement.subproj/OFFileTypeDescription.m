// Copyright 2010-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFFileTypeDescription.h>

RCS_ID("$Id$");

#import <OmniFoundation/OFUTI.h>

NS_ASSUME_NONNULL_BEGIN

OB_REQUIRE_ARC

@implementation OFFileTypeDescription

- initWithFileType:(NSString *)fileType;
{
    // TODO: Update this to prefer the application's built-in UTTypes instead of depending on LaunchServices to do the right thing.

    _fileType = [[fileType lowercaseString] copy];

    _pathExtensions = [CFBridgingRelease(UTTypeCopyAllTagsWithClass((__bridge CFStringRef)fileType, kUTTagClassFilenameExtension)) copy];
    if (_pathExtensions == nil) {
        _pathExtensions = @[];
    }

    _displayName = [CFBridgingRelease(UTTypeCopyDescription((__bridge CFStringRef)fileType)) copy];
    if (_displayName == nil) {
        _displayName = _fileType;
    }

    return self;
}

- (NSUInteger)hash;
{
    return [_fileType hash];
}

- (BOOL)isEqual:(id)object;
{
    if (![object isKindOfClass:[OFFileTypeDescription class]])
        return NO;
    OFFileTypeDescription *otherDesc = object;
    return [_fileType isEqual:otherDesc.fileType];
}

+ (OFFileTypeDescription *)plainText;
{
    return [[OFFileTypeDescription alloc] initWithFileType:(__bridge NSString *)kUTTypePlainText];
}

@end

NS_ASSUME_NONNULL_END
