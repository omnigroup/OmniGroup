// Copyright 2003-2005, 2007-2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

// const char * -> NSString
typedef struct _OFXMLInteredStringTable *OFXMLInternedStringTable;
extern OFXMLInternedStringTable OFXMLInternedStringTableCreate(NSSet *startingStrings);
extern void OFXMLInternedStringTableFree(OFXMLInternedStringTable table);
extern NSString *OFXMLInternedStringTableGetInternedString(OFXMLInternedStringTable table, const char *str);

// (const char *, const char *) -> OFXMLQName
@class OFXMLQName;
typedef struct _OFXMLInternedNameTable *OFXMLInternedNameTable;
extern OFXMLInternedNameTable OFXMLInternedNameTableCreate(OFXMLInternedNameTable startingQNameTable);
extern void OFXMLInternedNameTableFree(OFXMLInternedNameTable table);
extern OFXMLQName *OFXMLInternedNameTableGetInternedName(OFXMLInternedNameTable table, const char *_namespace, const char *name);
