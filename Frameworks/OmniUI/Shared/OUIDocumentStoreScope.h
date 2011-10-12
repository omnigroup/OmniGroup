// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

typedef enum {
    OUIDocumentStoreScopeUnknown = -1, // Somewhere else -- iCloud will move deleted documents to a private place before deletion, for example
    OUIDocumentStoreScopeLocal, // Inside ~/Documents on iPad, for example
    OUIDocumentStoreScopeUbiquitous, // Inside the applications iCloud container, under Documents.
} OUIDocumentStoreScope;


