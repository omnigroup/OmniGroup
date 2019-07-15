// Copyright 2005-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <CoreFoundation/CFString.h>

typedef struct _OFXMLBuffer *OFXMLBuffer;

extern OFXMLBuffer OFXMLBufferCreate(void);
extern void OFXMLBufferDestroy(OFXMLBuffer buf);

extern void OFXMLBufferAppendString(OFXMLBuffer buf, CFStringRef str);
extern void OFXMLBufferAppendUTF8CString(OFXMLBuffer buf, const char *str);
extern void OFXMLBufferAppendQuotedUTF8CString(OFXMLBuffer buf, const char *unquotedString);

extern void OFXMLBufferAppendUTF8Bytes(OFXMLBuffer buf, const char *str, size_t byteCount);
extern void OFXMLBufferAppendSpaces(OFXMLBuffer buf, CFIndex count);

extern void OFXMLBufferAppendUTF8Data(OFXMLBuffer buf, CFDataRef data);

extern CFDataRef OFXMLBufferCopyData(OFXMLBuffer buf, CFStringEncoding encoding);
extern CFStringRef OFXMLBufferCopyString(OFXMLBuffer buf);
