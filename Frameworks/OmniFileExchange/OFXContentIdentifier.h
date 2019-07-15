// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

// Utilities for debug logs
extern NSString *OFXContentIdentifierForURL(NSURL *fileURL, NSError **outError);
extern NSString *OFXContentIdentifierForContents(NSDictionary *contents);
extern void OFXRegisterDisplayNameForContentAtURL(NSURL *fileURL, NSString *displayName);
extern NSString *OFXLookupDisplayNameForContentIdentifier(NSString *contentIdentifier);

extern void _OFXNoteContentChanged(id self, const char *file, unsigned line, NSURL *fileURL);
extern void _OFXNoteContentDeleted(id self, const char *file, unsigned line, NSURL *fileURL);
extern void _OFXNoteContentMoved(id self, const char *file, unsigned line, NSURL *sourceURL, NSURL *destURL);

#define OFXNoteContentChanged(self, fileURL) _OFXNoteContentChanged(self, __FILE__, __LINE__, fileURL);
#define OFXNoteContentDeleted(self, fileURL) _OFXNoteContentDeleted(self, __FILE__, __LINE__, fileURL);
#define OFXNoteContentMoved(self, sourceURL, destURL) _OFXNoteContentMoved(self, __FILE__, __LINE__, sourceURL, destURL);
