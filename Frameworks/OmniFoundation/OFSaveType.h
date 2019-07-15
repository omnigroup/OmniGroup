// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Availability.h>

// THESE MUST MATCH APPKIT: In NSDocument-OAExtensions.h we add a mapping function, but we need some sort of symbol for this concept to share in model-level code for Mac/iPhone compatibility. Has slightly different names (for now at least), but they have the same meaning as their NSDocument-defined counterparts.
typedef NS_ENUM(NSUInteger, OFSaveType) {
    OFSaveTypeReplaceExisting, // NSSaveOperation
    OFSaveTypeNew, // NSSaveAsOperation
    OFSaveTypeExport, // NSSaveToOperation
    OFSaveTypeAutosaveElsewhere, // NSAutosaveElsewhereOperation
    OFSaveTypeAutosaveInPlace, // NSAutosaveInPlaceOperation
};
